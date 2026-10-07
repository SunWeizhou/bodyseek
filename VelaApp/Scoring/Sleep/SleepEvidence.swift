import Foundation

/// In-memory sleep evidence contract. Availability describes the quality of a
/// component; freshness and query outcome are carried separately so a retained
/// value can be distinguished from a current observation.
public enum SleepObservationAvailability: String, Codable, Hashable, Sendable {
    case observed
    case estimated
    case missing
    case excluded
}

public struct SleepComponentObservation: Codable, Hashable, Sendable {
    public var value: Double?
    public var availability: SleepObservationAvailability
    public var reason: String?
    public var observedWindow: DateInterval?

    public init(
        value: Double?,
        availability: SleepObservationAvailability,
        reason: String? = nil,
        observedWindow: DateInterval? = nil
    ) {
        self.value = value
        self.availability = availability
        self.reason = reason
        self.observedWindow = observedWindow
    }

    public static func missing(_ reason: String? = nil) -> SleepComponentObservation {
        SleepComponentObservation(value: nil, availability: .missing, reason: reason)
    }
}

public struct SleepEvidenceContext: Codable, Hashable, Sendable {
    public var queryOutcome: HealthQueryOutcomeKind?
    public var freshness: DataFreshness?
    public var totalSleep: SleepComponentObservation
    public var bedtime: SleepComponentObservation
    public var wakeTime: SleepComponentObservation
    public var inBed: SleepComponentObservation
    public var awake: SleepComponentObservation
    public var rem: SleepComponentObservation
    public var deep: SleepComponentObservation
    public var episodeCount: SleepComponentObservation

    public init(
        queryOutcome: HealthQueryOutcomeKind? = nil,
        freshness: DataFreshness? = nil,
        totalSleep: SleepComponentObservation,
        bedtime: SleepComponentObservation,
        wakeTime: SleepComponentObservation,
        inBed: SleepComponentObservation,
        awake: SleepComponentObservation,
        rem: SleepComponentObservation,
        deep: SleepComponentObservation,
        episodeCount: SleepComponentObservation
    ) {
        self.queryOutcome = queryOutcome
        self.freshness = freshness
        self.totalSleep = totalSleep
        self.bedtime = bedtime
        self.wakeTime = wakeTime
        self.inBed = inBed
        self.awake = awake
        self.rem = rem
        self.deep = deep
        self.episodeCount = episodeCount
    }

    public var isStale: Bool { freshness == .stale }

    static func from(
        summary: SleepSummary?,
        range: DateInterval,
        queryOutcome: HealthQueryOutcomeKind? = .data,
        freshness: DataFreshness? = .today
    ) -> SleepEvidenceContext {
        func observation(
            _ value: Double?,
            availability: SleepObservationAvailability,
            reason: String? = nil
        ) -> SleepComponentObservation {
            SleepComponentObservation(
                value: value,
                availability: availability,
                reason: reason,
                observedWindow: range
            )
        }

        guard let summary else {
            let missingOutcome = queryOutcome == .data ? .noData : (queryOutcome ?? .noData)
            let missingFreshness = missingOutcome == .noData ? .missing : (freshness ?? .missing)
            return SleepEvidenceContext(
                queryOutcome: missingOutcome,
                freshness: missingFreshness,
                totalSleep: .missing("没有睡眠摘要"),
                bedtime: .missing("没有入睡时间"),
                wakeTime: .missing("没有起床时间"),
                inBed: .missing("没有卧床阶段"),
                awake: .missing("没有清醒阶段"),
                rem: .missing("没有 REM 阶段"),
                deep: .missing("没有 Deep 阶段"),
                episodeCount: .missing("没有清醒次数")
            )
        }

        let total = Double(summary.totalSleepMinutes)
        let awake = summary.stageMinutes[.awake].map(Double.init)
        let inBed = summary.stageMinutes[.inBed].map(Double.init)
        let rem = summary.stageMinutes[.rem].map(Double.init)
        let deep = summary.stageMinutes[.deep].map(Double.init)
        let episodeCount = summary.segments.filter {
            $0.stage == .awake && $0.end.timeIntervalSince($0.start) >= 120
        }.count

        return SleepEvidenceContext(
            queryOutcome: queryOutcome,
            freshness: freshness,
            totalSleep: observation(
                total > 0 ? total : nil,
                availability: total > 0 ? .observed : .missing,
                reason: total > 0 ? nil : "没有有效睡眠片段"
            ),
            bedtime: observation(
                summary.bedtime?.timeIntervalSinceReferenceDate,
                availability: summary.bedtime == nil ? .missing : .observed
            ),
            wakeTime: observation(
                summary.wakeTime?.timeIntervalSinceReferenceDate,
                availability: summary.wakeTime == nil ? .missing : .observed
            ),
            inBed: {
                if let inBed, inBed > 0 {
                    return observation(inBed, availability: .observed)
                }
                if total > 0, let awake, awake >= 0 {
                    return observation(
                        total + awake,
                        availability: .estimated,
                        reason: "由睡眠时长与清醒时长推导卧床时长"
                    )
                }
                return .missing("HealthKit 未提供卧床阶段")
            }(),
            awake: observation(
                awake,
                availability: awake == nil ? .missing : .observed,
                reason: awake == nil ? "HealthKit 未提供清醒阶段" : nil
            ),
            rem: observation(
                rem,
                availability: rem == nil ? .missing : .observed,
                reason: rem == nil ? "HealthKit 未提供 REM 阶段" : nil
            ),
            deep: observation(
                deep,
                availability: deep == nil ? .missing : .observed,
                reason: deep == nil ? "HealthKit 未提供 Deep 阶段" : nil
            ),
            episodeCount: observation(
                Double(episodeCount),
                availability: .estimated,
                reason: "由清醒片段估算醒来次数"
            )
        )
    }
}

enum SleepTargetSettings {
    static let hoursKey = "vela_sleep_target_hours"
    static let defaultHours = 7.5
    static let availableHours = stride(from: 5.0, through: 10.0, by: 0.5).map { $0 }

    static func targetMinutes(defaults: UserDefaults = .standard) -> Double {
        let configuredHours = defaults.object(forKey: hoursKey) as? Double ?? defaultHours
        return min(max(configuredHours, 5.0), 10.0) * 60.0
    }

    static func displayHours(_ hours: Double) -> String {
        hours == hours.rounded() ? "\(Int(hours))h" : String(format: "%.1fh", hours)
    }
}
