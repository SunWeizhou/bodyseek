import Foundation

public struct DailyHealthComputationProfile: Sendable, Hashable {
    public let sleepTargetMinutes: Double
    public let maxHeartRate: Double?
    public let biologicalSex: String?

    public init(
        sleepTargetMinutes: Double,
        maxHeartRate: Double? = nil,
        biologicalSex: String? = nil
    ) {
        self.sleepTargetMinutes = sleepTargetMinutes
        self.maxHeartRate = maxHeartRate
        self.biologicalSex = biologicalSex
    }
}

/// Placeholder for the baseline report seam. Baseline statistics are not
/// migrated in PR1; ARCH-07 will replace this intentionally empty value with
/// the typed baseline contract before any long-term correction is enabled.
public struct LongTermBaselineReport: Codable, Hashable, Sendable {
    public init() {}
}

/// Five independent evidence slots. There is intentionally no aggregate or
/// readiness score: unavailable domains remain unavailable until their own
/// engine has been migrated and supplied with sufficient evidence.
public struct ScoredHealthEvidence: Codable, Hashable, Sendable {
    public let sleep: MetricResult
    public let recovery: MetricResult
    public let strain: MetricResult
    public let physiologicalStress: MetricResult
    public let energy: MetricResult

    public init(
        sleep: MetricResult,
        recovery: MetricResult,
        strain: MetricResult,
        physiologicalStress: MetricResult,
        energy: MetricResult
    ) {
        self.sleep = sleep
        self.recovery = recovery
        self.strain = strain
        self.physiologicalStress = physiologicalStress
        self.energy = energy
    }

    public var allMetrics: [MetricResult] {
        [sleep, recovery, strain, physiologicalStress, energy]
    }
}

/// Production scoring assembly. All five engines run here. Long-term baseline
/// statistics stay outside this type: callers pass an explicit recovery context
/// and quiet-heart-rate median. The empty `LongTermBaselineReport` parameter
/// remains so older call sites compile, and it does not affect the result.
public struct DailyHealthComputation: Sendable {
    private let calendar: Calendar
    private let now: Date
    private let profile: DailyHealthComputationProfile

    public init(calendar: Calendar, now: Date, profile: DailyHealthComputationProfile) {
        self.calendar = calendar
        self.now = now
        self.profile = profile
    }

    public func compute(
        for snapshot: DailyHealthSnapshot,
        history: [DailyHealthSnapshot],
        longTermBaselines: LongTermBaselineReport? = nil,
        sleepEvidence: SleepEvidenceContext? = nil,
        recoveryLongTerm: RecoveryLongTermContext? = nil,
        longTermQuietHeartRateMedian: Double? = nil
    ) -> ScoredHealthEvidence {
        _ = longTermBaselines
        let asOf = evaluationDate(for: snapshot)
        let baselineHistory = personalBaselineHistory(for: snapshot, from: history)
        let sleepHistoryStart = calendar.date(
            byAdding: .day,
            value: -13,
            to: calendar.startOfDay(for: snapshot.date)
        ) ?? .distantPast
        let recentBedtimes = baselineHistory
            .filter { calendar.startOfDay(for: $0.date) >= sleepHistoryStart }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .compactMap(\.bedtime)
        let (dailyLoadObservations, validDailyLoadDays) = continuousDailyLoadGrid(
            for: snapshot,
            from: history,
            maxDays: 42
        )
        let hrvEstimate = metricBaseline(in: baselineHistory, asOf: snapshot.date, value: \.hrvAverage)
        let hrvRmssdEstimate = metricBaseline(in: baselineHistory, asOf: snapshot.date, value: \.hrvRmssdMilliseconds)
        let rhrEstimate = metricBaseline(in: baselineHistory, asOf: snapshot.date, value: \.restingHeartRate)
        let respiratoryEstimate = metricBaseline(in: baselineHistory, asOf: snapshot.date, value: \.respiratoryRate)
        let hrvHistory = hrvEstimate?.values ?? []
        let hrvRmssdHistory = hrvRmssdEstimate?.values ?? []
        let rhrHistory = rhrEstimate?.values ?? []
        let respiratoryHistory = respiratoryEstimate?.values ?? []
        let dailyLoadHistory = dailyLoadObservations.loadValuesSkippingGaps()
        let temperatureDelta = wristTemperatureDelta(
            current: snapshot.wristTemperature,
            history: baselineHistory
        )

        let sleep = SleepScoreEngine(calendar: calendar).calculate(from: SleepScoreInput(
            asOf: asOf,
            totalSleepMinutes: snapshot.sleepHours.map { $0 * 60 },
            sleepTargetMinutes: profile.sleepTargetMinutes,
            todayBedtime: snapshot.bedtime,
            recentBedtimes: recentBedtimes,
            awakeMinutes: snapshot.awakeMinutes,
            awakeEpisodeCount: snapshot.awakeEpisodeCount,
            remMinutes: snapshot.remSleepMinutes,
            deepMinutes: snapshot.deepSleepMinutes,
            inBedMinutes: sleepEvidence?.inBed.value,
            evidence: sleepEvidence
        ))

        let yesterday = calendar.date(byAdding: .day, value: -1, to: snapshot.date) ?? snapshot.date
        let yesterdayStrain = baselineHistory.first {
            calendar.isDate($0.date, inSameDayAs: yesterday)
        }?.strainScore
        let recovery = RecoveryScoreEngine(calendar: calendar).calculate(from: RecoveryScoreInput(
            asOf: asOf,
            hrvToday: snapshot.hrvAverage,
            hrvBaseline: hrvEstimate?.median,
            hrvHistory: hrvHistory,
            hrvRmssdToday: snapshot.hrvRmssdMilliseconds,
            hrvRmssdBaseline: hrvRmssdEstimate?.median,
            hrvRmssdHistory: hrvRmssdHistory,
            restingHeartRateToday: snapshot.restingHeartRate,
            restingHeartRateBaseline: rhrEstimate?.median,
            rhrHistory: rhrHistory,
            sleepScoreLastNight: sleep.value,
            strainScoreYesterday: yesterdayStrain,
            respiratoryRateToday: snapshot.respiratoryRate,
            respiratoryRateBaseline: respiratoryEstimate?.median,
            respiratoryRateHistory: respiratoryHistory,
            bodyTempDelta: temperatureDelta,
            SpO2: snapshot.oxygenSaturation,
            longTermContext: recoveryLongTerm,
            observedAt: snapshot.hrvObservedAt ?? snapshot.rhrObservedAt,
            observedWindow: snapshot.hrvObservedWindow
        ))

        let strain = StrainScoreEngine(calendar: calendar).calculate(from: StrainScoreInput(
            asOf: asOf,
            workouts: snapshot.workouts.map {
                WorkoutInput(
                    id: $0.id,
                    durationMinutes: $0.end.timeIntervalSince($0.start) / 60,
                    averageHeartRate: $0.averageHeartRate,
                    rpe: $0.rpe
                )
            },
            activeEnergyToday: snapshot.activeCalories,
            exerciseMinutesToday: snapshot.activeMinutes ?? snapshot.workoutDuration,
            stepCount: snapshot.steps,
            restingHR: snapshot.restingHeartRate ?? 0,
            maxHR: profile.maxHeartRate ?? 0,
            biologicalSex: profile.biologicalSex,
            last28DaysDailyLoads: Array(dailyLoadHistory.prefix(28)),
            validObservedDaysCount: min(28, validDailyLoadDays),
            dailyLoadObservations: Array(dailyLoadObservations.prefix(28)),
            recoveryScore: recovery.value
        ))

        let respiratorySD = respiratoryEstimate?.robustScale
        let physiologicalStress = StressIndexEngine(calendar: calendar).calculate(from: StressIndexInput(
            asOf: asOf,
            quietHRToday: snapshot.restingHeartRate,
            quietHRBaseline: rhrEstimate?.median,
            quietHRSD: rhrEstimate?.robustScale,
            hrvToday: snapshot.hrvAverage,
            hrvBaseline: hrvEstimate?.median,
            hrvSD: hrvEstimate?.robustScale,
            respRateToday: snapshot.respiratoryRate,
            respRateBaseline: respiratoryEstimate?.median,
            respRateSD: respiratorySD,
            bodyTempDelta: temperatureDelta,
            sleepScoreLastNight: sleep.value,
            strainScoreToday: strain.value,
            isWithinWorkoutWindow: isInsideWorkoutRecoveryWindow(snapshot: snapshot, asOf: asOf),
            longTermQuietHRMedian: longTermQuietHeartRateMedian
        ))

        let respiratoryRateZ: Double? = {
            guard let current = snapshot.respiratoryRate,
                  let baseline = ScoringMath.median(respiratoryHistory),
                  let respiratorySD else { return nil }
            return (current - baseline) / respiratorySD
        }()
        let energy = EnergyBankEngine(calendar: calendar).calculate(from: EnergyBankInput(
            asOf: asOf,
            recoveryScore: recovery.value,
            sleepScore: sleep.value,
            strainScore: strain.value,
            stressIndex: physiologicalStress.value,
            hrvToday: snapshot.hrvAverage,
            hrvBaseline: hrvEstimate?.median,
            rhrToday: snapshot.restingHeartRate,
            rhrBaseline: rhrEstimate?.median,
            sleepHours: snapshot.sleepHours,
            strainHistory: dailyLoadHistory,
            trainingLoadHistory: dailyLoadObservations,
            todayLoad: strain.components["daily_load"],
            todayLoadObservation: todayLoadObservation(
                for: snapshot,
                dailyLoad: strain.components["daily_load"],
                asOf: asOf
            ),
            bodyTempDelta: temperatureDelta,
            hoursSinceWake: hoursSinceWake(snapshot: snapshot, asOf: asOf),
            respiratoryRateZ: respiratoryRateZ,
            SpO2: snapshot.oxygenSaturation,
            mindfulMinutes: nil,
            napMinutes: nil,
            trainingLoadStatus: strain.trainingLoadStatus,
            recoveryConfidence: recovery.confidence,
            sleepConfidence: sleep.confidence
        ))

        return ScoredHealthEvidence(
            sleep: sleep,
            recovery: recovery,
            strain: strain,
            physiologicalStress: physiologicalStress,
            energy: energy
        )
    }

    private func evaluationDate(for snapshot: DailyHealthSnapshot) -> Date {
        if calendar.isDate(snapshot.date, inSameDayAs: now) { return now }
        let start = calendar.startOfDay(for: snapshot.date)
        let next = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return next.addingTimeInterval(-1)
    }

    private func metricBaseline(
        in history: [DailyHealthSnapshot],
        asOf: Date,
        value: KeyPath<DailyHealthSnapshot, Double?>
    ) -> BaselineEstimate? {
        let samples = history.compactMap { snapshot -> BaselineSample? in
            guard let number = snapshot[keyPath: value] else { return nil }
            return BaselineSample(date: snapshot.date, value: number)
        }
        return BaselineEstimator.estimate(
            samples: samples,
            asOf: asOf,
            windowDays: 42,
            minimumSamples: 1,
            calendar: calendar
        )
    }

    private func personalBaselineHistory(
        for snapshot: DailyHealthSnapshot,
        from history: [DailyHealthSnapshot]
    ) -> [DailyHealthSnapshot] {
        let dayStart = calendar.startOfDay(for: snapshot.date)
        let earliest = calendar.date(byAdding: .day, value: -42, to: dayStart) ?? .distantPast
        return history
            .filter {
                let date = calendar.startOfDay(for: $0.date)
                return date >= earliest && date < dayStart
            }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private func wristTemperatureDelta(
        current: Double?,
        history: [DailyHealthSnapshot]
    ) -> Double? {
        guard let current else { return nil }
        let samples = history.compactMap(\.wristTemperature)
        guard samples.count >= 5,
              let baseline = ScoringMath.median(samples) else { return nil }
        return current - baseline
    }

    private func isInsideWorkoutRecoveryWindow(
        snapshot: DailyHealthSnapshot,
        asOf: Date
    ) -> Bool {
        guard calendar.isDate(snapshot.date, inSameDayAs: asOf) else { return false }
        return snapshot.workouts.contains { workout in
            asOf >= workout.start && asOf <= workout.end.addingTimeInterval(90 * 60)
        }
    }

    private func hoursSinceWake(
        snapshot: DailyHealthSnapshot,
        asOf: Date
    ) -> Double? {
        guard let wakeTime = snapshot.wakeTime, asOf >= wakeTime else { return nil }
        return max(0, min(24, asOf.timeIntervalSince(wakeTime) / 3_600))
    }

    private func continuousDailyLoadGrid(
        for snapshot: DailyHealthSnapshot,
        from history: [DailyHealthSnapshot],
        maxDays: Int
    ) -> (grid: [DailyLoadObservation], validDays: Int) {
        let dayStart = calendar.startOfDay(for: snapshot.date)
        var loadsByDay: [Date: Double] = [:]
        var earliestDate: Date?

        for item in history {
            let itemDay = calendar.startOfDay(for: item.date)
            if itemDay < dayStart {
                if earliestDate == nil || itemDay < earliestDate! {
                    earliestDate = itemDay
                }
                if let load = item.dailyLoad, load != 0 || hasActivityEvidence(in: item) {
                    loadsByDay[itemDay] = max(loadsByDay[itemDay] ?? 0.0, load)
                }
            }
        }

        guard let earliest = earliestDate else {
            return ([], 0)
        }

        let totalDays = min(maxDays, max(1, calendar.dateComponents([.day], from: earliest, to: dayStart).day ?? 1))
        var grid: [DailyLoadObservation] = []
        var validDays = 0
        grid.reserveCapacity(totalDays)

        for offset in 1...totalDays {
            guard let targetDate = calendar.date(byAdding: .day, value: -offset, to: dayStart) else { break }
            if let load = loadsByDay[targetDate] {
                grid.append(DailyLoadObservation(
                    date: targetDate,
                    value: load,
                    availability: load == 0 ? .knownZero : .observed,
                    observedWindow: DateInterval(start: targetDate, duration: 24 * 60 * 60)
                ))
                if offset <= 28 {
                    validDays += 1
                }
            } else {
                grid.append(DailyLoadObservation(
                    date: targetDate,
                    value: nil,
                    availability: .missing,
                    reason: "缺少该日负荷覆盖",
                    observedWindow: DateInterval(start: targetDate, duration: 24 * 60 * 60)
                ))
            }
        }

        return (grid, validDays)
    }

    private func hasActivityEvidence(in snapshot: DailyHealthSnapshot) -> Bool {
        !snapshot.workouts.isEmpty
            || snapshot.activeCalories != nil
            || snapshot.activeMinutes != nil
            || snapshot.workoutDuration != nil
            || snapshot.steps != nil
    }

    private func todayLoadObservation(
        for snapshot: DailyHealthSnapshot,
        dailyLoad: Double?,
        asOf: Date
    ) -> DailyLoadObservation {
        let day = calendar.startOfDay(for: asOf)
        guard hasActivityEvidence(in: snapshot) else {
            return DailyLoadObservation(
                date: day,
                value: nil,
                availability: .missing,
                reason: "今日没有训练或活动覆盖证据"
            )
        }
        let value = dailyLoad ?? 0.0
        return DailyLoadObservation(
            date: day,
            value: value,
            availability: value == 0 ? .knownZero : .observed,
            reason: dailyLoad == nil ? "今日活动已覆盖，但负荷尚未计算" : nil
        )
    }
}
