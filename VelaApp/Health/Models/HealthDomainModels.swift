import Foundation
@preconcurrency import HealthKit

/// Outcome of a HealthKit read. `noData` is intentionally distinct from a
/// failed read so callers can preserve missing-data semantics without hiding
/// permission, availability, or transient system failures.
enum HealthQueryOutcomeKind: String, Codable, Equatable, Sendable {
    case data
    case noData
    case denied
    case unavailable
    case transient
    case failed

    var isFailure: Bool {
        switch self {
        case .denied, .unavailable, .transient, .failed:
            return true
        case .data, .noData:
            return false
        }
    }
}

/// Machine-readable diagnostic attached to one HealthKit component/query.
/// Error text is deliberately omitted: localized descriptions are unstable
/// and should never drive product behaviour or persistence decisions.
struct HealthQueryDiagnostic: Codable, Equatable, Hashable, Sendable {
    var component: String
    var outcome: HealthQueryOutcomeKind
    var errorDomain: String?
    var errorCode: Int?

    init(
        component: String,
        outcome: HealthQueryOutcomeKind,
        error: Error? = nil
    ) {
        self.component = component
        self.outcome = outcome
        let nsError = error.map { $0 as NSError }
        self.errorDomain = nsError?.domain
        self.errorCode = nsError?.code
    }
}

/// Classifies HealthKit errors without inspecting localized text.
enum HealthKitQueryOutcomeClassifier {
    static func classify(_ error: Error) -> HealthQueryOutcomeKind {
        let nsError = error as NSError
        guard nsError.domain == HKErrorDomain,
              let code = HKError.Code(rawValue: nsError.code) else {
            return .failed
        }

        switch code {
        case .errorNoData:
            return .noData
        case .errorAuthorizationDenied, .errorAuthorizationNotDetermined:
            return .denied
        case .errorHealthDataUnavailable, .errorHealthDataRestricted:
            return .unavailable
        case .errorDatabaseInaccessible:
            return .transient
        default:
            return .failed
        }
    }
}

struct DailyHealthSnapshot: Identifiable, Hashable, Sendable {
    let id = UUID()
    var date: Date
    var createdAt: Date = Date()
    var sleepScore: Double?
    var recoveryScore: Double?
    var strainScore: Double?
    var stressIndex: Double?
    var morningEnergy: Double?
    var currentEnergy: Double?
    var energyBank: Double?
    // Raw metrics for historical trend analysis
    var healthAge: Double?
    var hrvAverage: Double?
    var hrvRmssdMilliseconds: Double?
    var restingHeartRate: Double?
    var sleepHours: Double?
    var deepSleepPercent: Double?
    var remSleepPercent: Double?
    var sleepEfficiency: Double?
    var steps: Double?
    var activeCalories: Double?
    var activeMinutes: Double?
    var workoutCount: Int?
    var workoutTypes: String?
    var workoutDuration: Double?
    var bodyWeight: Double?
    var bodyFatPercent: Double?
    var vo2Max: Double?
    var bmi: Double?
    var oxygenSaturation: Double?
    var respiratoryRate: Double?
    var wristTemperature: Double?
    var dailyLoad: Double?
    var workoutLoad: Double?
    var activityLoad: Double?
    var trainingLoadRatio: Double?
    var atl: Double?
    var ctl: Double?
    var tsb: Double?
    var acwr: Double?
    var bedtime: Date?
    var wakeTime: Date?
    var awakeMinutes: Double?
    var awakeEpisodeCount: Int?
    var deepSleepMinutes: Double?
    var remSleepMinutes: Double?
    var workouts: [WorkoutSummary] = []
    var hrvObservedAt: Date?
    var rhrObservedAt: Date?
    var spo2ObservedAt: Date?
    var hrvObservedWindow: DateInterval?
}

enum SleepStage: String, Codable, Hashable, CaseIterable {
    case awake
    case rem
    case core
    case deep
    case asleep
    case inBed

    var countsTowardSleepDuration: Bool {
        switch self {
        case .rem, .core, .deep, .asleep:
            return true
        case .awake, .inBed:
            return false
        }
    }
}

struct SleepStageSegment: Identifiable, Codable, Hashable {
    var id = UUID()
    var stage: SleepStage
    var start: Date
    var end: Date

    var durationMinutes: Int {
        max(Int(end.timeIntervalSince(start) / 60), 0)
    }
}

struct SleepSummary: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var totalSleepMinutes: Int
    var bedtime: Date?
    var wakeTime: Date?
    var stageMinutes: [SleepStage: Int]
    var segments: [SleepStageSegment]
    var sleepScore: Double?
}

struct RecoveryMetricSummary: Codable, Hashable {
    var hrvMilliseconds: Double?
    var hrvRmssdMilliseconds: Double?
    var restingHeartRate: Double?
    var sleepHeartRate: Double?
    var respiratoryRate: Double?
}

struct StrainActivitySummary: Codable, Hashable {
    var activeEnergyKilocalories: Double?
    var exerciseMinutes: Double?
    var stepCount: Double?
    var workouts: [WorkoutSummary]
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

struct BodyMetricsSummary: Codable, Hashable {
    var vo2Max: Double?
    var weightKilograms: Double?
    var bodyFatPercentage: Double?
    var leanBodyMassKilograms: Double?
}

/// Extended metrics gathered from the full HealthKit catalog
struct ExtendedHealthMetrics: Codable, Hashable {
    // Personal characteristics (from HKCharacteristicType)
    var age: Int?
    var biologicalSex: String?         // "male" / "female" / "other"
    var heightCm: Double?
    var bmi: Double?
    var bodyWeightKg: Double?
    var bodyFatPercent: Double?

    // Cardiovascular advanced
    var walkingHeartRateAvg: Double?    // bpm
    var oxygenSaturation: Double?      // 0-100 %
    var bloodPressureSystolic: Double?  // mmHg
    var bloodPressureDiastolic: Double? // mmHg

    // Metabolic
    var bloodGlucose: Double?          // mg/dL

    // Mobility & gait
    var walkingSpeed: Double?          // m/s
    var walkingStepLength: Double?     // m
    var walkingAsymmetry: Double?      // % (0-100)
    var walkingDoubleSupport: Double?  // % (0-100)
    var walkingSteadiness: Double?     // % (0-100)
    var stairAscentSpeed: Double?      // m/s
    var stairDescentSpeed: Double?     // m/s
    var sixMinuteWalkDistance: Double?  // meters

    // Activity totals
    var exerciseMinutes: Int?
    var standMinutes: Int?
    var flightsClimbed: Int?
    var distanceKm: Double?
    var cyclingDistanceKm: Double?

    // Environment
    var environmentalNoisedB: Double?
    var headphoneNoisedB: Double?
    var timeInDaylight: Double?        // minutes

    // Temperature
    var bodyTemperature: Double?       // °C

    // Nutrition
    var waterMl: Double?
    var caffeineMg: Double?
    var dietaryEnergyKcal: Double?
    var dietaryProteinG: Double?
    var dietaryCarbsG: Double?
    var dietaryFatG: Double?

    // Wellness
    var mindfulMinutes: Double?
    var sleepBreathingDisturbances: Double? // events/night
}

struct HeartRateSample: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var bpm: Double
}

/// 逐小时聚合值（步数/活动能量等累计型指标）。
struct HourlyQuantity: Equatable, Sendable {
    var hour: Int
    var value: Double
}

enum SleepHeartRateRangeResolver {
    static func range(for episodes: [SleepSummary], fallback: DateRangeQuery) -> DateRangeQuery {
        let candidates = episodes.compactMap { episode -> DateRangeQuery? in
            guard let start = episode.bedtime,
                  let end = episode.wakeTime,
                  end > start else {
                return nil
            }
            return DateRangeQuery(start: start, end: end)
        }
        return candidates.max { $0.end < $1.end } ?? fallback
    }
}

enum WorkoutHeartRateAverager {
    static func averageHeartRates(samples: [HeartRateSample], workouts: [WorkoutSummary]) -> [UUID: Double] {
        guard !samples.isEmpty, !workouts.isEmpty else { return [:] }
        // 性能修复：此前每个训练对全量样本做一次 filter，O(训练数 × 样本数)——
        // 60 天窗口 + 数十万心率样本时每次刷新要几秒。
        // 改为双指针单遍归并（O(n+m)）：样本按时间升序，训练按开始时间升序，
        // 每个样本只考察一次；重叠训练（罕见）保持旧语义：同时计入两者。
        let sortedWorkouts = workouts.sorted { $0.start < $1.start }
        let sortedSamples = samples.sorted { $0.date < $1.date }

        var sums: [UUID: Double] = [:]
        var counts: [UUID: Int] = [:]

        func accumulate(_ bpm: Double, for workout: WorkoutSummary) {
            sums[workout.id, default: 0] += bpm
            counts[workout.id, default: 0] += 1
        }

        var sampleIndex = 0
        var workoutIndex = 0
        while sampleIndex < sortedSamples.count, workoutIndex < sortedWorkouts.count {
            let sample = sortedSamples[sampleIndex]
            let workout = sortedWorkouts[workoutIndex]
            if sample.date < workout.start {
                sampleIndex += 1
                continue
            }
            if sample.date > workout.end {
                workoutIndex += 1
                continue
            }
            accumulate(sample.bpm, for: workout)
            // 重叠训练：后续开始时间早于当前样本的训练也计入（与旧 filter 语义一致）。
            var next = workoutIndex + 1
            while next < sortedWorkouts.count, sortedWorkouts[next].start <= sample.date {
                if sample.date <= sortedWorkouts[next].end {
                    accumulate(sample.bpm, for: sortedWorkouts[next])
                }
                next += 1
            }
            sampleIndex += 1
        }

        var result: [UUID: Double] = [:]
        for (id, sum) in sums {
            guard let count = counts[id], count > 0 else { continue }
            result[id] = sum / Double(count)
        }
        return result
    }
}

struct BloodGlucoseReading: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var milligramsPerDeciliter: Double
}

struct RouteCoordinate: Identifiable, Codable, Hashable {
    var id = UUID()
    var latitude: Double
    var longitude: Double
}

// MARK: - Historical sleep day aggregation

/// 历史回填用：把睡眠阶段段按健康日（默认 04:00 边界）聚合到每一天。
/// 跨边界的睡眠段按时间比例拆分到两天（与同步引擎的健康日归属语义一致）。
/// 纯函数，测试覆盖。
enum SleepDayAggregator {
    struct SleepDayBucket: Equatable {
        var sleepMinutes: Double = 0
        var deepMinutes: Double = 0
        var remMinutes: Double = 0
    }

    static func aggregate(
        segments: [SleepStageSegment],
        boundaryMinutes: Int = HealthDaySettings.boundaryMinutes(),
        calendar: Calendar = .current
    ) -> [Date: SleepDayBucket] {
        let boundary = HealthDayBoundary(calendar: calendar, boundaryMinutes: boundaryMinutes)
        var result: [Date: SleepDayBucket] = [:]

        for segment in segments {
            guard segment.end > segment.start else { continue }
            var cursor = segment.start
            while cursor < segment.end {
                let day = boundary.labelDate(containing: cursor)
                let dayRange = boundary.range(forLabelDate: day)
                let cut = min(segment.end, dayRange.end)
                let minutes = max(0, cut.timeIntervalSince(cursor) / 60.0)
                if minutes > 0 {
                    var bucket = result[day] ?? SleepDayBucket()
                    switch segment.stage {
                    case .deep:
                        bucket.deepMinutes += minutes
                        bucket.sleepMinutes += minutes
                    case .rem:
                        bucket.remMinutes += minutes
                        bucket.sleepMinutes += minutes
                    case .core, .asleep:
                        bucket.sleepMinutes += minutes
                    case .awake, .inBed:
                        break
                    }
                    result[day] = bucket
                }
                cursor = cut
            }
        }
        return result
    }
}
