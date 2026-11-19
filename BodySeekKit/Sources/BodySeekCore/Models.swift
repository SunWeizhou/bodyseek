import Foundation

public enum MetricKind: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
    case recovery
    case sleep
    case strain
    case stress
    case energy

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .recovery: "恢复"
        case .sleep: "睡眠"
        case .strain: "负荷"
        case .stress: "压力"
        case .energy: "能量"
        }
    }

    public var systemImage: String {
        switch self {
        case .recovery: "heart.circle.fill"
        case .sleep: "bed.double.fill"
        case .strain: "flame.fill"
        case .stress: "waveform.path.ecg"
        case .energy: "bolt.fill"
        }
    }

    public var shortExplanation: String {
        switch self {
        case .recovery: "结合夜间 HRV、静息心率与昨夜睡眠对比个人 28 天滚动基线评估恢复储备。"
        case .sleep: "综合入睡时长、深睡/REM 修复比例与清醒中断还原睡眠质量。"
        case .strain: "统计全天动态消耗、锻炼时长与 Apple Watch 心率负荷体现机能刺激。"
        case .stress: "按日间心率偏离静息基线幅度与恢复余量估算自主神经负荷。"
        case .energy: "结合昨夜充能斜率与全天活动掉电动态模拟当前可用能量。"
        }
    }
}

public enum MetricAvailability: Equatable, Hashable, Sendable, Codable {
    case available
    case knownZero(reason: String)
    case missing(reason: String)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    public var reasonText: String? {
        switch self {
        case .available: nil
        case let .knownZero(reason), let .missing(reason): reason
        }
    }
}

public struct MetricScore: Equatable, Hashable, Sendable, Codable {
    public let kind: MetricKind
    public let value: Int?
    public let availability: MetricAvailability
    public let badge: String
    public let subtitle: String
    public let baselineDelta: Int?

    public init(
        kind: MetricKind,
        value: Int?,
        availability: MetricAvailability,
        badge: String,
        subtitle: String,
        baselineDelta: Int? = nil
    ) {
        self.kind = kind
        self.value = value
        self.availability = availability
        self.badge = badge
        self.subtitle = subtitle
        self.baselineDelta = baselineDelta
    }

    public var formattedScore: String {
        if let value { return "\(value)" }
        return "--"
    }
}

public enum SleepStage: String, CaseIterable, Hashable, Sendable, Codable {
    case deep
    case core
    case rem
    case awake

    public var title: String {
        switch self {
        case .deep: "深睡"
        case .core: "核心"
        case .rem: "REM"
        case .awake: "清醒"
        }
    }
}

public struct SleepStageSegment: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let stage: SleepStage
    public let startDate: Date
    public let endDate: Date

    public init(id: UUID = UUID(), stage: SleepStage, startDate: Date, endDate: Date) {
        self.id = id
        self.stage = stage
        self.startDate = startDate
        self.endDate = max(startDate, endDate)
    }

    public var durationMinutes: Int {
        max(0, Int((endDate.timeIntervalSince(startDate) / 60).rounded()))
    }
}

public struct WorkoutHeartRateZones: Equatable, Hashable, Sendable, Codable {
    public let zone1Minutes: Int
    public let zone2Minutes: Int
    public let zone3Minutes: Int
    public let zone4Minutes: Int
    public let zone5Minutes: Int
    public let maxHeartRate: Double?

    public init(
        zone1Minutes: Int,
        zone2Minutes: Int,
        zone3Minutes: Int,
        zone4Minutes: Int,
        zone5Minutes: Int,
        maxHeartRate: Double? = nil
    ) {
        self.zone1Minutes = zone1Minutes
        self.zone2Minutes = zone2Minutes
        self.zone3Minutes = zone3Minutes
        self.zone4Minutes = zone4Minutes
        self.zone5Minutes = zone5Minutes
        self.maxHeartRate = maxHeartRate
    }

    public var totalZoneMinutes: Int {
        zone1Minutes + zone2Minutes + zone3Minutes + zone4Minutes + zone5Minutes
    }

    public var trimpScore: Double {
        Double(zone1Minutes) * 0.6
            + Double(zone2Minutes) * 1.1
            + Double(zone3Minutes) * 1.8
            + Double(zone4Minutes) * 2.8
            + Double(zone5Minutes) * 4.0
    }
}

public struct WorkoutSummary: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let activityName: String
    public let symbolName: String
    public let startDate: Date
    public let durationMinutes: Int
    public let activeEnergyKcal: Double
    public let averageHeartRate: Double?
    public let effortScore: Double?
    public let heartRateZones: WorkoutHeartRateZones?

    public init(
        id: UUID = UUID(),
        activityName: String,
        symbolName: String,
        startDate: Date,
        durationMinutes: Int,
        activeEnergyKcal: Double,
        averageHeartRate: Double? = nil,
        effortScore: Double? = nil,
        heartRateZones: WorkoutHeartRateZones? = nil
    ) {
        self.id = id
        self.activityName = activityName
        self.symbolName = symbolName
        self.startDate = startDate
        self.durationMinutes = durationMinutes
        self.activeEnergyKcal = activeEnergyKcal
        self.averageHeartRate = averageHeartRate
        self.effortScore = effortScore
        self.heartRateZones = heartRateZones
    }
}

public struct DailyRawMetrics: Identifiable, Hashable, Sendable, Codable {
    public var id: Date { date }
    public let date: Date
    public var hrvMs: Double?
    public var restingHeartRateBpm: Double?
    public var respiratoryRateBrpm: Double?
    public var wristTempDeltaC: Double?
    public var oxygenSaturationPct: Double?

    public var sleepAsleepMinutes: Int?
    public var sleepInBedMinutes: Int?
    public var deepMinutes: Int?
    public var remMinutes: Int?
    public var coreMinutes: Int?
    public var awakeMinutes: Int?
    public var sleepStart: Date?
    public var sleepEnd: Date?
    public var sleepSegments: [SleepStageSegment]

    public var activeEnergyKcal: Double?
    public var exerciseMinutes: Int?
    public var steps: Int?
    public var workouts: [WorkoutSummary]

    public var daytimeMeanHeartRateBpm: Double?
    public var daytimeMaxHeartRateBpm: Double?
    public var hasAuthorizedHealthData: Bool
    public var sourceNames: [String]

    public init(
        date: Date,
        hrvMs: Double? = nil,
        restingHeartRateBpm: Double? = nil,
        respiratoryRateBrpm: Double? = nil,
        wristTempDeltaC: Double? = nil,
        oxygenSaturationPct: Double? = nil,
        sleepAsleepMinutes: Int? = nil,
        sleepInBedMinutes: Int? = nil,
        deepMinutes: Int? = nil,
        remMinutes: Int? = nil,
        coreMinutes: Int? = nil,
        awakeMinutes: Int? = nil,
        sleepStart: Date? = nil,
        sleepEnd: Date? = nil,
        sleepSegments: [SleepStageSegment] = [],
        activeEnergyKcal: Double? = nil,
        exerciseMinutes: Int? = nil,
        steps: Int? = nil,
        workouts: [WorkoutSummary] = [],
        daytimeMeanHeartRateBpm: Double? = nil,
        daytimeMaxHeartRateBpm: Double? = nil,
        hasAuthorizedHealthData: Bool = true,
        sourceNames: [String] = []
    ) {
        self.date = date
        self.hrvMs = hrvMs
        self.restingHeartRateBpm = restingHeartRateBpm
        self.respiratoryRateBrpm = respiratoryRateBrpm
        self.wristTempDeltaC = wristTempDeltaC
        self.oxygenSaturationPct = oxygenSaturationPct
        self.sleepAsleepMinutes = sleepAsleepMinutes
        self.sleepInBedMinutes = sleepInBedMinutes
        self.deepMinutes = deepMinutes
        self.remMinutes = remMinutes
        self.coreMinutes = coreMinutes
        self.awakeMinutes = awakeMinutes
        self.sleepStart = sleepStart
        self.sleepEnd = sleepEnd
        self.sleepSegments = sleepSegments
        self.activeEnergyKcal = activeEnergyKcal
        self.exerciseMinutes = exerciseMinutes
        self.steps = steps
        self.workouts = workouts
        self.daytimeMeanHeartRateBpm = daytimeMeanHeartRateBpm
        self.daytimeMaxHeartRateBpm = daytimeMaxHeartRateBpm
        self.hasAuthorizedHealthData = hasAuthorizedHealthData
        self.sourceNames = sourceNames
    }
}

public enum StressLevel: String, Hashable, Sendable, Codable {
    case rest
    case low
    case medium
    case elevated
}

public struct StressTimelineBin: Identifiable, Hashable, Sendable, Codable {
    public var id: Int { hour }
    public let hour: Int
    public let value: Int
    public let level: StressLevel

    public init(hour: Int, value: Int, level: StressLevel) {
        self.hour = hour
        self.value = value
        self.level = level
    }
}

public struct EnergyCurvePoint: Identifiable, Hashable, Sendable, Codable {
    public var id: Int { hour }
    public let hour: Int
    public let value: Int
    public let date: Date

    public init(hour: Int, value: Int, date: Date) {
        self.hour = hour
        self.value = value
        self.date = date
    }
}

public struct DailyComputedDay: Identifiable, Hashable, Sendable, Codable {
    public var id: Date { date }
    public let date: Date
    public let raw: DailyRawMetrics
    public let recovery: MetricScore
    public let sleep: MetricScore
    public let strain: MetricScore
    public let stress: MetricScore
    public let energy: MetricScore
    public let energyCurve: [EnergyCurvePoint]
    public let stressTimeline: [StressTimelineBin]
    public let factualSummary: String
    public let evidenceSummary: String

    public init(
        date: Date,
        raw: DailyRawMetrics,
        recovery: MetricScore,
        sleep: MetricScore,
        strain: MetricScore,
        stress: MetricScore,
        energy: MetricScore,
        energyCurve: [EnergyCurvePoint],
        stressTimeline: [StressTimelineBin],
        factualSummary: String,
        evidenceSummary: String
    ) {
        self.date = date
        self.raw = raw
        self.recovery = recovery
        self.sleep = sleep
        self.strain = strain
        self.stress = stress
        self.energy = energy
        self.energyCurve = energyCurve
        self.stressTimeline = stressTimeline
        self.factualSummary = factualSummary
        self.evidenceSummary = evidenceSummary
    }

    public func score(for kind: MetricKind) -> MetricScore {
        switch kind {
        case .recovery: recovery
        case .sleep: sleep
        case .strain: strain
        case .stress: stress
        case .energy: energy
        }
    }
}

public enum TrendHorizon: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
    case week
    case month
    case sixMonths
    case threeYears

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .week: "7天"
        case .month: "30天"
        case .sixMonths: "6个月"
        case .threeYears: "3年"
        }
    }

    public var dayCount: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .sixMonths: 180
        case .threeYears: 365
        }
    }
}

public struct TrendPoint: Identifiable, Hashable, Sendable, Codable {
    public var id: Date { date }
    public let date: Date
    public let value: Int?
    public let availability: MetricAvailability

    public init(date: Date, value: Int?, availability: MetricAvailability) {
        self.date = date
        self.value = value
        self.availability = availability
    }
}

public struct TrendSeries: Equatable, Sendable {
    public let kind: MetricKind
    public let horizon: TrendHorizon
    public let points: [TrendPoint]
    public let baselineRange: ClosedRange<Double>?
    public let coveredDays: Int
    public let totalDays: Int
    public let median: Int?
    public let deltaFromFirstHalf: Int?
    public let statusSummary: String

    public init(
        kind: MetricKind,
        horizon: TrendHorizon,
        points: [TrendPoint],
        baselineRange: ClosedRange<Double>?,
        coveredDays: Int,
        totalDays: Int,
        median: Int?,
        deltaFromFirstHalf: Int?,
        statusSummary: String
    ) {
        self.kind = kind
        self.horizon = horizon
        self.points = points
        self.baselineRange = baselineRange
        self.coveredDays = coveredDays
        self.totalDays = totalDays
        self.median = median
        self.deltaFromFirstHalf = deltaFromFirstHalf
        self.statusSummary = statusSummary
    }
}

public struct BodySeekDashboardSnapshot: Equatable, Sendable {
    public let referenceDate: Date
    public let today: DailyComputedDay
    public let historyDays: [DailyComputedDay]
    public let trainingLoad: TrainingLoadStatus
    public let sourceLabel: String
    public let lastUpdatedAt: Date
    public let isAuthorized: Bool

    public init(
        referenceDate: Date,
        today: DailyComputedDay,
        historyDays: [DailyComputedDay],
        trainingLoad: TrainingLoadStatus,
        sourceLabel: String,
        lastUpdatedAt: Date,
        isAuthorized: Bool
    ) {
        self.referenceDate = referenceDate
        self.today = today
        self.historyDays = historyDays
        self.trainingLoad = trainingLoad
        self.sourceLabel = sourceLabel
        self.lastUpdatedAt = lastUpdatedAt
        self.isAuthorized = isAuthorized
    }
}

public struct AppPreferencesState: Equatable, Sendable, Codable {
    public var sleepGoalMinutes: Int
    public var subjectiveFeelingsByDay: [String: Int]

    public init(
        sleepGoalMinutes: Int = 450,
        subjectiveFeelingsByDay: [String: Int] = [:]
    ) {
        self.sleepGoalMinutes = sleepGoalMinutes
        self.subjectiveFeelingsByDay = subjectiveFeelingsByDay
    }
}

public enum AIBriefingStatus: Equatable, Hashable, Sendable {
    case idle
    case loading
    case generated(text: String, engineName: String)
    case unconfigured(reason: String)
}

public struct CoachMessage: Identifiable, Equatable, Sendable, Codable {
    public enum Role: String, Hashable, Sendable, Codable {
        case user
        case assistant
    }

    public let id: UUID
    public let role: Role
    public let text: String
    public let engineLabel: String?
    public let timestamp: Date
    public let evidenceMetric: MetricKind?
    public let workoutProposal: WorkoutProposal?
    public let memorySavedNote: String?

    public init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        engineLabel: String? = nil,
        timestamp: Date = .now,
        evidenceMetric: MetricKind? = nil,
        workoutProposal: WorkoutProposal? = nil,
        memorySavedNote: String? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.engineLabel = engineLabel
        self.timestamp = timestamp
        self.evidenceMetric = evidenceMetric
        self.workoutProposal = workoutProposal
        self.memorySavedNote = memorySavedNote
    }
}

public extension Date {
    func dayKey(calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: self)
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        let d = comps.day ?? 0
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}
