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

/// Standalone deterministic computation facade. PR1 has migrated only Sleep;
/// the other slots are explicit unavailable results until their engines can be
/// extracted with the same Foundation-only and golden-parity guarantees.
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
        longTermBaselines: LongTermBaselineReport? = nil
    ) -> ScoredHealthEvidence {
        // The placeholder is intentionally ignored until ARCH-07 defines and
        // migrates the baseline statistics contract.
        _ = longTermBaselines
        let asOf = evaluationDate(for: snapshot)
        let dayStart = calendar.startOfDay(for: snapshot.date)
        let earliest = calendar.date(byAdding: .day, value: -13, to: dayStart) ?? .distantPast
        let baselineHistory = history
            .filter {
                let date = calendar.startOfDay(for: $0.date)
                return date >= earliest && date < dayStart
            }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        let sleep = SleepScoreEngine(calendar: calendar).calculate(from: SleepScoreInput(
            asOf: asOf,
            totalSleepMinutes: snapshot.sleepHours.map { $0 * 60 },
            sleepTargetMinutes: profile.sleepTargetMinutes,
            todayBedtime: snapshot.bedtime,
            recentBedtimes: baselineHistory.compactMap(\.bedtime),
            awakeMinutes: snapshot.awakeMinutes,
            awakeEpisodeCount: snapshot.awakeEpisodeCount,
            remMinutes: snapshot.remSleepMinutes,
            deepMinutes: snapshot.deepSleepMinutes
        ))
        return ScoredHealthEvidence(
            sleep: sleep,
            recovery: unavailable(.recovery, asOf: asOf, algorithmVersion: ScoringAlgorithmVersions.recovery, reason: "Recovery engine remains in Vela adapter pending parity migration"),
            strain: unavailable(.strain, asOf: asOf, algorithmVersion: ScoringAlgorithmVersions.strain, reason: "Strain engine remains in Vela adapter pending parity migration"),
            physiologicalStress: unavailable(.physiologicalStress, asOf: asOf, algorithmVersion: ScoringAlgorithmVersions.physiologicalStress, reason: "Physiological stress engine remains in Vela adapter pending parity migration"),
            energy: unavailable(.energy, asOf: asOf, algorithmVersion: ScoringAlgorithmVersions.energy, reason: "Energy engine remains in Vela adapter pending parity migration")
        )
    }

    private func evaluationDate(for snapshot: DailyHealthSnapshot) -> Date {
        if calendar.isDate(snapshot.date, inSameDayAs: now) { return now }
        let start = calendar.startOfDay(for: snapshot.date)
        let next = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return next.addingTimeInterval(-1)
    }

    private func unavailable(
        _ domain: ScoredHealthDomain,
        asOf: Date,
        algorithmVersion: String,
        reason: String
    ) -> MetricResult {
        MetricResult(
            domain: domain,
            name: "\(domain.rawValue) score",
            value: nil,
            band: .low,
            confidence: .low,
            reasons: [reason],
            missingInputs: ["engineNotMigrated"],
            dataWindow: DateInterval(start: asOf, end: asOf),
            source: .derived,
            algorithmVersion: algorithmVersion,
            lastUpdated: asOf
        )
    }
}
