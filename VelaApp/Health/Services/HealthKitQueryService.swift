import Foundation
@preconcurrency import HealthKit

struct HeartRateRecoverySample: Hashable, Sendable {
    var date: Date
    var bpm: Double
}

enum WorkoutHeartRateRecoveryMatcher {
    static func match(
        samples: [HeartRateRecoverySample],
        workouts: [WorkoutSummary],
        maximumDelay: TimeInterval = 6 * 3_600
    ) -> [UUID: Double] {
        var available = samples.filter { $0.bpm.isFinite && $0.bpm >= 0 }.sorted { $0.date < $1.date }
        var result: [UUID: Double] = [:]

        for workout in workouts.sorted(by: { $0.end < $1.end }) {
            let earliest = workout.end.addingTimeInterval(-15 * 60)
            let latest = workout.end.addingTimeInterval(maximumDelay)
            guard let candidate = available.enumerated()
                .filter({ $0.element.date >= earliest && $0.element.date <= latest })
                .min(by: {
                    abs($0.element.date.timeIntervalSince(workout.end))
                        < abs($1.element.date.timeIntervalSince(workout.end))
                }) else { continue }
            result[workout.id] = candidate.element.bpm
            available.remove(at: candidate.offset)
        }
        return result
    }
}

final class HealthKitQueryService: HealthQueryService {
    private let healthStore: HKHealthStore
    private(set) var diagnostics: [HealthQueryDiagnostic] = []

    init(healthStore: HKHealthStore = HealthStoreProvider.shared) {
        self.healthStore = healthStore
    }

    func consumeDiagnostics() -> [HealthQueryDiagnostic] {
        defer { diagnostics.removeAll(keepingCapacity: true) }
        return diagnostics
    }

    private func recordDiagnostic(
        component: String,
        error: Error
    ) {
        diagnostics.append(HealthQueryDiagnostic(
            component: component,
            outcome: HealthKitQueryOutcomeClassifier.classify(error),
            error: error
        ))
    }

    /// HealthKit signals "this range simply has no samples" by throwing, not by
    /// returning an empty result. Identify that benign condition by `HKError.Code`
    /// only — never by `localizedDescription`, whose wording changes with the
    /// system language and across iOS releases. Matching on localized text turned
    /// a normal empty day into a thrown sync error on non-English devices.
    nonisolated static func isBenignHealthKitDataError(_ error: Error) -> Bool {
        HealthKitQueryOutcomeClassifier.classify(error) == .noData
    }

    func sleepSummary(in range: DateRangeQuery) async throws -> SleepSummary? {
        guard let sleepType = HealthSignalCatalog.objectType(for: .sleepAnalysis) as? HKCategoryType else {
            return nil
        }

        // 主睡眠段按样本 startDate 匹配查询窗：把窗口向前扩展 12 小时以捕获
        // 前夜入睡段（如 23:00 入睡、次日 07:00 醒），归属由 mainNightSummary
        // 按「主睡眠段结束时刻落在目标窗口内」判定，避免夜晚被 04:00 边界截断拆进两天。
        let extended = DateRangeQuery(
            start: range.start.addingTimeInterval(-12 * 3_600),
            end: range.end
        )
        let samples = try await categorySamples(type: sleepType, range: extended)
        let segments = samples.map {
            SleepStageSegment(
                stage: HealthKitSleepStageMapper.map($0.value),
                start: $0.startDate,
                end: $0.endDate
            )
        }

        return SleepSampleNormalizer.mainNightSummary(in: range, segments: segments)
    }

    func sleepEpisodes(in range: DateRangeQuery) async throws -> [SleepSummary] {
        guard let sleepType = HealthSignalCatalog.objectType(for: .sleepAnalysis) as? HKCategoryType else {
            return []
        }

        // 与 sleepSummary 一致：查询窗向前扩展 12h，避免跨 04:00 边界的夜晚被截断；
        // 结果按主睡眠段结束时刻过滤回原始窗口。
        let expanded = DateRangeQuery(
            start: range.start.addingTimeInterval(-12 * 3_600),
            end: range.end
        )
        let samples = try await categorySamples(type: sleepType, range: expanded)
        let segments = samples.map {
            SleepStageSegment(
                stage: HealthKitSleepStageMapper.map($0.value),
                start: $0.startDate,
                end: $0.endDate
            )
        }

        return SleepSampleNormalizer.allNightlyEpisodes(segments: segments).filter { episode in
            guard let wake = episode.wakeTime else { return true }
            return wake >= range.start && wake < range.end
        }
    }

    func recoveryMetrics(in range: DateRangeQuery) async throws -> RecoveryMetricSummary {
        async let hrv = averageQuantity(.hrvSDNN, unit: .secondUnit(with: .milli), range: range)
        async let rhr = averageQuantity(.restingHR, unit: HKUnit.count().unitDivided(by: .minute()), range: range)
        async let sleepHR = sleepHeartRate(in: range)
        async let respiratoryRate = averageQuantity(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()), range: range)

        return try await RecoveryMetricSummary(
            hrvMilliseconds: hrv,
            // HealthKit 仅暴露 SDNN（heartRateVariabilitySDNN），不存在 RMSSD 采样标识符。
            // RMSSD 是派生模型输入：PSTI 管道在 RMSSD 缺失时回退 SDNN（见 RecoveryScoreEngine），
            // 此处保持 nil 是有意为之，勿改为伪造采样。
            hrvRmssdMilliseconds: nil,
            restingHeartRate: rhr,
            sleepHeartRate: sleepHR,
            respiratoryRate: respiratoryRate
        )
    }

    func strainSummary(in range: DateRangeQuery) async throws -> StrainActivitySummary {
        try await StrainActivitySummary(
            activeEnergyKilocalories: sumQuantity(.activeEnergy, unit: .kilocalorie(), range: range),
            exerciseMinutes: sumQuantity(.exerciseTime, unit: .minute(), range: range),
            stepCount: sumQuantity(.stepCount, unit: .count(), range: range),
            workouts: workoutSummaries(in: range)
        )
    }

    func bodyMetrics(in range: DateRangeQuery) async throws -> BodyMetricsSummary {
        let bodyRange = DateRangeQuery(
            start: Calendar.current.date(byAdding: .day, value: -60, to: range.end) ?? range.start,
            end: range.end
        )
        return try await BodyMetricsSummary(
            vo2Max: mostRecentQuantity(.vo2Max, unit: HKUnit(from: "ml/kg*min"), range: bodyRange),
            weightKilograms: mostRecentQuantity(.bodyMass, unit: .gramUnit(with: .kilo), range: bodyRange),
            bodyFatPercentage: mostRecentQuantity(.bodyFatPercentage, unit: .percent(), range: bodyRange),
            leanBodyMassKilograms: mostRecentQuantity(.leanBodyMass, unit: .gramUnit(with: .kilo), range: bodyRange)
        )
    }

    private func categorySamples(type: HKCategoryType, range: DateRangeQuery) async throws -> [HKCategorySample] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: range.start,
                end: range.end,
                options: []
            )
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    if Self.isBenignHealthKitDataError(error) {
                        continuation.resume(returning: [])
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                continuation.resume(returning: samples?.compactMap { $0 as? HKCategorySample } ?? [])
            }
            healthStore.execute(query)
        }
    }

    private func sumQuantity(_ signal: HealthSignal, unit: HKUnit, range: DateRangeQuery) async throws -> Double? {
        try await statisticsQuantity(signal, unit: unit, options: .cumulativeSum, range: range)
    }

    private func averageQuantity(_ signal: HealthSignal, unit: HKUnit, range: DateRangeQuery) async throws -> Double? {
        try await statisticsQuantity(signal, unit: unit, options: .discreteAverage, range: range)
    }

    private func statisticsQuantity(
        _ signal: HealthSignal,
        unit: HKUnit,
        options: HKStatisticsOptions,
        range: DateRangeQuery
    ) async throws -> Double? {
        guard let quantityType = HealthSignalCatalog.objectType(for: signal) as? HKQuantityType else {
            return nil
        }

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: range.start,
                end: range.end,
                options: []
            )
            let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: options) { _, statistics, error in
                if let error {
                    if Self.isBenignHealthKitDataError(error) {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                let quantity = options.contains(.cumulativeSum) ? statistics?.sumQuantity() : statistics?.averageQuantity()
                continuation.resume(returning: quantity?.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    private func mostRecentQuantity(_ signal: HealthSignal, unit: HKUnit, range: DateRangeQuery) async throws -> Double? {
        guard let quantityType = HealthSignalCatalog.objectType(for: signal) as? HKQuantityType else {
            return nil
        }

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: range.start,
                end: range.end,
                options: []
            )
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    if Self.isBenignHealthKitDataError(error) {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                let sample = samples?.first as? HKQuantitySample
                continuation.resume(returning: sample?.quantity.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    /// 指定日期窗口内的训练摘要（含心率/恢复心率）——热力图/近期列表用。
    func workoutSummaries(in range: DateRangeQuery) async throws -> [WorkoutSummary] {
        guard let workoutType = HealthSignalCatalog.objectType(for: .workouts) as? HKWorkoutType else {
            return []
        }
        let rawWorkouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            // strictStartDate：训练按 startDate 归属健康日（与 dayIdentifier/聚合语义一致）。
            // 默认 overlap 谓词会让跨午夜训练（23:30–00:30）同时落入两天查询，
            // 在次日聚合时被当作独立 HK 摘要追加 → 时长/负荷双计。
            let predicate = HKQuery.predicateForSamples(
                withStart: range.start,
                end: range.end,
                options: [.strictStartDate]
            )
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    if Self.isBenignHealthKitDataError(error) {
                        continuation.resume(returning: [])
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            healthStore.execute(query)
        }

        async let heartRatesTask = averageHeartRates(for: rawWorkouts)
        async let recoveriesTask = heartRateRecoveries(for: rawWorkouts)
        let heartRates: [UUID: Double]
        do {
            heartRates = try await heartRatesTask
        } catch {
            recordDiagnostic(component: "workouts.averageHeartRate", error: error)
            heartRates = [:]
        }
        let recoveries: [UUID: Double]
        do {
            recoveries = try await recoveriesTask
        } catch {
            recordDiagnostic(component: "workouts.heartRateRecovery", error: error)
            recoveries = [:]
        }
        var summaries: [WorkoutSummary] = []
        for workout in rawWorkouts {
            summaries.append(WorkoutSummary(
                id: workout.uuid,
                start: workout.startDate,
                end: workout.endDate,
                activityName: workout.workoutActivityType.displayName,
                energyKilocalories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                averageHeartRate: heartRates[workout.uuid],
                heartRateRecoveryOneMinuteBPM: recoveries[workout.uuid],
                distanceMeters: workout.totalDistance?.doubleValue(for: .meter())
            ))
        }
        return summaries
    }

    // MARK: - Extended Metrics (30+ types)

    func extendedMetrics(in range: DateRangeQuery) async throws -> ExtendedHealthMetrics {
        var m = ExtendedHealthMetrics()

        // Personal characteristics (no range needed)
        let chars = queryCharacteristics()
        m.age = chars.age
        m.biologicalSex = chars.biologicalSex

        // Body (use 60-day lookback for body measurements)
        let bodyRange = DateRangeQuery(
            start: Calendar.current.date(byAdding: .day, value: -60, to: range.end) ?? range.start,
            end: range.end
        )

        // 性能：约 20 个相互独立的 HealthKit 查询并行发起——
        // 此前逐行串行 await，下拉刷新总耗时 = 查询数 × 单查询耗时。
        async let heightCm = mostRecentQuantity(.height, unit: .meterUnit(with: .centi), range: bodyRange)
        async let bmi = mostRecentQuantity(.bodyMassIndex, unit: .count(), range: bodyRange)
        async let bodyWeightKg = mostRecentQuantity(.bodyMass, unit: .gramUnit(with: .kilo), range: bodyRange)
        async let bodyFatPercent = mostRecentQuantity(.bodyFatPercentage, unit: .percent(), range: bodyRange)

        // Cardiovascular
        async let walkingHeartRateAvg = averageQuantity(.walkingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), range: range)
        async let oxygenSaturation = mostRecentQuantity(.oxygenSaturation, unit: .percent(), range: range)
        async let bloodPressureSystolic = mostRecentQuantity(.bloodPressureSystolic, unit: .millimeterOfMercury(), range: range)
        async let bloodPressureDiastolic = mostRecentQuantity(.bloodPressureDiastolic, unit: .millimeterOfMercury(), range: range)

        // Metabolic
        async let bloodGlucose = mostRecentQuantity(.bloodGlucose, unit: HKUnit(from: "mg/dL"), range: range)

        // Mobility & gait
        async let walkingSpeed = averageQuantity(.walkingSpeed, unit: HKUnit.meter().unitDivided(by: .second()), range: range)
        async let walkingAsymmetry = averageQuantity(.walkingAsymmetry, unit: .percent(), range: range)
        async let walkingDoubleSupport = averageQuantity(.doubleSupport, unit: .percent(), range: range)

        // Activity totals
        async let exerciseMinutes = sumQuantity(.exerciseTime, unit: .minute(), range: range)
        async let flightsClimbed = sumQuantity(.flightsClimbed, unit: .count(), range: range)

        // Environment
        async let environmentalNoisedB = averageQuantity(.envNoise, unit: .decibelAWeightedSoundPressureLevel(), range: range)
        async let timeInDaylight = sumQuantity(.daylight, unit: .minute(), range: range)

        // Apple Watch records nightly wrist temperature separately from manually-entered
        // body temperature. Prefer the wearable signal and fall back only if absent.
        async let wristTemperature = mostRecentQuantity(.wristTemperature, unit: .degreeCelsius(), range: range)
        async let bodyTemperatureFallback = mostRecentQuantity(.bodyTemperature, unit: .degreeCelsius(), range: range)

        // Nutrition（开关门控：关闭时直接 nil，不发起查询）
        async let waterMl = sumQuantity(.water, unit: .literUnit(with: .milli), range: range)
        async let caffeineMg = sumQuantity(.caffeine, unit: .gramUnit(with: .milli), range: range)
        async let dietaryEnergyKcal = VelaFeatureFlags.nutritionEnabled
            ? sumQuantity(.dietaryEnergy, unit: .kilocalorie(), range: range) : nil
        async let dietaryProteinG = VelaFeatureFlags.nutritionEnabled
            ? sumQuantity(.dietaryProtein, unit: .gram(), range: range) : nil
        async let dietaryCarbsG = VelaFeatureFlags.nutritionEnabled
            ? sumQuantity(.dietaryCarbohydrates, unit: .gram(), range: range) : nil
        async let dietaryFatG = VelaFeatureFlags.nutritionEnabled
            ? sumQuantity(.dietaryFat, unit: .gram(), range: range) : nil

        // Wellness
        async let mindfulMinutesValue = mindfulMinutes(in: range)
        async let sleepBreathingDisturbancesValue = sleepBreathingDisturbancesAverage(in: range)

        do { m.heightCm = try await heightCm } catch { recordDiagnostic(component: "extended.height", error: error) }
        do { m.bmi = try await bmi } catch { recordDiagnostic(component: "extended.bmi", error: error) }
        do { m.bodyWeightKg = try await bodyWeightKg } catch { recordDiagnostic(component: "extended.bodyWeight", error: error) }
        do { m.bodyFatPercent = try await bodyFatPercent } catch { recordDiagnostic(component: "extended.bodyFat", error: error) }

        do { m.walkingHeartRateAvg = try await walkingHeartRateAvg } catch { recordDiagnostic(component: "extended.walkingHeartRate", error: error) }
        do { m.oxygenSaturation = try await oxygenSaturation } catch { recordDiagnostic(component: "extended.oxygenSaturation", error: error) }
        do { m.bloodPressureSystolic = try await bloodPressureSystolic } catch { recordDiagnostic(component: "extended.bloodPressureSystolic", error: error) }
        do { m.bloodPressureDiastolic = try await bloodPressureDiastolic } catch { recordDiagnostic(component: "extended.bloodPressureDiastolic", error: error) }

        do { m.bloodGlucose = try await bloodGlucose } catch { recordDiagnostic(component: "extended.bloodGlucose", error: error) }

        do { m.walkingSpeed = try await walkingSpeed } catch { recordDiagnostic(component: "extended.walkingSpeed", error: error) }
        do { m.walkingAsymmetry = try await walkingAsymmetry } catch { recordDiagnostic(component: "extended.walkingAsymmetry", error: error) }
        do { m.walkingDoubleSupport = try await walkingDoubleSupport } catch { recordDiagnostic(component: "extended.doubleSupport", error: error) }

        do { m.exerciseMinutes = (try await exerciseMinutes).map { Int($0) } } catch { recordDiagnostic(component: "extended.exerciseMinutes", error: error) }
        do { m.flightsClimbed = (try await flightsClimbed).map { Int($0) } } catch { recordDiagnostic(component: "extended.flightsClimbed", error: error) }

        do { m.environmentalNoisedB = try await environmentalNoisedB } catch { recordDiagnostic(component: "extended.environmentalNoise", error: error) }
        do { m.timeInDaylight = try await timeInDaylight } catch { recordDiagnostic(component: "extended.daylight", error: error) }

        do {
            let wrist = try await wristTemperature
            m.bodyTemperature = wrist
        } catch {
            recordDiagnostic(component: "extended.wristTemperature", error: error)
            do { m.bodyTemperature = try await bodyTemperatureFallback } catch { recordDiagnostic(component: "extended.bodyTemperature", error: error) }
        }

        do { m.waterMl = try await waterMl } catch { recordDiagnostic(component: "extended.water", error: error) }
        do { m.caffeineMg = try await caffeineMg } catch { recordDiagnostic(component: "extended.caffeine", error: error) }
        if VelaFeatureFlags.nutritionEnabled {
            do { m.dietaryEnergyKcal = try await dietaryEnergyKcal } catch { recordDiagnostic(component: "extended.dietaryEnergy", error: error) }
            do { m.dietaryProteinG = try await dietaryProteinG } catch { recordDiagnostic(component: "extended.dietaryProtein", error: error) }
            do { m.dietaryCarbsG = try await dietaryCarbsG } catch { recordDiagnostic(component: "extended.dietaryCarbohydrates", error: error) }
            do { m.dietaryFatG = try await dietaryFatG } catch { recordDiagnostic(component: "extended.dietaryFat", error: error) }
        }

        do { m.mindfulMinutes = try await mindfulMinutesValue } catch { recordDiagnostic(component: "extended.mindfulMinutes", error: error) }
        do { m.sleepBreathingDisturbances = try await sleepBreathingDisturbancesValue } catch { recordDiagnostic(component: "extended.sleepBreathingDisturbances", error: error) }

        return m
    }

    /// 正念分钟（品类样本时长求和；无数据/失败返回 nil）。
    private func mindfulMinutes(in range: DateRangeQuery) async throws -> Double? {
        guard let mindfulType = HealthSignalCatalog.objectType(for: .mindfulSession) as? HKCategoryType else {
            return nil
        }
        let mindfulSamples = try await categorySamples(type: mindfulType, range: range)
        let totalMinutes = mindfulSamples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 60.0
        return totalMinutes > 0 ? totalMinutes : nil
    }

    /// 睡眠呼吸紊乱均值（iOS 18+；低版本直接 nil，不发起查询）。
    private func sleepBreathingDisturbancesAverage(in range: DateRangeQuery) async throws -> Double? {
        guard #available(iOS 18.0, *) else { return nil }
        return try await averageQuantity(
            .sleepBreathingDisturbances,
            unit: HKUnit.count().unitDivided(by: .hour()),
            range: range
        )
    }

    func hrvHistory(in range: DateRangeQuery) async throws -> [Double] {
        try await hrvDailyAverages(in: range)
    }

    /// Fetch daily average HRV values using HKStatisticsCollectionQuery.
    /// Returns one value per day (discrete average) instead of all raw samples.
    private func hrvDailyAverages(in range: DateRangeQuery) async throws -> [Double] {
        guard let quantityType = HealthSignalCatalog.objectType(for: .hrvSDNN) as? HKQuantityType else {
            return []
        }

        return try await withCheckedThrowingContinuation { continuation in
            // 锚定到健康日边界（04:00），使日分桶与调用方的健康日窗口一致；
            // 此前锚 1970 本地午夜，分桶与健康日归属差 4 小时。
            let anchor = HealthDayBoundary(calendar: Calendar.current)
                .labelDate(containing: range.start)
            let predicate = HKQuery.predicateForSamples(
                withStart: range.start,
                end: range.end,
                options: []
            )
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, results, error in
                if let error {
                    if Self.isBenignHealthKitDataError(error) {
                        continuation.resume(returning: [])
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                var values: [Double] = []
                results?.enumerateStatistics(from: range.start, to: range.end) { statistics, _ in
                    if let avg = statistics.averageQuantity() {
                        let value = avg.doubleValue(for: .secondUnit(with: .milli))
                        values.append(value)
                    }
                }
                continuation.resume(returning: values)
            }
            healthStore.execute(query)
        }
    }

    func rhrHistory(in range: DateRangeQuery) async throws -> [Double] {
        try await rhrDailyAverages(in: range)
    }

    /// Fetch daily average RHR values using HKStatisticsCollectionQuery.
    private func rhrDailyAverages(in range: DateRangeQuery) async throws -> [Double] {
        guard let quantityType = HealthSignalCatalog.objectType(for: .restingHR) as? HKQuantityType else {
            return []
        }

        return try await withCheckedThrowingContinuation { continuation in
            let anchor = HealthDayBoundary(calendar: Calendar.current)
                .labelDate(containing: range.start)
            let predicate = HKQuery.predicateForSamples(
                withStart: range.start,
                end: range.end,
                options: []
            )
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, results, error in
                if let error {
                    if Self.isBenignHealthKitDataError(error) {
                        continuation.resume(returning: [])
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                var values: [Double] = []
                results?.enumerateStatistics(from: range.start, to: range.end) { statistics, _ in
                    if let avg = statistics.averageQuantity() {
                        let value = avg.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                        values.append(value)
                    }
                }
                continuation.resume(returning: values)
            }
            healthStore.execute(query)
        }
    }

    /// Read HKCharacteristicType values (age, sex) — these don't need time ranges
    func queryCharacteristics() -> (age: Int?, biologicalSex: String?) {
        var age: Int?
        var sex: String?

        if let dob = try? healthStore.dateOfBirthComponents() {
            if let year = dob.year {
                age = Calendar.current.component(.year, from: Date()) - year
            }
        }

        if let bioSex = try? healthStore.biologicalSex().biologicalSex {
            switch bioSex {
            case .male: sex = "male"
            case .female: sex = "female"
            case .other: sex = "other"
            default: sex = nil
            }
        }

        return (age, sex)
    }

    func recentWorkouts(limit: Int) async throws -> [WorkoutSummary] {
        guard let workoutType = HealthSignalCatalog.objectType(for: .workouts) as? HKWorkoutType else {
            return []
        }
        let rawWorkouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: workoutType, predicate: nil, limit: limit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    if Self.isBenignHealthKitDataError(error) {
                        continuation.resume(returning: [])
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            healthStore.execute(query)
        }

        async let heartRatesTask = averageHeartRates(for: rawWorkouts)
        async let recoveriesTask = heartRateRecoveries(for: rawWorkouts)
        let heartRates: [UUID: Double]
        do {
            heartRates = try await heartRatesTask
        } catch {
            recordDiagnostic(component: "recentWorkouts.averageHeartRate", error: error)
            heartRates = [:]
        }
        let recoveries: [UUID: Double]
        do {
            recoveries = try await recoveriesTask
        } catch {
            recordDiagnostic(component: "recentWorkouts.heartRateRecovery", error: error)
            recoveries = [:]
        }
        var summaries: [WorkoutSummary] = []
        for workout in rawWorkouts {
            summaries.append(WorkoutSummary(
                id: workout.uuid,
                start: workout.startDate,
                end: workout.endDate,
                activityName: workout.workoutActivityType.displayName,
                energyKilocalories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                averageHeartRate: heartRates[workout.uuid],
                heartRateRecoveryOneMinuteBPM: recoveries[workout.uuid],
                distanceMeters: workout.totalDistance?.doubleValue(for: .meter())
            ))
        }
        return summaries
    }

    private func sleepHeartRate(in range: DateRangeQuery) async throws -> Double? {
        let episodes = try await sleepEpisodes(in: range)
        let sleepRange = SleepHeartRateRangeResolver.range(for: episodes, fallback: range)
        return try await averageQuantity(
            .workoutHR,
            unit: HKUnit.count().unitDivided(by: .minute()),
            range: sleepRange
        )
    }

    private func averageHeartRates(for workouts: [HKWorkout]) async throws -> [UUID: Double] {
        // 性能修复：只取训练区间内的心率样本（OR 谓词并集），
        // 不再把训练之间的夜间连续心率也全量拉下来（60 天可达数十万样本）。
        let samples = try await heartRateSamples(within: workouts)
        let summaries = workouts.map {
            WorkoutSummary(
                id: $0.uuid,
                start: $0.startDate,
                end: $0.endDate,
                activityName: $0.workoutActivityType.displayName
            )
        }
        return WorkoutHeartRateAverager.averageHeartRates(samples: samples, workouts: summaries)
    }

    /// 仅查询给定训练区间并集内的心率样本；无训练直接返回空。
    private func heartRateSamples(within workouts: [HKWorkout]) async throws -> [HeartRateSample] {
        let predicates = workouts.compactMap { workout -> NSPredicate? in
            guard workout.endDate > workout.startDate else { return nil }
            return HKQuery.predicateForSamples(
                withStart: workout.startDate,
                end: workout.endDate,
                options: [.strictStartDate, .strictEndDate]
            )
        }
        guard !predicates.isEmpty else { return [] }
        let compound = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        return try await heartRateSamples(predicate: compound)
    }

    private func heartRateRecoveries(for workouts: [HKWorkout]) async throws -> [UUID: Double] {
        guard let start = workouts.map(\.startDate).min(),
              let lastEnd = workouts.map(\.endDate).max() else { return [:] }
        let end = lastEnd.addingTimeInterval(6 * 3_600)
        let samples = try await heartRateRecoverySamples(start: start, end: end)
        let summaries = workouts.map {
            WorkoutSummary(
                id: $0.uuid,
                start: $0.startDate,
                end: $0.endDate,
                activityName: $0.workoutActivityType.displayName
            )
        }
        return WorkoutHeartRateRecoveryMatcher.match(samples: samples, workouts: summaries)
    }

    private func heartRateRecoverySamples(start: Date, end: Date) async throws -> [HeartRateRecoverySample] {
        guard let type = HealthSignalCatalog.objectType(for: .heartRateRecoveryOneMinute) as? HKQuantityType else {
            return []
        }
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    if Self.isBenignHealthKitDataError(error) {
                        continuation.resume(returning: [])
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                let values = (samples as? [HKQuantitySample])?.map {
                    HeartRateRecoverySample(
                        date: $0.startDate,
                        // Apple 的 heartRateRecoveryOneMinute 样本单位是 count/min。
                        // 用 .count() 取值会抛 NSInvalidArgumentException(count/min, count 不兼容)。
                        bpm: $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    )
                } ?? []
                continuation.resume(returning: values)
            }
            healthStore.execute(query)
        }
    }

    /// 逐小时累计聚合（步数/活动能量等），返回当天每个有值的小时。
    func hourlySums(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        day: Date,
        calendar: Calendar = .current
    ) async throws -> [HourlyQuantity] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        let start = calendar.startOfDay(for: day)
        let end = start.addingTimeInterval(86_400)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: [.cumulativeSum],
                anchorDate: start,
                intervalComponents: DateComponents(hour: 1)
            )
            query.initialResultsHandler = { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                var points: [HourlyQuantity] = []
                results?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    let hour = calendar.component(.hour, from: statistics.startDate)
                    if let sum = statistics.sumQuantity() {
                        let value = sum.doubleValue(for: unit)
                        if value > 0 {
                            points.append(HourlyQuantity(hour: hour, value: value))
                        }
                    }
                }
                continuation.resume(returning: points)
            }
            healthStore.execute(query)
        }
    }

    func hourlySteps(day: Date, calendar: Calendar = .current) async throws -> [HourlyQuantity] {
        try await hourlySums(identifier: .stepCount, unit: .count(), day: day, calendar: calendar)
    }

    func hourlyActiveEnergy(day: Date, calendar: Calendar = .current) async throws -> [HourlyQuantity] {
        try await hourlySums(identifier: .activeEnergyBurned, unit: .kilocalorie(), day: day, calendar: calendar)
    }

    func heartRateSamples(start: Date, end: Date) async throws -> [HeartRateSample] {
        try await heartRateSamples(
            predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        )
    }

    func heartRateSamples(predicate: NSPredicate) async throws -> [HeartRateSample] {
        guard let heartRateType = HealthSignalCatalog.objectType(for: .workoutHR) as? HKQuantityType else {
            return []
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: heartRateType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    if Self.isBenignHealthKitDataError(error) {
                        continuation.resume(returning: [])
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                let hrSamples = (samples as? [HKQuantitySample])?.map { sample in
                    HeartRateSample(
                        date: sample.startDate,
                        bpm: sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    )
                } ?? []
                continuation.resume(returning: hrSamples)
            }
            healthStore.execute(query)
        }
    }

    func intradaySamples(
        for signal: HealthSignal,
        in range: DateRangeQuery
    ) async throws -> [IntradaySignalPoint] {
        guard let quantityType = HealthSignalCatalog.objectType(for: signal) as? HKQuantityType,
              let unit = HealthSignalCatalog.unit(for: signal)?.healthKitUnit else {
            return []
        }

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: range.start,
                end: range.end,
                options: []
            )
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    if Self.isBenignHealthKitDataError(error) {
                        continuation.resume(returning: [])
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                continuation.resume(returning: (samples as? [HKQuantitySample])?.map {
                    IntradaySignalPoint(
                        date: $0.startDate,
                        value: $0.quantity.doubleValue(for: unit),
                        sourceIdentifier: $0.sourceRevision.source.bundleIdentifier
                    )
                } ?? [])
            }
            healthStore.execute(query)
        }
    }

    func bloodGlucoseSamples(in range: DateRangeQuery) async throws -> [BloodGlucoseReading] {
        guard let glucoseType = HealthSignalCatalog.objectType(for: .bloodGlucose) as? HKQuantityType else {
            return []
        }

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: range.start,
                end: range.end,
                options: []
            )
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: glucoseType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    if Self.isBenignHealthKitDataError(error) {
                        continuation.resume(returning: [])
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                let unit = HKUnit(from: "mg/dL")
                let readings = (samples as? [HKQuantitySample])?.map { sample in
                    BloodGlucoseReading(
                        date: sample.startDate,
                        milligramsPerDeciliter: sample.quantity.doubleValue(for: unit)
                    )
                } ?? []
                continuation.resume(returning: readings)
            }
            healthStore.execute(query)
        }
    }

    func workoutRoute(workoutId: UUID) async throws -> [RouteCoordinate] {
        let workoutPredicate = HKQuery.predicateForObject(with: workoutId)
        guard let workoutType = HealthSignalCatalog.objectType(for: .workouts) as? HKWorkoutType else {
            return []
        }
        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: workoutType, predicate: workoutPredicate, limit: 1, sortDescriptors: nil) { _, samples, error in
                if let error {
                    if Self.isBenignHealthKitDataError(error) {
                        continuation.resume(returning: [])
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            healthStore.execute(query)
        }
        
        guard let workout = workouts.first else { return [] }
        
        guard let routeType = HealthSignalCatalog.objectType(for: .workoutRoute) as? HKSeriesType else {
            return []
        }
        let routePredicate = HKQuery.predicateForObjects(from: workout)
        let routes: [HKWorkoutRoute] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: routeType, predicate: routePredicate, limit: 1, sortDescriptors: nil) { _, samples, error in
                if let error {
                    if Self.isBenignHealthKitDataError(error) {
                        continuation.resume(returning: [])
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
            }
            healthStore.execute(query)
        }
        
        guard let route = routes.first else { return [] }
        
        return try await withCheckedThrowingContinuation { continuation in
            let accumulator = WorkoutRouteAccumulator()
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                if let locations = locations {
                    accumulator.append(
                        locations.map {
                            RouteCoordinate(
                                latitude: $0.coordinate.latitude,
                                longitude: $0.coordinate.longitude
                            )
                        }
                    )
                }
                if done || error != nil, let coordinates = accumulator.finish() {
                    if let error {
                        if Self.isBenignHealthKitDataError(error) {
                            continuation.resume(returning: [])
                        } else {
                            continuation.resume(throwing: error)
                        }
                    } else {
                        continuation.resume(returning: coordinates)
                    }
                }
            }
            healthStore.execute(query)
        }
    }
}

private final class WorkoutRouteAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var coordinates: [RouteCoordinate] = []
    private var isFinished = false

    func append(_ newCoordinates: [RouteCoordinate]) {
        lock.lock()
        coordinates.append(contentsOf: newCoordinates)
        lock.unlock()
    }

    func finish() -> [RouteCoordinate]? {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { return nil }
        isFinished = true
        return coordinates
    }
}

private extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .running:
            return "Running"
        case .walking:
            return "Walking"
        case .cycling:
            return "Cycling"
        case .traditionalStrengthTraining:
            return "Strength Training"
        case .functionalStrengthTraining:
            return "Functional Strength"
        case .yoga:
            return "Yoga"
        case .swimming:
            return "Swimming"
        case .hiking:
            return "Hiking"
        case .highIntensityIntervalTraining:
            return "HIIT"
        case .crossTraining:
            return "Cross Training"
        case .pilates:
            return "Pilates"
        case .rowing:
            return "Rowing"
        case .mixedCardio:
            return "Mixed Cardio"
        case .other:
            return "Other Workout"
        default:
            return "Workout"
        }
    }
}

// MARK: - Historical backfill aggregations（三年历史回填用逐日聚合）

/// 一天的睡眠聚合（回填写入 DailyHealthSummaryRecord 的原始字段）。
struct HistoricalSleepDay: Sendable {
    var sleepHours: Double
    var deepMinutes: Double?
    var remMinutes: Double?
}

extension HealthKitQueryService {
    /// 逐健康日均值（HRV/静息心率等）。
    func dailyAverages(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date,
        calendar: Calendar = .current
    ) async throws -> [Date: Double] {
        try await dailyStatistics(
            identifier: identifier,
            unit: unit,
            options: .discreteAverage,
            start: start,
            end: end,
            calendar: calendar
        )
    }

    /// 逐健康日累计（步数/活动能量等）。
    func dailySums(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date,
        calendar: Calendar = .current
    ) async throws -> [Date: Double] {
        try await dailyStatistics(
            identifier: identifier,
            unit: unit,
            options: .cumulativeSum,
            start: start,
            end: end,
            calendar: calendar
        )
    }

    /// 逐健康日最新值（体重/体脂等时点型指标）。
    func dailyMostRecent(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date,
        calendar: Calendar = .current
    ) async throws -> [Date: Double] {
        try await dailyStatistics(
            identifier: identifier,
            unit: unit,
            options: .mostRecent,
            start: start,
            end: end,
            calendar: calendar
        )
    }

    /// 逐健康日睡眠聚合：总睡眠小时 + 深睡/REM 分钟（iOS 16+ 分期；旧数据只有总时长）。
    /// 跨 04:00 边界的睡眠段按比例拆分（SleepDayAggregator，与同步引擎归属语义一致）。
    func dailySleep(
        start: Date,
        end: Date,
        calendar: Calendar = .current
    ) async throws -> [Date: HistoricalSleepDay] {
        guard let sleepType = HealthSignalCatalog.objectType(for: .sleepAnalysis) as? HKCategoryType else {
            return [:]
        }
        // 向前扩 12 小时：捕获在前夜入睡、次日早上结束的睡眠段。
        let extendedStart = start.addingTimeInterval(-12 * 3_600)
        let samples = try await categorySamples(
            type: sleepType,
            range: DateRangeQuery(start: extendedStart, end: end)
        )
        var segments: [SleepStageSegment] = []
        segments.reserveCapacity(samples.count)
        for sample in samples {
            let stage: SleepStage
            if let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) {
                switch value {
                case .asleepUnspecified: stage = .asleep
                case .asleepCore: stage = .core
                case .asleepDeep: stage = .deep
                case .asleepREM: stage = .rem
                case .awake: stage = .awake
                case .inBed: stage = .inBed
                @unknown default: stage = .asleep
                }
            } else {
                stage = .asleep
            }
            segments.append(SleepStageSegment(
                stage: stage,
                start: sample.startDate,
                end: sample.endDate
            ))
        }

        let aggregated = SleepDayAggregator.aggregate(
            segments: segments,
            boundaryMinutes: HealthDaySettings.boundaryMinutes(),
            calendar: calendar
        )
        let windowStart = calendar.startOfDay(for: start)
        let windowEnd = calendar.startOfDay(for: end)
        var out: [Date: HistoricalSleepDay] = [:]
        for (day, bucket) in aggregated where day >= windowStart && day < windowEnd {
            out[day] = HistoricalSleepDay(
                sleepHours: bucket.sleepMinutes / 60.0,
                deepMinutes: bucket.deepMinutes > 0 ? bucket.deepMinutes : nil,
                remMinutes: bucket.remMinutes > 0 ? bucket.remMinutes : nil
            )
        }
        return out
    }

    /// 通用逐日统计聚合：HKStatisticsCollectionQuery、1 天间隔、
    /// 锚定 04:00 健康日边界，结果按日历日午夜为键。
    private func dailyStatistics(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        options: HKStatisticsOptions,
        start: Date,
        end: Date,
        calendar: Calendar
    ) async throws -> [Date: Double] {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return [:] }
        let anchor = HealthDayBoundary(calendar: calendar).labelDate(containing: start)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, results, error in
                if let error {
                    if Self.isBenignHealthKitDataError(error) {
                        continuation.resume(returning: [:])
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                var out: [Date: Double] = [:]
                results?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    let value: Double?
                    if options.contains(.cumulativeSum) {
                        value = statistics.sumQuantity()?.doubleValue(for: unit)
                    } else if options.contains(.mostRecent) {
                        value = statistics.mostRecentQuantity()?.doubleValue(for: unit)
                    } else {
                        value = statistics.averageQuantity()?.doubleValue(for: unit)
                    }
                    if let value {
                        out[calendar.startOfDay(for: statistics.startDate)] = value
                    }
                }
                continuation.resume(returning: out)
            }
            healthStore.execute(query)
        }
    }
}
