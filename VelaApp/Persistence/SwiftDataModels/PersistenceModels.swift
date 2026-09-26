import Foundation
import SwiftData

struct DailyScoreEvidenceEnvelope: Codable, Hashable {
    static let currentVersion = 1

    var version: Int
    var sleep: MetricResult
    var recovery: MetricResult
    var strain: MetricResult
    var stress: MetricResult
    var energy: MetricResult
    var persistedAt: Date

    init(
        version: Int = currentVersion,
        sleep: MetricResult,
        recovery: MetricResult,
        strain: MetricResult,
        stress: MetricResult,
        energy: MetricResult,
        persistedAt: Date = Date()
    ) {
        self.version = version
        self.sleep = sleep
        self.recovery = recovery
        self.strain = strain
        self.stress = stress
        self.energy = energy
        self.persistedAt = persistedAt
    }

    init(evidence: ScoredHealthEvidence, persistedAt: Date = Date()) {
        self.init(
            sleep: evidence.sleep,
            recovery: evidence.recovery,
            strain: evidence.strain,
            stress: evidence.physiologicalStress,
            energy: evidence.energy,
            persistedAt: persistedAt
        )
    }
}

struct IntradaySignalPoint: Hashable, Sendable {
    var date: Date
    var value: Double
    var sourceIdentifier: String = "unknown"
}

struct IntradaySignalBucket: Hashable, Sendable {
    var signal: HealthSignal
    var start: Date
    var end: Date
    var average: Double
    var minimum: Double
    var maximum: Double
    var sampleCount: Int
    var unit: String
    var sourceIdentifier: String
}

enum IntradaySignalBucketizer {
    static func bucket(
        points: [IntradaySignalPoint],
        signal: HealthSignal,
        unit: String,
        sourceIdentifier: String,
        interval: TimeInterval = 5 * 60
    ) -> [IntradaySignalBucket] {
        guard interval > 0 else { return [] }
        let groups = Dictionary(grouping: points) { point in
            floor(point.date.timeIntervalSince1970 / interval) * interval
        }
        return groups.compactMap { epoch, values in
            guard !values.isEmpty else { return nil }
            let start = Date(timeIntervalSince1970: epoch)
            let scalarValues = values.map(\.value)
            return IntradaySignalBucket(
                signal: signal,
                start: start,
                end: start.addingTimeInterval(interval),
                average: scalarValues.reduce(0, +) / Double(scalarValues.count),
                minimum: scalarValues.min() ?? 0,
                maximum: scalarValues.max() ?? 0,
                sampleCount: scalarValues.count,
                unit: unit,
                sourceIdentifier: sourceIdentifier
            )
        }
        .sorted { $0.start < $1.start }
    }
}

@Model
final class IntradaySignalBucketRecord {
    @Attribute(.unique) var id: String
    var dayIdentifier: String
    var signalRawValue: String
    var bucketStart: Date
    var bucketEnd: Date
    var average: Double
    var minimum: Double
    var maximum: Double
    var sampleCount: Int
    var unit: String
    var sourceIdentifier: String
    var sourceRevision: String
    var updatedAt: Date

    init(
        bucket: IntradaySignalBucket,
        sourceRevision: String = "healthKit.v1",
        calendar: Calendar = .current,
        updatedAt: Date = Date()
    ) {
        let dayIdentifier = DailyHealthSummaryRecord.dayIdentifier(
            for: bucket.start,
            calendar: calendar
        )
        self.id = [
            dayIdentifier,
            bucket.signal.rawValue,
            String(Int(bucket.start.timeIntervalSince1970)),
            bucket.sourceIdentifier
        ].joined(separator: "|")
        self.dayIdentifier = dayIdentifier
        self.signalRawValue = bucket.signal.rawValue
        self.bucketStart = bucket.start
        self.bucketEnd = bucket.end
        self.average = bucket.average
        self.minimum = bucket.minimum
        self.maximum = bucket.maximum
        self.sampleCount = bucket.sampleCount
        self.unit = bucket.unit
        self.sourceIdentifier = bucket.sourceIdentifier
        self.sourceRevision = sourceRevision
        self.updatedAt = updatedAt
    }

    func apply(bucket: IntradaySignalBucket, sourceRevision: String, updatedAt: Date = Date()) {
        bucketStart = bucket.start
        bucketEnd = bucket.end
        average = bucket.average
        minimum = bucket.minimum
        maximum = bucket.maximum
        sampleCount = bucket.sampleCount
        unit = bucket.unit
        sourceIdentifier = bucket.sourceIdentifier
        self.sourceRevision = sourceRevision
        self.updatedAt = updatedAt
    }
}

@Model
final class DailyHealthSummaryRecord {
    @Attribute(.unique) var dayIdentifier: String
    var date: Date
    var sleepScore: Double?
    // Algorithm/source/confidence: RecoveryScoreEngine v1 derived from sleep, HRV, RHR and prior strain.
    // Stored as a daily cache of the latest HealthKit-derived score; confidence is carried by MetricResult upstream.
    var recoveryScore: Double?
    // Algorithm/source/confidence: StrainScoreEngine v1 derived from active energy, exercise minutes and workout load.
    // Stored as a daily cache of the latest mixed HealthKit/local workout score.
    var strainScore: Double?
    var stressIndex: Double?
    var morningEnergy: Double?
    var currentEnergy: Double?
    var energyBank: Double?
    var configVersion: String
    var schemaVersion: Int
    var updatedAt: Date
    var createdAt: Date
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
    var bmi: Double?
    var oxygenSaturation: Double?
    var respiratoryRate: Double?
    var wristTemperature: Double?
    // Algorithm/source/confidence: workoutAggregation.v1 combines activityLoad with session-RPE workout load.
    // Source is mixed HealthKit WorkoutSummary + WorkoutEventRecord; confidence is medium with RPE/HR, low with duration fallback.
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
    
    // Core Metrics v1.3 Additions
    var awakeMinutes: Double?
    var awakeEpisodeCount: Int?
    var deepSleepMinutes: Double?
    var remSleepMinutes: Double?
    @Attribute(.externalStorage) var workoutsData: Data?
    @Attribute(.externalStorage) var scoreEvidenceData: Data?

    init(
        dayIdentifier: String,
        date: Date,
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
        workoutsData: Data? = nil,
        scoreEvidenceData: Data? = nil,
        configVersion: String = VelaAppMetadata.configVersion,
        schemaVersion: Int = 2,
        updatedAt: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.dayIdentifier = dayIdentifier
        self.date = date
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
        self.workoutsData = workoutsData
        self.scoreEvidenceData = scoreEvidenceData
        self.configVersion = configVersion
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }

    convenience init(snapshot: DailyHealthSnapshot, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: snapshot.date)
        self.init(
            dayIdentifier: Self.dayIdentifier(for: day, calendar: calendar),
            date: day,
            sleepScore: snapshot.sleepScore,
            recoveryScore: snapshot.recoveryScore,
            strainScore: snapshot.strainScore,
            stressIndex: snapshot.stressIndex,
            morningEnergy: snapshot.morningEnergy,
            currentEnergy: snapshot.currentEnergy,
            energyBank: snapshot.energyBank,
            healthAge: snapshot.healthAge,
            hrvAverage: snapshot.hrvAverage,
            hrvRmssdMilliseconds: snapshot.hrvRmssdMilliseconds,
            restingHeartRate: snapshot.restingHeartRate,
            sleepHours: snapshot.sleepHours,
            deepSleepPercent: snapshot.deepSleepPercent,
            remSleepPercent: snapshot.remSleepPercent,
            sleepEfficiency: snapshot.sleepEfficiency,
            steps: snapshot.steps,
            activeCalories: snapshot.activeCalories,
            activeMinutes: snapshot.activeMinutes,
            workoutCount: nil,
            workoutTypes: nil,
            workoutDuration: nil,
            bodyWeight: snapshot.bodyWeight,
            bodyFatPercent: snapshot.bodyFatPercent,
            bmi: snapshot.bmi,
            oxygenSaturation: snapshot.oxygenSaturation,
            respiratoryRate: snapshot.respiratoryRate,
            wristTemperature: snapshot.wristTemperature,
            dailyLoad: snapshot.dailyLoad,
            workoutLoad: snapshot.workoutLoad,
            activityLoad: snapshot.activityLoad,
            trainingLoadRatio: snapshot.trainingLoadRatio,
            atl: snapshot.atl,
            ctl: snapshot.ctl,
            tsb: snapshot.tsb,
            acwr: snapshot.acwr,
            bedtime: snapshot.bedtime,
            wakeTime: snapshot.wakeTime,
            awakeMinutes: snapshot.awakeMinutes,
            awakeEpisodeCount: snapshot.awakeEpisodeCount,
            deepSleepMinutes: snapshot.deepSleepMinutes,
            remSleepMinutes: snapshot.remSleepMinutes,
            workoutsData: nil
        )
    }

    func apply(snapshot: DailyHealthSnapshot, calendar: Calendar = .current, updatedAt: Date = Date()) {
        date = calendar.startOfDay(for: snapshot.date)
        dayIdentifier = Self.dayIdentifier(for: date, calendar: calendar)
        sleepScore = snapshot.sleepScore
        recoveryScore = snapshot.recoveryScore
        strainScore = snapshot.strainScore
        stressIndex = snapshot.stressIndex
        morningEnergy = snapshot.morningEnergy
        currentEnergy = snapshot.currentEnergy
        energyBank = snapshot.energyBank
        healthAge = snapshot.healthAge
        hrvAverage = snapshot.hrvAverage
        hrvRmssdMilliseconds = snapshot.hrvRmssdMilliseconds
        restingHeartRate = snapshot.restingHeartRate
        sleepHours = snapshot.sleepHours
        deepSleepPercent = snapshot.deepSleepPercent
        remSleepPercent = snapshot.remSleepPercent
        sleepEfficiency = snapshot.sleepEfficiency
        steps = snapshot.steps
        activeCalories = snapshot.activeCalories
        activeMinutes = snapshot.activeMinutes
        bodyWeight = snapshot.bodyWeight
        bodyFatPercent = snapshot.bodyFatPercent
        bmi = snapshot.bmi
        oxygenSaturation = snapshot.oxygenSaturation
        respiratoryRate = snapshot.respiratoryRate
        wristTemperature = snapshot.wristTemperature
        activityLoad = snapshot.activityLoad
        // dailyLoad/workoutLoad 由评分引擎写入（TRIMP 域），必须随快照落库；
        // aggregateDay 仅在引擎未提供时才以 session-RPE 兜底，避免两套公式
        // 写同一字段导致历史（RPE 域）与当日（TRIMP 域）量纲混用。
        dailyLoad = snapshot.dailyLoad
        workoutLoad = snapshot.workoutLoad
        trainingLoadRatio = snapshot.trainingLoadRatio
        atl = snapshot.atl
        ctl = snapshot.ctl
        tsb = snapshot.tsb
        acwr = snapshot.acwr
        bedtime = snapshot.bedtime
        wakeTime = snapshot.wakeTime
        awakeMinutes = snapshot.awakeMinutes
        awakeEpisodeCount = snapshot.awakeEpisodeCount
        deepSleepMinutes = snapshot.deepSleepMinutes
        remSleepMinutes = snapshot.remSleepMinutes
        // [10] 修复：聚合字段随快照一并落库，消除「saveDailySnapshot 必须紧跟
        // aggregateDay」的隐式契约。快照含 workouts 时写入；空快照不动存量
        //（避免部分更新路径清空已有聚合）。
        if !snapshot.workouts.isEmpty {
            workoutCount = snapshot.workoutCount ?? snapshot.workouts.count
            workoutDuration = snapshot.workoutDuration
                ?? snapshot.workouts.reduce(0) { $0 + max(0, $1.end.timeIntervalSince($1.start) / 60) }
            workoutTypes = snapshot.workoutTypes
                ?? Set(snapshot.workouts.map(\.activityName)).sorted().joined(separator: ", ")
            workoutsData = try? JSONEncoder().encode(snapshot.workouts)
        }
        configVersion = VelaAppMetadata.configVersion
        self.updatedAt = updatedAt
    }

    func apply(scoreEvidence: DailyScoreEvidenceEnvelope?) throws {
        guard let scoreEvidence else {
            scoreEvidenceData = nil
            return
        }
        scoreEvidenceData = try JSONEncoder().encode(scoreEvidence)
        configVersion = [
            scoreEvidence.sleep.algorithmVersion,
            scoreEvidence.recovery.algorithmVersion,
            scoreEvidence.strain.algorithmVersion,
            scoreEvidence.stress.algorithmVersion,
            scoreEvidence.energy.algorithmVersion
        ].joined(separator: "|")
        schemaVersion = 2
        // Never move updatedAt backwards: persistedAt is the scoring timestamp and
        // can predate the actual write. updatedAt drives dashboard cache-freshness,
        // so it must be monotonic (max of current and the evidence timestamp).
        updatedAt = max(updatedAt, scoreEvidence.persistedAt)
    }

    func decodedScoreEvidence() -> DailyScoreEvidenceEnvelope? {
        guard let scoreEvidenceData else { return nil }
        return try? JSONDecoder().decode(DailyScoreEvidenceEnvelope.self, from: scoreEvidenceData)
    }

    static func dayIdentifier(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return [
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        ]
        .map { String(format: "%02d", $0) }
        .joined(separator: "-")
    }

    static func healthDayIdentifier(
        forSampleAt date: Date,
        calendar: Calendar = .current
    ) -> String {
        let labelDate = HealthDayBoundary(calendar: calendar).labelDate(containing: date)
        return dayIdentifier(for: labelDate, calendar: calendar)
    }

    func toSnapshot() -> DailyHealthSnapshot {
        return DailyHealthSnapshot(
            date: date,
            createdAt: createdAt,
            sleepScore: sleepScore,
            recoveryScore: recoveryScore,
            strainScore: strainScore,
            stressIndex: stressIndex,
            morningEnergy: morningEnergy,
            currentEnergy: currentEnergy,
            energyBank: energyBank,
            healthAge: healthAge,
            hrvAverage: hrvAverage,
            hrvRmssdMilliseconds: hrvRmssdMilliseconds,
            restingHeartRate: restingHeartRate,
            sleepHours: sleepHours,
            deepSleepPercent: deepSleepPercent,
            remSleepPercent: remSleepPercent,
            sleepEfficiency: sleepEfficiency,
            steps: steps,
            activeCalories: activeCalories,
            activeMinutes: activeMinutes,
            workoutCount: workoutCount,
            workoutTypes: workoutTypes,
            workoutDuration: workoutDuration,
            bodyWeight: bodyWeight,
            bodyFatPercent: bodyFatPercent,
            bmi: bmi,
            oxygenSaturation: oxygenSaturation,
            respiratoryRate: respiratoryRate,
            wristTemperature: wristTemperature,
            dailyLoad: dailyLoad,
            workoutLoad: workoutLoad,
            activityLoad: activityLoad,
            trainingLoadRatio: trainingLoadRatio,
            atl: atl,
            ctl: ctl,
            tsb: tsb,
            acwr: acwr,
            bedtime: bedtime,
            wakeTime: wakeTime,
            awakeMinutes: awakeMinutes,
            awakeEpisodeCount: awakeEpisodeCount,
            deepSleepMinutes: deepSleepMinutes,
            remSleepMinutes: remSleepMinutes,
            workouts: decodedWorkouts()
        )
    }

    private func decodedWorkouts() -> [WorkoutSummary] {
        guard let workoutsData,
              let decoded = try? JSONDecoder().decode([WorkoutSummary].self, from: workoutsData) else {
            return []
        }
        return decoded
    }

}

enum StrengthSetKind: String, Codable, Hashable, CaseIterable {
    case working
    case warmup
    case drop
    case backoff
    case failure

    var displayName: String {
        switch self {
        case .working: "正式组"
        case .warmup: "热身组"
        case .drop: "递减组"
        case .backoff: "回退组"
        case .failure: "力竭组"
        }
    }

    var shortLabel: String {
        switch self {
        case .working: "正"
        case .warmup: "热"
        case .drop: "降"
        case .backoff: "退"
        case .failure: "竭"
        }
    }
}

struct StrengthSetLog: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var repetitions: Int
    var weightKilograms: Double
    var isWarmup: Bool = false
    var rpe: Double?
    var rir: Double?
    var isCompleted: Bool?
    var completedAt: Date?
    var kindRaw: String? = nil

    var kind: StrengthSetKind {
        get {
            if isWarmup { return .warmup }
            return kindRaw.flatMap(StrengthSetKind.init(rawValue:)) ?? .working
        }
        set {
            kindRaw = newValue == .working ? nil : newValue.rawValue
            isWarmup = newValue == .warmup
        }
    }

    var volumeKilograms: Double {
        guard kind != .warmup else { return 0 }
        return Double(repetitions) * weightKilograms
    }
}

enum StrengthExerciseGroupKind: String, Codable, Hashable, CaseIterable {
    case superset
    case circuit

    var displayName: String {
        switch self {
        case .superset: "超级组"
        case .circuit: "循环组"
        }
    }
}

struct StrengthExerciseLog: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var exerciseDefinitionId: UUID?
    var exerciseCanonicalKey: String?
    var name: String
    var equipment: String
    var primaryMuscleGroup: String?
    var sets: [StrengthSetLog]
    var groupID: UUID? = nil
    var groupKindRaw: String? = nil
    var groupPosition: Int? = nil

    var groupKind: StrengthExerciseGroupKind? {
        get { groupKindRaw.flatMap(StrengthExerciseGroupKind.init(rawValue:)) }
        set { groupKindRaw = newValue?.rawValue }
    }

    var volumeKilograms: Double {
        sets.reduce(0) { $0 + $1.volumeKilograms }
    }
}

@Model
final class StrengthWorkoutRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var startedAt: Date
    var durationMinutes: Int
    var notes: String
    @Attribute(.externalStorage) var exercisesData: Data
    var linkedWorkoutEventId: UUID?
    var sourceTemplateId: UUID?
    var planDayId: UUID?
    var sessionRPE: Double?
    var completedAt: Date?
    var analyticsJSON: String?

    init(
        id: UUID = UUID(),
        title: String,
        startedAt: Date = Date(),
        durationMinutes: Int,
        notes: String = "",
        exercises: [StrengthExerciseLog]
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.durationMinutes = durationMinutes
        self.notes = notes
        exercisesData = (try? JSONEncoder().encode(exercises)) ?? Data("[]".utf8)
        linkedWorkoutEventId = nil
        sourceTemplateId = nil
        planDayId = nil
        sessionRPE = nil
        completedAt = endedAt
        analyticsJSON = nil
    }

    var exercises: [StrengthExerciseLog] {
        get { (try? JSONDecoder().decode([StrengthExerciseLog].self, from: exercisesData)) ?? [] }
        set { exercisesData = (try? JSONEncoder().encode(newValue)) ?? Data("[]".utf8) }
    }

    var endedAt: Date {
        startedAt.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }

    var exerciseCount: Int {
        exercises.count
    }

    var totalSetCount: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }

    var totalRepetitionCount: Int {
        exercises.reduce(0) { exerciseTotal, exercise in
            exerciseTotal + exercise.sets.reduce(0) { $0 + $1.repetitions }
        }
    }

    var totalVolumeKilograms: Double {
        exercises.reduce(0) { $0 + $1.volumeKilograms }
    }
}

@Model
final class ActiveWorkoutDraftRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var startedAt: Date
    var templateId: UUID?
    @Attribute(.externalStorage) var exercisesJSON: String
    var notes: String
    var lastUpdated: Date

    init(
        id: UUID = UUID(),
        title: String,
        startedAt: Date = Date(),
        templateId: UUID? = nil,
        exercisesJSON: String = "[]",
        notes: String = "",
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.templateId = templateId
        self.exercisesJSON = exercisesJSON
        self.notes = notes
        self.lastUpdated = lastUpdated
    }

    @Transient
    var exercises: [StrengthExerciseLog] {
        get {
            guard let data = exercisesJSON.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([StrengthExerciseLog].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let str = String(data: data, encoding: .utf8) {
                exercisesJSON = str
            } else {
                exercisesJSON = "[]"
            }
        }
    }
}

@Model
final class ExerciseDefinitionRecord {
    @Attribute(.unique) var id: UUID
    var canonicalKey: String = ""
    var name: String
    var aliasesJSON: String
    var primaryMuscleGroup: String
    var secondaryMuscleGroupsJSON: String
    var equipment: String
    var movementPattern: String
    var isCustom: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        canonicalKey: String = "",
        name: String,
        aliases: [String] = [],
        primaryMuscleGroup: String,
        secondaryMuscleGroups: [String] = [],
        equipment: String,
        movementPattern: String,
        isCustom: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.canonicalKey = canonicalKey.isEmpty ? name.toCanonicalKey() : canonicalKey
        self.name = name
        self.aliasesJSON = Self.encode(aliases)
        self.primaryMuscleGroup = primaryMuscleGroup
        self.secondaryMuscleGroupsJSON = Self.encode(secondaryMuscleGroups)
        self.equipment = equipment
        self.movementPattern = movementPattern
        self.isCustom = isCustom
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var aliases: [String] {
        get { Self.decode(aliasesJSON) }
        set { aliasesJSON = Self.encode(newValue) }
    }

    var secondaryMuscleGroups: [String] {
        get { Self.decode(secondaryMuscleGroupsJSON) }
        set { secondaryMuscleGroupsJSON = Self.encode(newValue) }
    }

    private static func encode(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func decode(_ value: String) -> [String] {
        guard let data = value.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}

struct WorkoutTemplateExercise: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var exerciseDefinitionId: UUID?
    var exerciseCanonicalKey: String?
    var name: String
    var targetSets: Int
    var targetReps: String
    var targetRPE: Double?
    var restSeconds: Int
    var notes: String?
}

enum StrengthWorkoutTemplateParser {
    static func reps(from targetReps: String, fallback: Int = 10) -> Int {
        let trimmed = targetReps.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = Int(trimmed) { return exact }

        let normalized = trimmed.replacingOccurrences(of: " ", with: "").lowercased()
        if let range = normalized.range(of: #"(?<=x)\d+"#, options: .regularExpression) {
            return Int(normalized[range]) ?? fallback
        }
        if let range = normalized.range(of: #"\d+"#, options: .regularExpression) {
            return Int(normalized[range]) ?? fallback
        }
        return fallback
    }
}

enum StrengthWorkoutSaveValidator {
    enum ValidationError: Error, Equatable {
        case emptyCompletedSets
    }

    static func exercisesToSave(
        from exercises: [StrengthExerciseLog],
        ignoringUncompletedSets: Bool
    ) -> Result<[StrengthExerciseLog], ValidationError> {
        let namedExercises = exercises.filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let exercisesToSave: [StrengthExerciseLog]
        if ignoringUncompletedSets {
            exercisesToSave = namedExercises.compactMap { exercise in
                var copy = exercise
                copy.sets = exercise.sets.filter { $0.isCompleted == true }
                return copy.sets.isEmpty ? nil : copy
            }
        } else {
            exercisesToSave = namedExercises
        }

        guard exercisesToSave.contains(where: { !$0.sets.isEmpty }) else {
            return .failure(.emptyCompletedSets)
        }
        return .success(exercisesToSave)
    }
}

@Model
final class WorkoutTemplateRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var goal: String
    var notes: String
    var exercisesJSON: String
    var estimatedDurationMinutes: Int
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        goal: String = "",
        notes: String = "",
        exercises: [WorkoutTemplateExercise],
        estimatedDurationMinutes: Int = 60,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.goal = goal
        self.notes = notes
        self.exercisesJSON = Self.encode(exercises)
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
    }

    var exercises: [WorkoutTemplateExercise] {
        get {
            guard let data = exercisesJSON.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([WorkoutTemplateExercise].self, from: data)) ?? []
        }
        set { exercisesJSON = Self.encode(newValue) }
    }

    private static func encode(_ values: [WorkoutTemplateExercise]) -> String {
        guard let data = try? JSONEncoder().encode(values) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}

@Model
final class TrainingResponseRecord {
    @Attribute(.unique) var id: UUID
    var workoutId: UUID
    var date: Date
    var nextDayDate: Date
    var primaryMuscleGroupsJSON: String
    var totalEffectiveSets: Int
    var totalVolumeKg: Double
    var sessionRPE: Double?
    var nextDayRecoveryDelta: Double?
    var nextDayHRVDelta: Double?
    var nextDayRHRDelta: Double?
    var nextDaySleepScore: Double?
    var subjectiveTagsJSON: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        workoutId: UUID,
        date: Date,
        nextDayDate: Date,
        primaryMuscleGroups: [String],
        totalEffectiveSets: Int,
        totalVolumeKg: Double,
        sessionRPE: Double? = nil,
        nextDayRecoveryDelta: Double? = nil,
        nextDayHRVDelta: Double? = nil,
        nextDayRHRDelta: Double? = nil,
        nextDaySleepScore: Double? = nil,
        subjectiveTags: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.workoutId = workoutId
        self.date = date
        self.nextDayDate = nextDayDate
        self.primaryMuscleGroupsJSON = Self.encode(primaryMuscleGroups)
        self.totalEffectiveSets = totalEffectiveSets
        self.totalVolumeKg = totalVolumeKg
        self.sessionRPE = sessionRPE
        self.nextDayRecoveryDelta = nextDayRecoveryDelta
        self.nextDayHRVDelta = nextDayHRVDelta
        self.nextDayRHRDelta = nextDayRHRDelta
        self.nextDaySleepScore = nextDaySleepScore
        self.subjectiveTagsJSON = Self.encode(subjectiveTags)
        self.createdAt = createdAt
    }

    var primaryMuscleGroups: [String] {
        get { Self.decode(primaryMuscleGroupsJSON) }
        set { primaryMuscleGroupsJSON = Self.encode(newValue) }
    }

    var subjectiveTags: [String] {
        get { Self.decode(subjectiveTagsJSON) }
        set { subjectiveTagsJSON = Self.encode(newValue) }
    }

    private static func encode(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func decode(_ value: String) -> [String] {
        guard let data = value.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}

@Model
final class SleepSummaryRecord {
    @Attribute(.unique) var dayIdentifier: String
    var date: Date
    var totalSleepMinutes: Int
    var bedtime: Date?
    var wakeTime: Date?
    var deepMinutes: Int?
    var remMinutes: Int?
    var coreMinutes: Int?
    var awakeMinutes: Int?
    var sleepScore: Double?
    var updatedAt: Date

    init(summary: SleepSummary, calendar: Calendar = .current, updatedAt: Date = Date()) {
        let day = calendar.startOfDay(for: summary.date)
        dayIdentifier = DailyHealthSummaryRecord.dayIdentifier(for: day, calendar: calendar)
        date = day
        totalSleepMinutes = summary.totalSleepMinutes
        bedtime = summary.bedtime
        wakeTime = summary.wakeTime
        deepMinutes = summary.stageMinutes[.deep]
        remMinutes = summary.stageMinutes[.rem]
        coreMinutes = summary.stageMinutes[.core]
        awakeMinutes = summary.stageMinutes[.awake]
        sleepScore = summary.sleepScore
        self.updatedAt = updatedAt
    }
}

@Model
final class JournalEntryRecord {
    var createdAt: Date
    var serializedTags: String
    var note: String
    var value: Double?
    var unit: String?

    init(createdAt: Date = Date(), tags: [String], note: String, value: Double? = nil, unit: String? = nil) {
        self.createdAt = createdAt
        serializedTags = tags.joined(separator: ",")
        self.note = note
        self.value = value
        self.unit = unit
    }

    var tags: [String] {
        get {
            serializedTags
                .split(separator: ",")
                .map(String.init)
                .filter { !$0.isEmpty }
        }
        set {
            serializedTags = newValue.joined(separator: ",")
        }
    }

    /// Predefined tag categories for common habit/behavior tracking.
    /// Both Chinese and English labels are provided for bilingual support.
    static let tagCategories: [String: [String]] = [
        "caffeine":     ["caffeine", "咖啡因"],
        "alcohol":      ["alcohol", "酒精"],
        "late_meal":    ["late_meal", "夜宵"],
        "heavy_meal":   ["heavy_meal", "大餐"],
        "exercise":     ["exercise", "锻炼"],
        "stressed":     ["stressed", "压力大"],
        "meditation":   ["meditation", "冥想"],
        "hydration":    ["hydration", "补水"],
        "supplements":  ["supplements", "补剂"],
        "sick":         ["sick", "生病"],
        "travel":       ["travel", "旅行"],
        "menstruation": ["menstruation", "月经"],
        "sunlight":     ["sunlight", "阳光"],
        "mindfulness":  ["mindfulness", "正念"],
        "recovery":     ["recovery", "恢复"],
        "sleep":        ["sleep", "睡眠"],
        "training":     ["training", "训练"],
        "stress":       ["stress", "压力"],
        "mood":         ["mood", "情绪"],
        "supplement":   ["supplement", "补剂"],
    ]

    /// All known tags (flattened from tagCategories).
    static var allKnownTags: [String] {
        tagCategories.values.flatMap { $0 }
    }
}

@Model
final class CoachInteractionRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var userText: String
    var assistantText: String
    var focus: String
    var contextHash: String?
    var sessionId: UUID?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        userText: String,
        assistantText: String,
        focus: String,
        contextHash: String? = nil,
        sessionId: UUID? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.userText = userText
        self.assistantText = assistantText
        self.focus = focus
        self.contextHash = contextHash
        self.sessionId = sessionId
    }
}

@Model
final class DailyOperatingPlanRecord {
    @Attribute(.unique) var dayIdentifier: String
    var bodyStateHash: String
    var generatedAt: Date
    var primaryActionType: String
    var title: String
    var payloadJSON: String
    var reasonsJSON: String
    var confidence: Double
    var status: String
    var source: String?
    var safetyNotice: String?

    init(
        dayIdentifier: String,
        bodyStateHash: String,
        generatedAt: Date = Date(),
        primaryActionType: String,
        title: String,
        payloadJSON: String,
        reasonsJSON: String,
        confidence: Double,
        status: String = "proposed",
        source: String? = "BodyStateKernel + TrainingDecisionKernel",
        safetyNotice: String? = "General wellness guidance only; not a medical diagnosis."
    ) {
        self.dayIdentifier = dayIdentifier
        self.bodyStateHash = bodyStateHash
        self.generatedAt = generatedAt
        self.primaryActionType = primaryActionType
        self.title = title
        self.payloadJSON = payloadJSON
        self.reasonsJSON = reasonsJSON
        self.confidence = min(1, max(0, confidence))
        self.status = status
        self.source = source
        self.safetyNotice = safetyNotice
    }
}

/// User-observed outcome of a daily operating plan. Kept separate from the
/// generated plan so recommendations remain auditable while feedback evolves.
@Model
final class DailyDecisionFeedbackRecord {
    @Attribute(.unique) var dayIdentifier: String
    var planGeneratedAt: Date?
    var bodyStateHash: String
    var decisionType: String
    var decisionTitle: String
    var viewedAt: Date?
    var actionStartedAt: Date?
    var actionDestination: String?
    var adoptionStatus: String?
    var accuracyRating: String?
    var actualAction: String?
    var energyRating: Int?
    var fatigueRating: Int?
    var painRating: Int?
    var satisfactionRating: Int?
    var note: String
    var linkedWorkoutId: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        dayIdentifier: String,
        planGeneratedAt: Date? = nil,
        bodyStateHash: String,
        decisionType: String,
        decisionTitle: String,
        viewedAt: Date? = nil,
        actionStartedAt: Date? = nil,
        actionDestination: String? = nil,
        adoptionStatus: String? = nil,
        accuracyRating: String? = nil,
        actualAction: String? = nil,
        energyRating: Int? = nil,
        fatigueRating: Int? = nil,
        painRating: Int? = nil,
        satisfactionRating: Int? = nil,
        note: String = "",
        linkedWorkoutId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.dayIdentifier = dayIdentifier
        self.planGeneratedAt = planGeneratedAt
        self.bodyStateHash = bodyStateHash
        self.decisionType = decisionType
        self.decisionTitle = decisionTitle
        self.viewedAt = viewedAt
        self.actionStartedAt = actionStartedAt
        self.actionDestination = actionDestination
        self.adoptionStatus = adoptionStatus
        self.accuracyRating = accuracyRating
        self.actualAction = actualAction
        self.energyRating = energyRating
        self.fatigueRating = fatigueRating
        self.painRating = painRating
        self.satisfactionRating = satisfactionRating
        self.note = note
        self.linkedWorkoutId = linkedWorkoutId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isCompleted: Bool {
        adoptionStatus != nil && accuracyRating != nil && actualAction != nil
    }
}

@Model
final class PersonalExperimentRecord {
    @Attribute(.unique) var id: UUID
    var templateID: String
    var title: String
    var hypothesis: String
    var protocolText: String
    var targetBehaviorTag: String
    var primaryOutcome: String
    var startDate: Date
    var endDate: Date
    var baselineDays: Int
    var status: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(), templateID: String, title: String,
        hypothesis: String, protocolText: String, targetBehaviorTag: String,
        primaryOutcome: String = "sleep_score", startDate: Date, endDate: Date,
        baselineDays: Int = 7, status: String = "active",
        createdAt: Date = Date(), updatedAt: Date = Date()
    ) {
        self.id = id
        self.templateID = templateID
        self.title = title
        self.hypothesis = hypothesis
        self.protocolText = protocolText
        self.targetBehaviorTag = targetBehaviorTag
        self.primaryOutcome = primaryOutcome
        self.startDate = startDate
        self.endDate = endDate
        self.baselineDays = baselineDays
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class ExperimentCheckInRecord {
    @Attribute(.unique) var id: String
    var experimentID: UUID
    var dayIdentifier: String
    var date: Date
    var followedProtocol: Bool
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(
        experimentID: UUID, dayIdentifier: String, date: Date,
        followedProtocol: Bool, note: String = "",
        createdAt: Date = Date(), updatedAt: Date = Date()
    ) {
        self.id = "\(experimentID.uuidString):\(dayIdentifier)"
        self.experimentID = experimentID
        self.dayIdentifier = dayIdentifier
        self.date = date
        self.followedProtocol = followedProtocol
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class AgentArtifactRecord {
    @Attribute(.unique) var id: UUID
    var type: String
    var title: String
    var createdAt: Date
    var payloadJSON: String
    var sourceContextHash: String
    var status: String
    var confidence: Double
    var source: String
    var safetyNotice: String?

    init(
        id: UUID = UUID(),
        type: String,
        title: String,
        createdAt: Date = Date(),
        payloadJSON: String,
        sourceContextHash: String,
        status: String = "active",
        confidence: Double,
        source: String,
        safetyNotice: String? = "General wellness guidance only; not a medical diagnosis."
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.createdAt = createdAt
        self.payloadJSON = payloadJSON
        self.sourceContextHash = sourceContextHash
        self.status = status
        self.confidence = min(1, max(0, confidence))
        self.source = source
        self.safetyNotice = safetyNotice
    }
}

enum AgentArtifactType: String, Codable, CaseIterable {
    case dailyPlan = "daily_plan"
    case trainingAdjustment = "training_adjustment"
    case weeklyReport = "weekly_report"
    case correlationChart = "correlation_chart"
    case wikiDiff = "wiki_diff"
    case nutritionFeedback = "nutrition_feedback"
}

@Model
final class AIReportRecord {
    var createdAt: Date
    var type: String
    var title: String
    var markdownContent: String
    var serializedContextSnapshot: String
    var serializedTags: String

    init(
        createdAt: Date = Date(),
        type: String,
        title: String,
        markdownContent: String,
        serializedContextSnapshot: String,
        tags: [String] = []
    ) {
        self.createdAt = createdAt
        self.type = type
        self.title = title
        self.markdownContent = markdownContent
        self.serializedContextSnapshot = serializedContextSnapshot
        serializedTags = tags.joined(separator: ",")
    }
}

@Model
final class UserWikiDocumentRecord {
    @Attribute(.unique) var filename: String
    var title: String
    var markdownContent: String
    var updatedAt: Date

    init(filename: String, title: String, markdownContent: String, updatedAt: Date = Date()) {
        self.filename = filename
        self.title = title
        self.markdownContent = markdownContent
        self.updatedAt = updatedAt
    }
}

@Model
final class CoachSessionRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var serializedMessages: String
    var isArchived: Bool
    
    init(
        id: UUID = UUID(),
        title: String = "新对话",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        serializedMessages: String = "[]",
        isArchived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.serializedMessages = serializedMessages
        self.isArchived = isArchived
    }
}

struct UserGoalProfile: Codable, Hashable {
    var primaryGoal: String
    var secondaryGoals: [String]
    var experienceLevel: String
    var bodyConcerns: [String]

    init(
        primaryGoal: String = "maintain",
        secondaryGoals: [String] = [],
        experienceLevel: String = "unknown",
        bodyConcerns: [String] = []
    ) {
        self.primaryGoal = primaryGoal
        self.secondaryGoals = secondaryGoals
        self.experienceLevel = experienceLevel
        self.bodyConcerns = bodyConcerns
    }
}

struct TrainingPreferenceProfile: Codable, Hashable, Sendable {
    var trainingStyle: String
    var weeklyTrainingDays: Int
    var sessionDurationMinutes: Int
    var preferredTrainingDays: [String]
    /// Lightweight split context for people who execute with Apple Watch rather
    /// than a set-by-set phone logger. Optional keeps older profile JSON decodable.
    var rotationFocuses: [String]?
    var nextRotationFocus: String?

    init(
        trainingStyle: String = "mixed",
        weeklyTrainingDays: Int = 3,
        sessionDurationMinutes: Int = 45,
        preferredTrainingDays: [String] = [],
        rotationFocuses: [String]? = nil,
        nextRotationFocus: String? = nil
    ) {
        self.trainingStyle = trainingStyle
        self.weeklyTrainingDays = weeklyTrainingDays
        self.sessionDurationMinutes = sessionDurationMinutes
        self.preferredTrainingDays = preferredTrainingDays
        self.rotationFocuses = rotationFocuses
        self.nextRotationFocus = nextRotationFocus
    }
}

struct EquipmentProfile: Codable, Hashable {
    var equipment: [String]
    var scheduleNotes: String

    init(equipment: [String] = [], scheduleNotes: String = "") {
        self.equipment = equipment
        self.scheduleNotes = scheduleNotes
    }
}

struct CoachingPreference: Codable, Hashable {
    var style: String
    var explanationDepth: String
    var language: String

    init(style: String = "explanatory", explanationDepth: String = "balanced", language: String = "zh-Hans") {
        self.style = style
        self.explanationDepth = explanationDepth
        self.language = language
    }
}

struct InitialBodySnapshot: Codable, Hashable {
    var sleepScore: Double?
    var recoveryScore: Double?
    var strainScore: Double?
    var dataConfidence: DataConfidence
    var missingData: [String]
    var generatedAt: Date

    init(
        sleepScore: Double? = nil,
        recoveryScore: Double? = nil,
        strainScore: Double? = nil,
        dataConfidence: DataConfidence = .unavailable,
        missingData: [String] = [],
        generatedAt: Date = Date()
    ) {
        self.sleepScore = sleepScore
        self.recoveryScore = recoveryScore
        self.strainScore = strainScore
        self.dataConfidence = dataConfidence
        self.missingData = missingData
        self.generatedAt = generatedAt
    }
}

@Model
final class OnboardingState {
    @Attribute(.unique) var id: UUID
    var currentStep: String
    var isCompleted: Bool
    var completedAt: Date?
    var goalProfileJSON: String
    var trainingPreferenceJSON: String
    var equipmentProfileJSON: String
    var coachingPreferenceJSON: String
    var initialBodySnapshotJSON: String
    var missingDataJSON: String
    var firstBrief: String
    var firstActionPlanJSON: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        currentStep: String = "welcome",
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        goalProfile: UserGoalProfile = UserGoalProfile(),
        trainingPreference: TrainingPreferenceProfile = TrainingPreferenceProfile(),
        equipmentProfile: EquipmentProfile = EquipmentProfile(),
        coachingPreference: CoachingPreference = CoachingPreference(),
        initialBodySnapshot: InitialBodySnapshot = InitialBodySnapshot(),
        missingData: [String] = [],
        firstBrief: String = "",
        firstActionPlan: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.currentStep = currentStep
        self.isCompleted = isCompleted
        self.completedAt = completedAt ?? (isCompleted ? updatedAt : nil)
        self.goalProfileJSON = Self.encode(goalProfile)
        self.trainingPreferenceJSON = Self.encode(trainingPreference)
        self.equipmentProfileJSON = Self.encode(equipmentProfile)
        self.coachingPreferenceJSON = Self.encode(coachingPreference)
        self.initialBodySnapshotJSON = Self.encode(initialBodySnapshot)
        self.missingDataJSON = Self.encode(missingData)
        self.firstBrief = firstBrief
        self.firstActionPlanJSON = Self.encode(firstActionPlan)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    @Transient
    var goalProfile: UserGoalProfile {
        get { Self.decode(goalProfileJSON, fallback: UserGoalProfile()) }
        set { goalProfileJSON = Self.encode(newValue); updatedAt = Date() }
    }

    @Transient
    var trainingPreference: TrainingPreferenceProfile {
        get { Self.decode(trainingPreferenceJSON, fallback: TrainingPreferenceProfile()) }
        set { trainingPreferenceJSON = Self.encode(newValue); updatedAt = Date() }
    }

    @Transient
    var equipmentProfile: EquipmentProfile {
        get { Self.decode(equipmentProfileJSON, fallback: EquipmentProfile()) }
        set { equipmentProfileJSON = Self.encode(newValue); updatedAt = Date() }
    }

    @Transient
    var coachingPreference: CoachingPreference {
        get { Self.decode(coachingPreferenceJSON, fallback: CoachingPreference()) }
        set { coachingPreferenceJSON = Self.encode(newValue); updatedAt = Date() }
    }

    @Transient
    var initialBodySnapshot: InitialBodySnapshot {
        get { Self.decode(initialBodySnapshotJSON, fallback: InitialBodySnapshot()) }
        set { initialBodySnapshotJSON = Self.encode(newValue); updatedAt = Date() }
    }

    @Transient
    var missingData: [String] {
        get { Self.decode(missingDataJSON, fallback: []) }
        set { missingDataJSON = Self.encode(newValue); updatedAt = Date() }
    }

    @Transient
    var firstActionPlan: [String] {
        get { Self.decode(firstActionPlanJSON, fallback: []) }
        set { firstActionPlanJSON = Self.encode(newValue); updatedAt = Date() }
    }

    private static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func decode<T: Decodable>(_ json: String, fallback: T) -> T {
        guard let data = json.data(using: .utf8) else { return fallback }
        return (try? JSONDecoder().decode(T.self, from: data)) ?? fallback
    }
}

@Model
final class CoachArtifactRecord {
    @Attribute(.unique) var id: UUID
    var type: String
    var title: String
    var summary: String
    var createdAt: Date
    var relatedDate: Date?
    var decision: String?
    var confidence: Double
    var reasonsJSON: String
    var actionsJSON: String
    var sourceContextHash: String
    var userFeedback: String?
    var status: String
    var followUpQuestion: String?

    init(artifact: CoachArtifact) {
        self.id = artifact.id
        self.type = artifact.type.rawValue
        self.title = artifact.title
        self.summary = artifact.summary
        self.createdAt = artifact.createdAt
        self.relatedDate = artifact.relatedDate
        self.decision = artifact.decision
        self.confidence = artifact.confidence
        self.reasonsJSON = Self.encode(artifact.reasons)
        self.actionsJSON = Self.encode(artifact.actions)
        self.sourceContextHash = artifact.sourceContextHash
        self.userFeedback = artifact.userFeedback
        self.status = artifact.status.rawValue
        self.followUpQuestion = artifact.followUpQuestion
    }

    @Transient
    var artifact: CoachArtifact {
        get {
            CoachArtifact(
                id: id,
                type: CoachArtifactType(rawValue: type) ?? .askCoachAnswer,
                title: title,
                summary: summary,
                createdAt: createdAt,
                relatedDate: relatedDate,
                decision: decision,
                confidence: confidence,
                reasons: Self.decode(reasonsJSON, fallback: []),
                actions: Self.decode(actionsJSON, fallback: []),
                sourceContextHash: sourceContextHash,
                userFeedback: userFeedback,
                status: CoachArtifactStatus(rawValue: status) ?? .created,
                followUpQuestion: followUpQuestion
            )
        }
        set {
            id = newValue.id
            type = newValue.type.rawValue
            title = newValue.title
            summary = newValue.summary
            createdAt = newValue.createdAt
            relatedDate = newValue.relatedDate
            decision = newValue.decision
            confidence = newValue.confidence
            reasonsJSON = Self.encode(newValue.reasons)
            actionsJSON = Self.encode(newValue.actions)
            sourceContextHash = newValue.sourceContextHash
            userFeedback = newValue.userFeedback
            status = newValue.status.rawValue
            followUpQuestion = newValue.followUpQuestion
        }
    }

    private static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func decode<T: Decodable>(_ json: String, fallback: T) -> T {
        guard let data = json.data(using: .utf8) else { return fallback }
        return (try? JSONDecoder().decode(T.self, from: data)) ?? fallback
    }
}

enum PersistenceSchemaVersion {
    static let current = "v0.1"
}

enum FoodLogSource: String, Codable, CaseIterable {
    case photoAnalysis = "photo_analysis"
    case barcodeLookup = "barcode_lookup"
    case manual
    case coachTool = "coach_tool"
}

struct FoodLogItem: Codable, Hashable, Sendable {
    var name: String
    var portion: String
    var calories: Int

    init(name: String, portion: String, calories: Int) {
        self.name = name
        self.portion = portion
        self.calories = calories
    }
}

@Model
final class FoodLogRecord {
    @Attribute(.unique) var id: UUID
    var mealName: String
    var createdAt: Date
    var updatedAt: Date
    var source: String
    var totalCalories: Int
    var proteinGrams: Int
    var carbsGrams: Int
    var fatGrams: Int
    var fiberGrams: Int
    var healthScore: String
    var rawAnalysis: String
    var serializedFoods: String
    var serializedSuggestions: String

    @Transient
    var foods: [FoodLogItem] {
        get {
            guard let data = serializedFoods.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([FoodLogItem].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let value = String(data: data, encoding: .utf8) {
                serializedFoods = value
            } else {
                serializedFoods = "[]"
            }
        }
    }

    @Transient
    var suggestions: [String] {
        get {
            guard let data = serializedSuggestions.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let value = String(data: data, encoding: .utf8) {
                serializedSuggestions = value
            } else {
                serializedSuggestions = "[]"
            }
        }
    }

    var summaryLine: String {
        let names = foods.map(\.name).joined(separator: ", ")
        let foodText = names.isEmpty ? mealName : names
        return "\(mealName): \(foodText) · \(totalCalories) kcal · P\(proteinGrams) C\(carbsGrams) F\(fatGrams)"
    }

    @Transient
    var micronutrients: [NutritionMicronutrientAmount] {
        NutritionAnalysisArchiveCodec.micronutrients(from: rawAnalysis)
    }

    init(
        id: UUID = UUID(),
        mealName: String,
        foods: [FoodLogItem],
        totalCalories: Int,
        proteinGrams: Int,
        carbsGrams: Int,
        fatGrams: Int,
        fiberGrams: Int,
        healthScore: String,
        suggestions: [String] = [],
        source: FoodLogSource,
        rawAnalysis: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.mealName = mealName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.source = source.rawValue
        self.totalCalories = totalCalories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
        self.healthScore = healthScore
        self.rawAnalysis = rawAnalysis
        self.serializedFoods = "[]"
        self.serializedSuggestions = "[]"
        self.foods = foods
        self.suggestions = suggestions
    }

    convenience init(
        analysis: FoodAnalysisResult,
        mealName: String,
        source: FoodLogSource,
        createdAt: Date = Date()
    ) {
        self.init(
            mealName: mealName,
            foods: analysis.foods.map {
                FoodLogItem(name: $0.name, portion: $0.portion, calories: $0.calories)
            },
            totalCalories: analysis.totalCalories,
            proteinGrams: analysis.macros.protein,
            carbsGrams: analysis.macros.carbs,
            fatGrams: analysis.macros.fat,
            fiberGrams: analysis.macros.fiber,
            healthScore: analysis.healthScore,
            suggestions: analysis.suggestions,
            source: source,
            rawAnalysis: NutritionAnalysisArchiveCodec.encode(
                original: analysis.rawAnalysis,
                micronutrients: analysis.micronutrients
            ),
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }
}

public struct TrainingDay: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var weekNumber: Int      // 1-indexed
    public var dayNumber: Int       // 1-7 (1 = Monday, 7 = Sunday)
    public var title: String        // e.g. "Cardio Endurance"
    public var description: String  // e.g. "Run for 45 minutes in HR Zone 2."
    public var focus: String        // "cardio" | "strength" | "flexibility" | "rest"
    public var durationMinutes: Int
    public var intensity: String    // "low" | "moderate" | "high"
    public var isCompleted: Bool
    public var completedAt: Date?
    public var loggedStrain: Double?
    
    // Closed-loop training additions
    public var linkedWorkoutEventIds: [UUID]
    public var plannedExercisesJSON: String
    public var actualSummaryJSON: String
    public var adherenceScore: Double?

    public init(
        id: UUID = UUID(),
        weekNumber: Int,
        dayNumber: Int,
        title: String,
        description: String,
        focus: String,
        durationMinutes: Int,
        intensity: String,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        loggedStrain: Double? = nil,
        linkedWorkoutEventIds: [UUID] = [],
        plannedExercisesJSON: String = "[]",
        actualSummaryJSON: String = "{}",
        adherenceScore: Double? = nil
    ) {
        self.id = id
        self.weekNumber = weekNumber
        self.dayNumber = dayNumber
        self.title = title
        self.description = description
        self.focus = focus
        self.durationMinutes = durationMinutes
        self.intensity = intensity
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.loggedStrain = loggedStrain
        self.linkedWorkoutEventIds = linkedWorkoutEventIds
        self.plannedExercisesJSON = plannedExercisesJSON
        self.actualSummaryJSON = actualSummaryJSON
        self.adherenceScore = adherenceScore
    }

    enum CodingKeys: String, CodingKey {
        case id, weekNumber, dayNumber, title, description, focus, durationMinutes, intensity
        case isCompleted, completedAt, loggedStrain, linkedWorkoutEventIds
        case plannedExercisesJSON, actualSummaryJSON, adherenceScore
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        weekNumber = try container.decodeIfPresent(Int.self, forKey: .weekNumber) ?? 1
        dayNumber = try container.decodeIfPresent(Int.self, forKey: .dayNumber) ?? 1
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        focus = try container.decodeIfPresent(String.self, forKey: .focus) ?? "strength"
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 0
        intensity = try container.decodeIfPresent(String.self, forKey: .intensity) ?? "moderate"
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        loggedStrain = try container.decodeIfPresent(Double.self, forKey: .loggedStrain)
        linkedWorkoutEventIds = try container.decodeIfPresent([UUID].self, forKey: .linkedWorkoutEventIds) ?? []
        plannedExercisesJSON = try container.decodeIfPresent(String.self, forKey: .plannedExercisesJSON) ?? "[]"
        actualSummaryJSON = try container.decodeIfPresent(String.self, forKey: .actualSummaryJSON) ?? "{}"
        adherenceScore = try container.decodeIfPresent(Double.self, forKey: .adherenceScore)
    }
}

@Model
public final class TrainingPlanRecord {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var goalDescription: String
    public var startDate: Date
    public var weeksCount: Int
    public var isActive: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var serializedDays: String
    public var idempotencyKey: String?

    @Transient
    public var days: [TrainingDay] {
        get {
            guard let data = serializedDays.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([TrainingDay].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let str = String(data: data, encoding: .utf8) {
                serializedDays = str
            } else {
                serializedDays = "[]"
            }
        }
    }

    public init(
        id: UUID = UUID(),
        title: String,
        goalDescription: String,
        startDate: Date = Date(),
        weeksCount: Int = 4,
        isActive: Bool = true,
        days: [TrainingDay] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.goalDescription = goalDescription
        self.startDate = startDate
        self.weeksCount = weeksCount
        self.isActive = isActive
        self.serializedDays = "[]"
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.days = days
    }
}

@Model
public final class BiomarkerRecord {
    @Attribute(.unique) public var id: UUID
    public var name: String          // e.g., "Vitamin D", "Cortisol", "Ferritin", "Cholesterol"
    public var value: Double
    public var unit: String           // e.g., "ng/mL", "mcg/dL", "mg/dL"
    public var date: Date
    public var isOptimal: Bool
    public var referenceMin: Double
    public var referenceMax: Double
    public var sourceDocumentName: String? // Linked document name if OCR-extracted

    public init(
        id: UUID = UUID(),
        name: String,
        value: Double,
        unit: String,
        date: Date = Date(),
        isOptimal: Bool = true,
        referenceMin: Double,
        referenceMax: Double,
        sourceDocumentName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.unit = unit
        self.date = date
        self.isOptimal = isOptimal
        self.referenceMin = referenceMin
        self.referenceMax = referenceMax
        self.sourceDocumentName = sourceDocumentName
    }
}

@Model
public final class WorkoutEventRecord {
    @Attribute(.unique) public var id: UUID
    public var source: String // "healthKit" | "manual" | "strengthLog"
    public var startedAt: Date
    public var endedAt: Date
    public var dayIdentifier: String = ""
    public var activityType: String
    public var title: String = ""
    public var durationMinutes: Double = 0
    public var energyKilocalories: Double?
    public var averageHeartRate: Double?
    public var rpe: Double?
    public var linkedStrengthWorkoutId: UUID?
    public var linkedHealthKitWorkoutId: UUID?
    public var linkedTrainingPlanDayId: UUID?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(
        id: UUID = UUID(),
        source: String,
        startedAt: Date,
        endedAt: Date,
        activityType: String,
        title: String? = nil,
        energyKilocalories: Double? = nil,
        averageHeartRate: Double? = nil,
        rpe: Double? = nil,
        linkedStrengthWorkoutId: UUID? = nil,
        linkedHealthKitWorkoutId: UUID? = nil,
        linkedTrainingPlanDayId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.id = id
        self.source = source
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.dayIdentifier = DailyHealthSummaryRecord.healthDayIdentifier(
            forSampleAt: startedAt,
            calendar: calendar
        )
        self.activityType = activityType
        self.title = title ?? activityType
        self.durationMinutes = max(0, endedAt.timeIntervalSince(startedAt) / 60)
        self.energyKilocalories = energyKilocalories
        self.averageHeartRate = averageHeartRate
        self.rpe = rpe
        self.linkedStrengthWorkoutId = linkedStrengthWorkoutId
        self.linkedHealthKitWorkoutId = linkedHealthKitWorkoutId
        self.linkedTrainingPlanDayId = linkedTrainingPlanDayId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class DeletedWorkoutRecord {
    @Attribute(.unique) var id: String
    var deletedAt: Date

    init(id: String, deletedAt: Date = Date()) {
        self.id = id
        self.deletedAt = deletedAt
    }
}

@Model
final class XunjiDailyCacheRecord {
    @Attribute(.unique) var datestr: String
    var fetchedAt: Date
    var includeFullData: Bool
    @Attribute(.externalStorage) var responseData: Data

    init(
        datestr: String,
        fetchedAt: Date = Date(),
        includeFullData: Bool,
        responseData: Data
    ) {
        self.datestr = datestr
        self.fetchedAt = fetchedAt
        self.includeFullData = includeFullData
        self.responseData = responseData
    }
}

@Model
final class XunjiWorkoutMirrorRecord {
    @Attribute(.unique) var externalID: String
    var datestr: String
    var linkedStrengthWorkoutID: UUID?
    var linkedWorkoutEventID: UUID?
    @Attribute(.externalStorage) var rawTrainData: Data
    var lastImportedAt: Date

    init(
        externalID: String,
        datestr: String,
        linkedStrengthWorkoutID: UUID? = nil,
        linkedWorkoutEventID: UUID? = nil,
        rawTrainData: Data,
        lastImportedAt: Date = Date()
    ) {
        self.externalID = externalID
        self.datestr = datestr
        self.linkedStrengthWorkoutID = linkedStrengthWorkoutID
        self.linkedWorkoutEventID = linkedWorkoutEventID
        self.rawTrainData = rawTrainData
        self.lastImportedAt = lastImportedAt
    }
}

enum XunjiCachePolicy {
    static let cooldown: TimeInterval = 90

    static func shouldReuse(
        _ cache: XunjiDailyCacheRecord,
        datestr: String,
        includeFullData: Bool,
        now: Date = Date()
    ) -> Bool {
        guard cache.datestr == datestr else {
            return false
        }

        let age = now.timeIntervalSince(cache.fetchedAt)
        if age >= 0, age < cooldown {
            return true
        }

        return cache.includeFullData || !includeFullData
    }
}

extension String {
    public func toCanonicalKey() -> String {
        let mapping: [String: String] = [
            "杠铃卧推": "barbell_bench_press",
            "哑铃卧推": "dumbbell_bench_press",
            "上斜卧推": "incline_bench_press",
            "双杠臂屈伸": "dips",
            "绳索夹胸": "cable_fly",
            "器械推胸": "chest_press",
            "引体向上": "pull_ups",
            "高位下拉": "lat_pulldown",
            "杠铃划船": "barbell_row",
            "坐姿划船": "seated_row",
            "单臂哑铃划船": "one_arm_dumbbell_row",
            "硬拉": "deadlift",
            "深蹲": "squat",
            "腿举": "leg_press",
            "罗马尼亚硬拉": "romanian_deadlift",
            "腿屈伸": "leg_extension",
            "腿弯举": "leg_curl",
            "保加利亚分腿蹲": "bulgarian_split_squat",
            "臀推": "hip_thrust",
            "推举": "overhead_press",
            "哑铃侧平举": "lateral_raise",
            "俯身飞鸟": "rear_delt_fly",
            "面拉": "face_pull",
            "阿诺德推举": "arnold_press",
            "杠铃弯举": "barbell_curl",
            "哑铃弯举": "dumbbell_curl",
            "绳索下压": "triceps_pushdown",
            "窄距卧推": "close_grip_bench_press",
            "臂屈伸": "triceps_extension",
            "卷腹": "crunch",
            "悬垂举腿": "hanging_leg_raise",
            "平板支撑": "plank",
            "pallof press": "pallof_press"
        ]
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let mapped = mapping[trimmed] {
            return mapped
        }
        for (key, val) in mapping {
            if trimmed.contains(key.lowercased()) {
                return val
            }
        }
        return trimmed
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}

@Model
final class VelaEventRecord {
    @Attribute(.unique) var id: UUID
    var eventType: String
    var timestamp: Date
    var title: String
    var detail: String
    var metadataJSON: String

    init(
        id: UUID = UUID(),
        eventType: String,
        timestamp: Date = Date(),
        title: String,
        detail: String = "",
        metadataJSON: String = "{}"
    ) {
        self.id = id
        self.eventType = eventType
        self.timestamp = timestamp
        self.title = title
        self.detail = detail
        self.metadataJSON = metadataJSON
    }
}

@Model
public final class ProactiveInsightRecord {
    @Attribute(.unique) public var id: UUID
    public var date: Date
    public var focusRaw: String
    public var severityRaw: String
    public var title: String
    public var bodyText: String
    public var suggestedAction: String?
    public var priority: Int
    public var coachPresetQuestion: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        focusRaw: String,
        severityRaw: String,
        title: String,
        bodyText: String,
        suggestedAction: String? = nil,
        priority: Int = 50,
        coachPresetQuestion: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.focusRaw = focusRaw
        self.severityRaw = severityRaw
        self.title = title
        self.bodyText = bodyText
        self.suggestedAction = suggestedAction
        self.priority = priority
        self.coachPresetQuestion = coachPresetQuestion
        self.createdAt = createdAt
    }
}

extension ProactiveInsightRecord {
    var toInsight: ProactiveInsight {
        let focusVal: ProactiveInsight.Focus
        switch focusRaw {
        case "recovery": focusVal = .recovery
        case "sleep": focusVal = .sleep
        case "training", "strain", "adaptation": focusVal = .training
        case "stress": focusVal = .stress
        case "energy": focusVal = .energy
        case "movement": focusVal = .movement
        default: focusVal = .readiness
        }

        let sevVal: ProactiveInsight.Severity
        switch severityRaw {
        case "alert": sevVal = .alert
        case "warning": sevVal = .warning
        case "positive": sevVal = .info
        default: sevVal = .info
        }

        return ProactiveInsight(
            focus: focusVal,
            severity: sevVal,
            title: title,
            body: bodyText,
            suggestedAction: suggestedAction,
            relatedMetrics: [],
            evidence: [],
            priority: priority,
            coachPresetQuestion: coachPresetQuestion
        )
    }
}

// MARK: - Kernel Input Value DTOs (Sendable)
//
// The training kernels (BodyStateKernel / TrainingDecisionKernel / TrainingScheduleResolver)
// and TrainingAnalyticsService previously read SwiftData @Model classes directly, which forced
// the heavy secondary-data computation to stay on the main actor. These plain value-type DTOs
// carry exactly the fields the kernels read, are Sendable, and let the same pure computation
// run off the main thread. Conversion (dto) is cheap and must run on the main actor where the
// model object lives; the kernels then operate only on the immutable value copies.

struct WorkoutEventDTO: Sendable {
    var id: UUID
    var startedAt: Date
    var durationMinutes: Double
    var linkedTrainingPlanDayId: UUID?
    var linkedStrengthWorkoutId: UUID?
}

extension WorkoutEventRecord {
    var dto: WorkoutEventDTO {
        WorkoutEventDTO(
            id: id,
            startedAt: startedAt,
            durationMinutes: durationMinutes,
            linkedTrainingPlanDayId: linkedTrainingPlanDayId,
            linkedStrengthWorkoutId: linkedStrengthWorkoutId
        )
    }
}

struct TrainingResponseDTO: Sendable {
    var id: UUID
    var date: Date
    var workoutId: UUID
    var primaryMuscleGroups: [String]
    var totalEffectiveSets: Int
    var totalVolumeKg: Double
    var sessionRPE: Double?
    var nextDayRecoveryDelta: Double?
    var nextDayHRVDelta: Double?
    var nextDayRHRDelta: Double?
}

extension TrainingResponseRecord {
    var dto: TrainingResponseDTO {
        TrainingResponseDTO(
            id: id,
            date: date,
            workoutId: workoutId,
            primaryMuscleGroups: primaryMuscleGroups,
            totalEffectiveSets: totalEffectiveSets,
            totalVolumeKg: totalVolumeKg,
            sessionRPE: sessionRPE,
            nextDayRecoveryDelta: nextDayRecoveryDelta,
            nextDayHRVDelta: nextDayHRVDelta,
            nextDayRHRDelta: nextDayRHRDelta
        )
    }
}

struct FoodLogDTO: Sendable {
    var id: UUID
    var createdAt: Date
    var totalCalories: Int
    var proteinGrams: Int
    var carbsGrams: Int
    var fatGrams: Int
    var fiberGrams: Int
}

extension FoodLogRecord {
    var dto: FoodLogDTO {
        FoodLogDTO(
            id: id,
            createdAt: createdAt,
            totalCalories: totalCalories,
            proteinGrams: proteinGrams,
            carbsGrams: carbsGrams,
            fatGrams: fatGrams,
            fiberGrams: fiberGrams
        )
    }
}

struct JournalEntryDTO: Sendable {
    var createdAt: Date
    var note: String
    var tags: [String]
    var value: Double?
}

extension JournalEntryRecord {
    var dto: JournalEntryDTO {
        JournalEntryDTO(
            createdAt: createdAt,
            note: note,
            tags: tags,
            value: value
        )
    }
}

struct TrainingPlanDTO: Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var goalDescription: String
    var startDate: Date
    var weeksCount: Int
    var isActive: Bool
    var days: [TrainingDay]
}

extension TrainingPlanRecord {
    var dto: TrainingPlanDTO {
        TrainingPlanDTO(
            id: id,
            title: title,
            goalDescription: goalDescription,
            startDate: startDate,
            weeksCount: weeksCount,
            isActive: isActive,
            days: days
        )
    }
}

struct DailyHealthSummaryDTO: Sendable {
    var dayIdentifier: String
    var date: Date
    var updatedAt: Date
    var recoveryScore: Double?
    var sleepScore: Double?
    var strainScore: Double?
    var stressIndex: Double?
    var currentEnergy: Double?
    var morningEnergy: Double?
    var energyBank: Double?
}

extension DailyHealthSummaryRecord {
    var dto: DailyHealthSummaryDTO {
        DailyHealthSummaryDTO(
            dayIdentifier: dayIdentifier,
            date: date,
            updatedAt: updatedAt,
            recoveryScore: recoveryScore,
            sleepScore: sleepScore,
            strainScore: strainScore,
            stressIndex: stressIndex,
            currentEnergy: currentEnergy,
            morningEnergy: morningEnergy,
            energyBank: energyBank
        )
    }
}

struct StrengthWorkoutDTO: Sendable {
    var id: UUID
    var title: String
    var startedAt: Date
    var durationMinutes: Int
    var endedAt: Date
    var sessionRPE: Double?
    var exercises: [StrengthExerciseLog]

    var exerciseCount: Int { exercises.count }
}

extension StrengthWorkoutRecord {
    var dto: StrengthWorkoutDTO {
        StrengthWorkoutDTO(
            id: id,
            title: title,
            startedAt: startedAt,
            durationMinutes: durationMinutes,
            endedAt: endedAt,
            sessionRPE: sessionRPE,
            exercises: exercises
        )
    }
}
