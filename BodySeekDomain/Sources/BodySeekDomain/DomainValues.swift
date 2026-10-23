import Foundation

/// The platform-neutral evidence collected for one health day.
///
/// HealthKit, SwiftData, and other adapters translate their records into this
/// value before invoking a domain computation. Missing values remain `nil`;
/// they are never silently converted to zero by the domain model.
public struct DailyHealthSnapshot: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var createdAt: Date

    // Computed score projections (kept here for replay/persistence compatibility).
    public var sleepScore: Double?
    public var recoveryScore: Double?
    public var strainScore: Double?
    public var stressIndex: Double?
    public var morningEnergy: Double?
    public var currentEnergy: Double?
    public var energyBank: Double?

    // Raw evidence used by scoring and trend adapters.
    public var healthAge: Double?
    public var hrvAverage: Double?
    public var hrvRmssdMilliseconds: Double?
    public var restingHeartRate: Double?
    public var sleepHours: Double?
    public var deepSleepPercent: Double?
    public var remSleepPercent: Double?
    public var sleepEfficiency: Double?
    public var steps: Double?
    public var activeCalories: Double?
    public var activeMinutes: Double?
    public var workoutCount: Int?
    public var workoutTypes: String?
    public var workoutDuration: Double?
    public var bodyWeight: Double?
    public var bodyFatPercent: Double?
    public var vo2Max: Double?
    public var bmi: Double?
    public var oxygenSaturation: Double?
    public var respiratoryRate: Double?
    public var wristTemperature: Double?
    public var dailyLoad: Double?
    public var workoutLoad: Double?
    public var activityLoad: Double?
    public var trainingLoadRatio: Double?
    public var atl: Double?
    public var ctl: Double?
    public var tsb: Double?
    public var acwr: Double?
    public var bedtime: Date?
    public var wakeTime: Date?
    public var awakeMinutes: Double?
    public var awakeEpisodeCount: Int?
    public var deepSleepMinutes: Double?
    public var remSleepMinutes: Double?
    public var workouts: [WorkoutSummary]
    public var hrvObservedAt: Date?
    public var rhrObservedAt: Date?
    public var spo2ObservedAt: Date?
    public var hrvObservedWindow: DateInterval?
    public var rhrObservedWindow: DateInterval?

    public init(
        id: UUID = UUID(),
        date: Date,
        createdAt: Date? = nil,
        sleepScore: Double? = nil,
        recoveryScore: Double? = nil,
        strainScore: Double? = nil,
        stressIndex: Double? = nil,
        morningEnergy: Double? = nil,
        currentEnergy: Double? = nil,
        energyBank: Double? = nil,
        healthAge: Double? = nil,
        hrvAverage: Double? = nil,
        hrvRmssdMilliseconds: Double? = nil,
        restingHeartRate: Double? = nil,
        sleepHours: Double? = nil,
        deepSleepPercent: Double? = nil,
        remSleepPercent: Double? = nil,
        sleepEfficiency: Double? = nil,
        steps: Double? = nil,
        activeCalories: Double? = nil,
        activeMinutes: Double? = nil,
        workoutCount: Int? = nil,
        workoutTypes: String? = nil,
        workoutDuration: Double? = nil,
        bodyWeight: Double? = nil,
        bodyFatPercent: Double? = nil,
        vo2Max: Double? = nil,
        bmi: Double? = nil,
        oxygenSaturation: Double? = nil,
        respiratoryRate: Double? = nil,
        wristTemperature: Double? = nil,
        dailyLoad: Double? = nil,
        workoutLoad: Double? = nil,
        activityLoad: Double? = nil,
        trainingLoadRatio: Double? = nil,
        atl: Double? = nil,
        ctl: Double? = nil,
        tsb: Double? = nil,
        acwr: Double? = nil,
        bedtime: Date? = nil,
        wakeTime: Date? = nil,
        awakeMinutes: Double? = nil,
        awakeEpisodeCount: Int? = nil,
        deepSleepMinutes: Double? = nil,
        remSleepMinutes: Double? = nil,
        workouts: [WorkoutSummary] = [],
        hrvObservedAt: Date? = nil,
        rhrObservedAt: Date? = nil,
        spo2ObservedAt: Date? = nil,
        hrvObservedWindow: DateInterval? = nil,
        rhrObservedWindow: DateInterval? = nil
    ) {
        self.id = id
        self.date = date
        self.createdAt = createdAt ?? Date()
        self.sleepScore = sleepScore
        self.recoveryScore = recoveryScore
        self.strainScore = strainScore
        self.stressIndex = stressIndex
        self.morningEnergy = morningEnergy
        self.currentEnergy = currentEnergy
        self.energyBank = energyBank
        self.healthAge = healthAge
        self.hrvAverage = hrvAverage
        self.hrvRmssdMilliseconds = hrvRmssdMilliseconds
        self.restingHeartRate = restingHeartRate
        self.sleepHours = sleepHours
        self.deepSleepPercent = deepSleepPercent
        self.remSleepPercent = remSleepPercent
        self.sleepEfficiency = sleepEfficiency
        self.steps = steps
        self.activeCalories = activeCalories
        self.activeMinutes = activeMinutes
        self.workoutCount = workoutCount
        self.workoutTypes = workoutTypes
        self.workoutDuration = workoutDuration
        self.bodyWeight = bodyWeight
        self.bodyFatPercent = bodyFatPercent
        self.vo2Max = vo2Max
        self.bmi = bmi
        self.oxygenSaturation = oxygenSaturation
        self.respiratoryRate = respiratoryRate
        self.wristTemperature = wristTemperature
        self.dailyLoad = dailyLoad
        self.workoutLoad = workoutLoad
        self.activityLoad = activityLoad
        self.trainingLoadRatio = trainingLoadRatio
        self.atl = atl
        self.ctl = ctl
        self.tsb = tsb
        self.acwr = acwr
        self.bedtime = bedtime
        self.wakeTime = wakeTime
        self.awakeMinutes = awakeMinutes
        self.awakeEpisodeCount = awakeEpisodeCount
        self.deepSleepMinutes = deepSleepMinutes
        self.remSleepMinutes = remSleepMinutes
        self.workouts = workouts
        self.hrvObservedAt = hrvObservedAt
        self.rhrObservedAt = rhrObservedAt
        self.spo2ObservedAt = spo2ObservedAt
        self.hrvObservedWindow = hrvObservedWindow
        self.rhrObservedWindow = rhrObservedWindow
    }
}

public enum SleepStage: String, Codable, Hashable, CaseIterable, Sendable {
    case awake
    case rem
    case core
    case deep
    case asleep
    case inBed

    public var countsTowardSleepDuration: Bool {
        switch self {
        case .rem, .core, .deep, .asleep:
            true
        case .awake, .inBed:
            false
        }
    }
}

public struct SleepStageSegment: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var stage: SleepStage
    public var start: Date
    public var end: Date

    public init(
        id: UUID = UUID(),
        stage: SleepStage,
        start: Date,
        end: Date
    ) {
        self.id = id
        self.stage = stage
        self.start = start
        self.end = end
    }

    public var durationMinutes: Int {
        max(Int(end.timeIntervalSince(start) / 60), 0)
    }
}

public struct SleepSummary: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var totalSleepMinutes: Int
    public var bedtime: Date?
    public var wakeTime: Date?
    public var stageMinutes: [SleepStage: Int]
    public var segments: [SleepStageSegment]
    public var sleepScore: Double?

    public init(
        id: UUID = UUID(),
        date: Date,
        totalSleepMinutes: Int,
        bedtime: Date? = nil,
        wakeTime: Date? = nil,
        stageMinutes: [SleepStage: Int] = [:],
        segments: [SleepStageSegment] = [],
        sleepScore: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.totalSleepMinutes = totalSleepMinutes
        self.bedtime = bedtime
        self.wakeTime = wakeTime
        self.stageMinutes = stageMinutes
        self.segments = segments
        self.sleepScore = sleepScore
    }
}

public struct WorkoutSummary: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var start: Date
    public var end: Date
    public var activityName: String
    public var energyKilocalories: Double?
    public var averageHeartRate: Double?
    public var heartRateRecoveryOneMinuteBPM: Double?
    public var distanceMeters: Double?
    public var source: String?
    public var rpe: Double?

    public init(
        id: UUID = UUID(),
        start: Date,
        end: Date,
        activityName: String,
        energyKilocalories: Double? = nil,
        averageHeartRate: Double? = nil,
        heartRateRecoveryOneMinuteBPM: Double? = nil,
        distanceMeters: Double? = nil,
        source: String? = nil,
        rpe: Double? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.activityName = activityName
        self.energyKilocalories = energyKilocalories
        self.averageHeartRate = averageHeartRate
        self.heartRateRecoveryOneMinuteBPM = heartRateRecoveryOneMinuteBPM
        self.distanceMeters = distanceMeters
        self.source = source
        self.rpe = rpe
    }
}
