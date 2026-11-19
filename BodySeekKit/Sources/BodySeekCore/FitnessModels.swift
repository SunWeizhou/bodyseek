import Foundation

/// Anatomical muscle group identifiers matching `MuscleMap.Muscle` raw values cleanly
/// while keeping `BodySeekCore` dependency-free.
public enum BodyRegionMuscle: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
    case chest
    case upperBack = "upper-back"
    case lowerBack = "lower-back"
    case deltoids
    case biceps
    case triceps
    case forearm
    case abs
    case obliques
    case quadriceps
    case hamstring
    case gluteal
    case calves
    case trapezius

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .chest: "胸部"
        case .upperBack: "上背与背阔"
        case .lowerBack: "下背"
        case .deltoids: "肩部三角肌"
        case .biceps: "肱二头肌"
        case .triceps: "肱三头肌"
        case .forearm: "前臂"
        case .abs: "腹肌"
        case .obliques: "腹斜肌"
        case .quadriceps: "股四头肌"
        case .hamstring: "腘绳肌"
        case .gluteal: "臀肌"
        case .calves: "小腿"
        case .trapezius: "斜方肌"
        }
    }
}

public enum ExerciseCategory: String, CaseIterable, Hashable, Sendable, Codable {
    case strength
    case cardio
    case mobility

    public var title: String {
        switch self {
        case .strength: "力量"
        case .cardio: "有氧"
        case .mobility: "恢复拉伸"
        }
    }
}

public struct ExerciseDefinition: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let name: String
    public let englishName: String
    public let category: ExerciseCategory
    public let equipment: String
    public let primaryMuscles: [BodyRegionMuscle]
    public let secondaryMuscles: [BodyRegionMuscle]
    public let instructions: String

    public init(
        id: String,
        name: String,
        englishName: String,
        category: ExerciseCategory,
        equipment: String,
        primaryMuscles: [BodyRegionMuscle],
        secondaryMuscles: [BodyRegionMuscle] = [],
        instructions: String
    ) {
        self.id = id
        self.name = name
        self.englishName = englishName
        self.category = category
        self.equipment = equipment
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.instructions = instructions
    }
}

public struct PlannedExerciseItem: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let exerciseID: String
    public let targetSets: Int
    public let targetReps: Int
    public let targetWeightKg: Double
    public let restSeconds: Int

    public init(
        id: UUID = UUID(),
        exerciseID: String,
        targetSets: Int,
        targetReps: Int,
        targetWeightKg: Double,
        restSeconds: Int = 90
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetWeightKg = targetWeightKg
        self.restSeconds = restSeconds
    }
}

public struct WorkoutTemplate: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var title: String
    public var subtitle: String
    public var focusTag: String
    public var estimatedMinutes: Int
    public var exercises: [PlannedExerciseItem]
    public var isAIGenerated: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        focusTag: String,
        estimatedMinutes: Int,
        exercises: [PlannedExerciseItem],
        isAIGenerated: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.focusTag = focusTag
        self.estimatedMinutes = estimatedMinutes
        self.exercises = exercises
        self.isAIGenerated = isAIGenerated
    }

    public var primaryMuscles: [BodyRegionMuscle] {
        var seen: Set<BodyRegionMuscle> = []
        var result: [BodyRegionMuscle] = []
        for item in exercises {
            if let def = ExerciseCatalog.find(id: item.exerciseID) {
                for m in def.primaryMuscles where seen.insert(m).inserted {
                    result.append(m)
                }
            }
        }
        return result
    }
}

public struct LoggedSetEntry: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var setIndex: Int
    public var weightKg: Double
    public var reps: Int
    public var isCompleted: Bool

    public init(
        id: UUID = UUID(),
        setIndex: Int,
        weightKg: Double,
        reps: Int,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.setIndex = setIndex
        self.weightKg = weightKg
        self.reps = reps
        self.isCompleted = isCompleted
    }
}

public struct LoggedExerciseRecord: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let exerciseID: String
    public var sets: [LoggedSetEntry]
    public var restSeconds: Int

    public init(
        id: UUID = UUID(),
        exerciseID: String,
        sets: [LoggedSetEntry],
        restSeconds: Int = 90
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.sets = sets
        self.restSeconds = restSeconds
    }

    public var completedVolumeKg: Double {
        sets.filter(\.isCompleted).reduce(0) { $0 + ($1.weightKg * Double($1.reps)) }
    }
}

public struct LoggedWorkoutSession: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var title: String
    public var startedAt: Date
    public var completedAt: Date
    public var exercises: [LoggedExerciseRecord]
    public var rpe: Int
    public var estimatedCalories: Double
    public var syncedHealthKitUUID: String?
    public var notes: String

    public init(
        id: UUID = UUID(),
        title: String,
        startedAt: Date,
        completedAt: Date,
        exercises: [LoggedExerciseRecord],
        rpe: Int,
        estimatedCalories: Double,
        syncedHealthKitUUID: String? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.exercises = exercises
        self.rpe = rpe
        self.estimatedCalories = estimatedCalories
        self.syncedHealthKitUUID = syncedHealthKitUUID
        self.notes = notes
    }

    public var durationMinutes: Int {
        max(1, Int((completedAt.timeIntervalSince(startedAt) / 60).rounded()))
    }

    public var totalVolumeKg: Double {
        exercises.reduce(0) { $0 + $1.completedVolumeKg }
    }

    public var muscleLoadIntensities: [BodyRegionMuscle: Double] {
        var load: [BodyRegionMuscle: Double] = [:]
        for record in exercises {
            let completedSets = Double(record.sets.filter(\.isCompleted).count)
            guard completedSets > 0, let def = ExerciseCatalog.find(id: record.exerciseID) else { continue }
            for primary in def.primaryMuscles {
                load[primary, default: 0] += completedSets * 0.22
            }
            for secondary in def.secondaryMuscles {
                load[secondary, default: 0] += completedSets * 0.10
            }
        }
        return load.mapValues { min(1.0, $0) }
    }
}

public struct ActiveWorkoutDraft: Equatable, Hashable, Sendable, Codable {
    public let id: UUID
    public var title: String
    public var startedAt: Date
    public var exercises: [LoggedExerciseRecord]
    public var rpe: Int
    public var restSecondsRemaining: Int?
    public var restEndsAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        startedAt: Date = .now,
        exercises: [LoggedExerciseRecord],
        rpe: Int = 7,
        restSecondsRemaining: Int? = nil,
        restEndsAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.exercises = exercises
        self.rpe = rpe
        self.restSecondsRemaining = restSecondsRemaining
        self.restEndsAt = restEndsAt
    }

    public static func from(template: WorkoutTemplate, now: Date = .now) -> ActiveWorkoutDraft {
        let records = template.exercises.map { item in
            let sets = (1...max(1, item.targetSets)).map { idx in
                LoggedSetEntry(
                    setIndex: idx,
                    weightKg: item.targetWeightKg,
                    reps: item.targetReps,
                    isCompleted: false
                )
            }
            return LoggedExerciseRecord(
                exerciseID: item.exerciseID,
                sets: sets,
                restSeconds: item.restSeconds
            )
        }
        return ActiveWorkoutDraft(title: template.title, startedAt: now, exercises: records)
    }

    public var completedSetCount: Int {
        exercises.flatMap(\.sets).filter(\.isCompleted).count
    }

    public var totalSetCount: Int {
        exercises.flatMap(\.sets).count
    }

    public var totalCompletedVolumeKg: Double {
        exercises.reduce(0) { $0 + $1.completedVolumeKg }
    }
}

public enum AthleteMemoryCategory: String, CaseIterable, Hashable, Sendable, Codable {
    case injury
    case goal
    case preference
    case schedule

    public var title: String {
        switch self {
        case .injury: "伤病/受限"
        case .goal: "长期目标"
        case .preference: "训练偏好"
        case .schedule: "作息与频率"
        }
    }
}

public struct AthleteMemoryItem: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let category: AthleteMemoryCategory
    public var content: String
    public let updatedAt: Date

    public init(
        id: UUID = UUID(),
        category: AthleteMemoryCategory,
        content: String,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.category = category
        self.content = content
        self.updatedAt = updatedAt
    }
}

public struct WorkoutProposal: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let template: WorkoutTemplate
    public let rationale: String

    public init(id: UUID = UUID(), template: WorkoutTemplate, rationale: String) {
        self.id = id
        self.template = template
        self.rationale = rationale
    }
}

public enum ACWRZone: String, Hashable, Sendable, Codable {
    case undertraining
    case sweetSpot
    case highRisk
    case insufficientData

    public var title: String {
        switch self {
        case .undertraining: "负荷偏低"
        case .sweetSpot: "甜蜜推进区"
        case .highRisk: "过载预警"
        case .insufficientData: "基线积累中"
        }
    }

    public var note: String {
        switch self {
        case .undertraining: "近 7 天负荷低于平时 28 天水平，可按恢复条件适度增量。"
        case .sweetSpot: "7天/28天负荷比落在 0.8–1.3 最佳区间，稳步提升体能。"
        case .highRisk: "近期负荷拉升偏快（>1.35），注意减组与补觉预防劳损。"
        case .insufficientData: "持续记录至少 7 天活动后生成急性/慢性负荷比。"
        }
    }
}

public struct TrainingLoadStatus: Equatable, Hashable, Sendable, Codable {
    public let acute7dLoad: Double
    public let chronic28dWeeklyAvg: Double
    public let acwrRatio: Double?
    public let zone: ACWRZone

    public init(
        acute7dLoad: Double,
        chronic28dWeeklyAvg: Double,
        acwrRatio: Double?,
        zone: ACWRZone
    ) {
        self.acute7dLoad = acute7dLoad
        self.chronic28dWeeklyAvg = chronic28dWeeklyAvg
        self.acwrRatio = acwrRatio
        self.zone = zone
    }
}
