import BodySeekCore
import Foundation
import os

#if os(iOS)
import HealthKit
import SpeziHealthKit

enum SpeziHealthKitFetcher {
    private static let logger = Logger(subsystem: "com.sunweizhou.Vela4", category: "HealthKitSync")

    private static func runLogged<T>(
        _ label: String,
        operation: () async throws -> T
    ) async -> T? {
        do {
            return try await operation()
        } catch {
            logger.error("HealthKit operation '\(label, privacy: .public)' failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    @MainActor
    static func requestAuthorization(using healthKit: HealthKit) async -> Bool {
        do {
            try await healthKit.askForAuthorization()
            return true
        } catch {
            return false
        }
    }

    @MainActor
    static func isAuthorizedPrompted(using healthKit: HealthKit) -> Bool {
        healthKit.isFullyAuthorized
    }

    static func saveStrengthWorkout(
        _ session: LoggedWorkoutSession,
        using healthKit: HealthKit
    ) async throws -> String {
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor

        let builder = HKWorkoutBuilder(
            healthStore: healthKit.healthStore,
            configuration: config,
            device: .local()
        )
        try await builder.beginCollection(at: session.startedAt)
        if session.estimatedCalories > 0 {
            let energySample = HKQuantitySample(
                type: HKQuantityType(.activeEnergyBurned),
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: session.estimatedCalories),
                start: session.startedAt,
                end: session.completedAt
            )
            try await builder.addSamples([energySample])
        }
        try await builder.endCollection(at: session.completedAt)
        guard let workout = try await builder.finishWorkout() else {
            throw NSError(
                domain: "BodySeekHealth",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Apple 健康未能完成训练记录保存"]
            )
        }
        return workout.uuid.uuidString
    }

    static func fetchWindow(
        using healthKit: HealthKit,
        days: Int,
        sleepGoalMinutes: Int,
        referenceDate: Date,
        calendar: Calendar = .current
    ) async -> BodySeekDashboardSnapshot {
        let signpost = BodySeekSignposts.shared.begin(.healthKitWindowFetch)
        defer { BodySeekSignposts.shared.end(.healthKitWindowFetch, signpost) }

        let clampedDays = max(1, days)
        let refStart = calendar.startOfDay(for: referenceDate)
        let windowStart = calendar.date(byAdding: .day, value: -(clampedDays - 1), to: refStart) ?? refStart
        let windowEnd = calendar.date(byAdding: .day, value: 1, to: refStart) ?? referenceDate
        let queryRange = HealthKitQueryTimeRange(windowStart..<windowEnd)

        let sleepStart = calendar.date(byAdding: .hour, value: -16, to: windowStart) ?? windowStart
        let sleepRange = HealthKitQueryTimeRange(sleepStart..<windowEnd)

        async let hrvStats = runLogged("hrvStatistics") {
            try await healthKit.statisticsQuery(
                .heartRateVariabilitySDNN,
                aggregatedBy: [.average],
                over: .day,
                timeRange: queryRange
            )
        }
        async let rhrStats = runLogged("rhrStatistics") {
            try await healthKit.statisticsQuery(
                .restingHeartRate,
                aggregatedBy: [.average],
                over: .day,
                timeRange: queryRange
            )
        }
        async let respStats = runLogged("respiratoryStatistics") {
            try await healthKit.statisticsQuery(
                .respiratoryRate,
                aggregatedBy: [.average],
                over: .day,
                timeRange: queryRange
            )
        }
        async let spo2Stats = runLogged("spo2Statistics") {
            try await healthKit.statisticsQuery(
                .bloodOxygen,
                aggregatedBy: [.average],
                over: .day,
                timeRange: queryRange
            )
        }
        async let hrStats = runLogged("heartRateStatistics") {
            try await healthKit.statisticsQuery(
                .heartRate,
                aggregatedBy: [.average, .max],
                over: .day,
                timeRange: queryRange
            )
        }
        async let energyStats = runLogged("activeEnergyStatistics") {
            try await healthKit.statisticsQuery(
                .activeEnergyBurned,
                aggregatedBy: [.sum],
                over: .day,
                timeRange: queryRange
            )
        }
        async let exerciseStats = runLogged("exerciseMinutesStatistics") {
            try await healthKit.statisticsQuery(
                .appleExerciseTime,
                aggregatedBy: [.sum],
                over: .day,
                timeRange: queryRange
            )
        }
        async let stepStats = runLogged("stepStatistics") {
            try await healthKit.statisticsQuery(
                .stepCount,
                aggregatedBy: [.sum],
                over: .day,
                timeRange: queryRange
            )
        }
        async let sleepSamples = runLogged("sleepAnalysisQuery") {
            try await healthKit.query(.sleepAnalysis, timeRange: sleepRange)
        }
        async let workoutSamples = runLogged("workoutQuery") {
            try await healthKit.query(.workout, timeRange: queryRange)
        }

        let hrvByDay = mapAverage(await hrvStats, unit: .secondUnit(with: .milli), calendar: calendar)
        let rhrByDay = mapAverage(await rhrStats, unit: .count().unitDivided(by: .minute()), calendar: calendar)
        let respByDay = mapAverage(await respStats, unit: .count().unitDivided(by: .minute()), calendar: calendar)
        let spo2ByDay = mapAverage(await spo2Stats, unit: .percent(), calendar: calendar)
            .mapValues { $0 * 100.0 }
        let hrAvgByDay = mapAverage(await hrStats, unit: .count().unitDivided(by: .minute()), calendar: calendar)
        let hrMaxByDay = mapMax(await hrStats, unit: .count().unitDivided(by: .minute()), calendar: calendar)
        let kcalByDay = mapSum(await energyStats, unit: .kilocalorie(), calendar: calendar)
        let exByDay = mapSum(await exerciseStats, unit: .minute(), calendar: calendar)
        let stepsByDay = mapSum(await stepStats, unit: .count(), calendar: calendar)

        let sleepByDay = buildSleepByDay(from: await sleepSamples ?? [], calendar: calendar)
        let fetchedWorkouts = await workoutSamples ?? []
        let workoutsByDay = await buildWorkoutsByDay(
            from: fetchedWorkouts,
            using: healthKit,
            calendar: calendar
        )

        let isPrompted = await MainActor.run { healthKit.isFullyAuthorized }
        let hasAnyData = !hrvByDay.isEmpty
            || !rhrByDay.isEmpty
            || !sleepByDay.isEmpty
            || !kcalByDay.isEmpty
            || !stepsByDay.isEmpty
            || !fetchedWorkouts.isEmpty

        var rawDays: [DailyRawMetrics] = []
        rawDays.reserveCapacity(clampedDays)
        for offset in stride(from: -(clampedDays - 1), through: 0, by: 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: refStart) else { continue }
            let sleepInfo = sleepByDay[day]
            rawDays.append(
                DailyRawMetrics(
                    date: day,
                    hrvMs: hrvByDay[day],
                    restingHeartRateBpm: rhrByDay[day],
                    respiratoryRateBrpm: respByDay[day],
                    wristTempDeltaC: nil,
                    oxygenSaturationPct: spo2ByDay[day],
                    sleepAsleepMinutes: sleepInfo?.asleepMinutes,
                    sleepInBedMinutes: sleepInfo?.inBedMinutes,
                    deepMinutes: sleepInfo?.deepMinutes,
                    remMinutes: sleepInfo?.remMinutes,
                    coreMinutes: sleepInfo?.coreMinutes,
                    awakeMinutes: sleepInfo?.awakeMinutes,
                    sleepStart: sleepInfo?.start,
                    sleepEnd: sleepInfo?.end,
                    sleepSegments: sleepInfo?.segments ?? [],
                    activeEnergyKcal: kcalByDay[day],
                    exerciseMinutes: exByDay[day].map { Int($0.rounded()) },
                    steps: stepsByDay[day].map { Int($0.rounded()) },
                    workouts: workoutsByDay[day] ?? [],
                    daytimeMeanHeartRateBpm: hrAvgByDay[day],
                    daytimeMaxHeartRateBpm: hrMaxByDay[day],
                    hasAuthorizedHealthData: isPrompted || hasAnyData,
                    sourceNames: ["Apple 健康"]
                )
            )
        }

        return BevelScoringEngine.computeWindow(
            rawDays: rawDays,
            sleepGoalMinutes: sleepGoalMinutes,
            referenceDate: referenceDate,
            sourceLabel: "Apple 健康 · SpeziHealthKit",
            isAuthorized: isPrompted || hasAnyData,
            calendar: calendar
        )
    }

    private struct DaySleepAggregate {
        let asleepMinutes: Int
        let inBedMinutes: Int
        let deepMinutes: Int
        let remMinutes: Int
        let coreMinutes: Int
        let awakeMinutes: Int
        let start: Date
        let end: Date
        let segments: [SleepStageSegment]
    }

    private static func mapAverage(
        _ stats: [HKStatistics]?,
        unit: HKUnit,
        calendar: Calendar
    ) -> [Date: Double] {
        guard let stats else { return [:] }
        var map: [Date: Double] = [:]
        for item in stats {
            if let q = item.averageQuantity() {
                map[calendar.startOfDay(for: item.startDate)] = q.doubleValue(for: unit)
            }
        }
        return map
    }

    private static func mapMax(
        _ stats: [HKStatistics]?,
        unit: HKUnit,
        calendar: Calendar
    ) -> [Date: Double] {
        guard let stats else { return [:] }
        var map: [Date: Double] = [:]
        for item in stats {
            if let q = item.maximumQuantity() {
                map[calendar.startOfDay(for: item.startDate)] = q.doubleValue(for: unit)
            }
        }
        return map
    }

    private static func mapSum(
        _ stats: [HKStatistics]?,
        unit: HKUnit,
        calendar: Calendar
    ) -> [Date: Double] {
        guard let stats else { return [:] }
        var map: [Date: Double] = [:]
        for item in stats {
            if let q = item.sumQuantity() {
                map[calendar.startOfDay(for: item.startDate)] = q.doubleValue(for: unit)
            }
        }
        return map
    }

    private static func buildSleepByDay(
        from samples: [HKCategorySample],
        calendar: Calendar
    ) -> [Date: DaySleepAggregate] {
        guard !samples.isEmpty else { return [:] }
        let sessions: [SleepSession]
        do {
            sessions = try samples.splitIntoSleepSessions(threshold: .minutes(60), separateBySource: true)
        } catch {
            logger.error("splitIntoSleepSessions failed: \(error.localizedDescription, privacy: .public)")
            sessions = []
        }

        var bestByDay: [Date: SleepSession] = [:]
        for session in sessions where session.totalTimeSpentAsleep > 0 {
            let wakeDay = calendar.startOfDay(for: session.endDate)
            if let existing = bestByDay[wakeDay] {
                if session.totalTimeSpentAsleep > existing.totalTimeSpentAsleep {
                    bestByDay[wakeDay] = session
                }
            } else {
                bestByDay[wakeDay] = session
            }
        }

        return bestByDay.mapValues { session in
            let asleep = Int((session.totalTimeSpentAsleep / 60).rounded())
            let deep = Int(((session.timeSpentInSleepPhase[.asleepDeep] ?? 0) / 60).rounded())
            let rem = Int(((session.timeSpentInSleepPhase[.asleepREM] ?? 0) / 60).rounded())
            let core = Int(((session.timeSpentInSleepPhase[.asleepCore] ?? 0) / 60).rounded())
            let unspecified = Int(((session.timeSpentInSleepPhase[.asleepUnspecified] ?? 0) / 60).rounded())
            let awake = Int((session.totalTimeSpentAwake / 60).rounded())
            let effectiveCore = core + unspecified
            let inBed = max(asleep + awake, Int((session.endDate.timeIntervalSince(session.startDate) / 60).rounded()))

            let segments: [SleepStageSegment] = session.samples.compactMap { sample in
                let stage: SleepStage? = switch sample.sleepPhase {
                case .asleepDeep: .deep
                case .asleepREM: .rem
                case .asleepCore, .asleepUnspecified: .core
                case .awake: .awake
                default: nil
                }
                guard let stage else { return nil }
                return SleepStageSegment(stage: stage, startDate: sample.startDate, endDate: sample.endDate)
            }

            return DaySleepAggregate(
                asleepMinutes: asleep,
                inBedMinutes: inBed,
                deepMinutes: deep,
                remMinutes: rem,
                coreMinutes: effectiveCore,
                awakeMinutes: awake,
                start: session.startDate,
                end: session.endDate,
                segments: segments
            )
        }
    }

    private static func buildWorkoutsByDay(
        from workouts: [HKWorkout],
        using healthKit: HealthKit,
        calendar: Calendar
    ) async -> [Date: [WorkoutSummary]] {
        let recentSorted = workouts.sorted { $0.startDate > $1.startDate }
        var grouped: [Date: [WorkoutSummary]] = [:]

        for (index, workout) in recentSorted.enumerated() {
            let day = calendar.startOfDay(for: workout.startDate)
            let minutes = max(1, Int((workout.duration / 60).rounded()))
            let energyType = HKQuantityType(.activeEnergyBurned)
            let kcal = workout.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            let hrType = HKQuantityType(.heartRate)
            let avgHR = workout.statistics(for: hrType)?.averageQuantity()?
                .doubleValue(for: .count().unitDivided(by: .minute()))
            let effortType = HKQuantityType(.workoutEffortScore)
            let effort = workout.statistics(for: effortType)?.mostRecentQuantity()?
                .doubleValue(for: .appleEffortScore())

            var zones: WorkoutHeartRateZones?
            if index < 10, workout.endDate > workout.startDate {
                do {
                    let hrSamples = try await healthKit.query(
                        .heartRate,
                        timeRange: HealthKitQueryTimeRange(workout.startDate..<workout.endDate)
                    )
                    if !hrSamples.isEmpty {
                        zones = computeHeartRateZones(samples: hrSamples, totalMinutes: minutes)
                    }
                } catch {
                    logger.error("HealthKit operation 'workoutHeartRateQuery' failed: \(error.localizedDescription, privacy: .public)")
                }
            }

            let (name, symbol) = activityDisplay(for: workout.workoutActivityType)
            grouped[day, default: []].append(
                WorkoutSummary(
                    id: workout.uuid,
                    activityName: name,
                    symbolName: symbol,
                    startDate: workout.startDate,
                    durationMinutes: minutes,
                    activeEnergyKcal: kcal,
                    averageHeartRate: avgHR,
                    effortScore: effort,
                    heartRateZones: zones,
                    healthKitUUID: workout.uuid,
                    recordedEndDate: workout.endDate
                )
            )
        }
        return grouped
    }

    private static func computeHeartRateZones(
        samples: [HKQuantitySample],
        totalMinutes: Int
    ) -> WorkoutHeartRateZones? {
        guard !samples.isEmpty else { return nil }
        let unit = HKUnit.count().unitDivided(by: .minute())
        var z1 = 0, z2 = 0, z3 = 0, z4 = 0, z5 = 0
        var maxHR = 0.0
        let estMax = 190.0

        for sample in samples {
            let bpm = sample.quantity.doubleValue(for: unit)
            maxHR = max(maxHR, bpm)
            let pct = bpm / estMax
            if pct < 0.60 { z1 += 1 }
            else if pct < 0.70 { z2 += 1 }
            else if pct < 0.80 { z3 += 1 }
            else if pct < 0.90 { z4 += 1 }
            else { z5 += 1 }
        }

        let total = max(1, z1 + z2 + z3 + z4 + z5)
        func scaled(_ count: Int) -> Int {
            Int((Double(count) / Double(total) * Double(totalMinutes)).rounded())
        }
        return WorkoutHeartRateZones(
            zone1Minutes: scaled(z1),
            zone2Minutes: scaled(z2),
            zone3Minutes: scaled(z3),
            zone4Minutes: scaled(z4),
            zone5Minutes: scaled(z5),
            maxHeartRate: maxHR > 0 ? maxHR : nil
        )
    }

    static func activityDisplay(for type: HKWorkoutActivityType) -> (String, String) {
        switch type {
        case .running: ("跑步", "figure.run")
        case .walking: ("步行", "figure.walk")
        case .cycling: ("骑行", "figure.outdoor.cycle")
        case .swimming: ("游泳", "figure.pool.swim")
        case .badminton: ("羽毛球", "figure.badminton")
        case .traditionalStrengthTraining, .functionalStrengthTraining: ("力量训练", "dumbbell.fill")
        case .highIntensityIntervalTraining: ("HIIT", "flame.fill")
        case .yoga: ("瑜伽", "figure.mind.and.body")
        case .coreTraining: ("核心训练", "figure.core.training")
        case .hiking: ("徒步", "figure.hiking")
        default: ("体能训练", "figure.mixed.cardio")
        }
    }
}
#endif
