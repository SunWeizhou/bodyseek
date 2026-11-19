import Foundation

public struct SyncAnchorState: Hashable, Codable, Sendable {
    public let type: String
    public var anchorData: Data?
    public var backfillCursor: DayKey?
    public var updatedAt: Date

    public init(
        type: String,
        anchorData: Data? = nil,
        backfillCursor: DayKey? = nil,
        updatedAt: Date = Date()
    ) {
        self.type = type
        self.anchorData = anchorData
        self.backfillCursor = backfillCursor
        self.updatedAt = updatedAt
    }
}

public enum ObservationStateTag: String, Hashable, Codable, Sendable {
    case available
    case knownZero
    case missing
    case excluded
}

public struct DayMetricRecord: Hashable, Codable, Sendable {
    public let dayKey: DayKey
    public let metric: String
    public let value: Double?
    public let state: ObservationStateTag
    public let reason: String?
    public let coverage: Double
    public let sources: [SourceRef]

    public init(
        dayKey: DayKey,
        metric: String,
        value: Double?,
        state: ObservationStateTag,
        reason: String? = nil,
        coverage: Double = 1.0,
        sources: [SourceRef] = []
    ) {
        self.dayKey = dayKey
        self.metric = metric
        self.value = value
        self.state = state
        self.reason = reason
        self.coverage = min(1.0, max(0.0, coverage))
        self.sources = sources
    }
}

public struct HourlyMetricRecord: Hashable, Codable, Sendable {
    public let hourStart: Date
    public let metric: String
    public let value: Double?
    public let coverage: Double

    public init(hourStart: Date, metric: String, value: Double?, coverage: Double = 1.0) {
        self.hourStart = hourStart
        self.metric = metric
        self.value = value
        self.coverage = min(1.0, max(0.0, coverage))
    }
}

public enum WorkoutReviewState: String, Hashable, Codable, Sendable {
    case unreviewed
    case autoAttributed
    case annotated
    case skipped
}

public struct StoredWorkoutRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: String { hkUUID }
    public let hkUUID: String
    public let type: String
    public let start: Date
    public let end: Date
    public let energy: Double
    public let avgHR: Double?
    public let zones: WorkoutHeartRateZones?
    public let effortUser: Double?
    public let effortEstimated: Double?
    public var reviewState: WorkoutReviewState

    public init(
        hkUUID: String,
        type: String,
        start: Date,
        end: Date,
        energy: Double,
        avgHR: Double? = nil,
        zones: WorkoutHeartRateZones? = nil,
        effortUser: Double? = nil,
        effortEstimated: Double? = nil,
        reviewState: WorkoutReviewState = .unreviewed
    ) {
        self.hkUUID = hkUUID
        self.type = type
        self.start = start
        self.end = end
        self.energy = energy
        self.avgHR = avgHR
        self.zones = zones
        self.effortUser = effortUser
        self.effortEstimated = effortEstimated
        self.reviewState = reviewState
    }
}

public struct WorkoutAnnotationRecord: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let workoutUUID: String
    public let rawText: String
    public let parserVersion: AlgorithmVersion
    public let confirmedAt: Date?

    public init(
        id: UUID = UUID(),
        workoutUUID: String,
        rawText: String,
        parserVersion: AlgorithmVersion = .workoutParserV1,
        confirmedAt: Date? = Date()
    ) {
        self.id = id
        self.workoutUUID = workoutUUID
        self.rawText = rawText
        self.parserVersion = parserVersion
        self.confirmedAt = confirmedAt
    }
}

public enum MuscleLoadRole: String, Hashable, Codable, Sendable {
    case primary
    case secondary
    case stabilizer
}

public struct WorkoutMuscleLoadRecord: Hashable, Codable, Sendable {
    public let workoutUUID: String
    public let muscle: BodyRegionMuscle
    public let role: MuscleLoadRole
    public let load: Double
    public let algorithmVersion: AlgorithmVersion

    public init(
        workoutUUID: String,
        muscle: BodyRegionMuscle,
        role: MuscleLoadRole,
        load: Double,
        algorithmVersion: AlgorithmVersion = .recoveryHeuristicV1
    ) {
        self.workoutUUID = workoutUUID
        self.muscle = muscle
        self.role = role
        self.load = load
        self.algorithmVersion = algorithmVersion
    }
}

public struct ScoreSnapshotRecord: Hashable, Codable, Sendable {
    public let dayKey: DayKey
    public let kind: MetricKind
    public let value: Int?
    public let state: ObservationStateTag
    public let reason: String?
    public let baselineDelta: Int?
    public let algorithmVersion: AlgorithmVersion
    public let computedAt: Date

    public init(
        dayKey: DayKey,
        kind: MetricKind,
        value: Int?,
        state: ObservationStateTag,
        reason: String? = nil,
        baselineDelta: Int? = nil,
        algorithmVersion: AlgorithmVersion = .scoreV2,
        computedAt: Date = Date()
    ) {
        self.dayKey = dayKey
        self.kind = kind
        self.value = value
        self.state = state
        self.reason = reason
        self.baselineDelta = baselineDelta
        self.algorithmVersion = algorithmVersion
        self.computedAt = computedAt
    }
}

public struct MuscleRecoveryRecord: Hashable, Codable, Sendable {
    public let asOf: Date
    public let muscle: BodyRegionMuscle
    public let recovery: Double
    public let algorithmVersion: AlgorithmVersion

    public init(
        asOf: Date,
        muscle: BodyRegionMuscle,
        recovery: Double,
        algorithmVersion: AlgorithmVersion = .recoveryHeuristicV1
    ) {
        self.asOf = asOf
        self.muscle = muscle
        self.recovery = min(1.0, max(0.0, recovery))
        self.algorithmVersion = algorithmVersion
    }
}

public enum PlanItemKind: String, Hashable, Codable, Sendable {
    case trainingFocus
    case sleepWindow
    case recoveryAction
    case experiment
}

public enum PlanItemState: String, Hashable, Codable, Sendable {
    case suggested
    case adopted
    case completed
    case dismissed
}

public struct PlanItemRecord: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let dayKey: DayKey
    public let kind: PlanItemKind
    public let payloadJSON: String
    public var state: PlanItemState
    public let origin: ActionProposal.Origin

    public init(
        id: UUID = UUID(),
        dayKey: DayKey,
        kind: PlanItemKind,
        payloadJSON: String,
        state: PlanItemState = .suggested,
        origin: ActionProposal.Origin = .system
    ) {
        self.id = id
        self.dayKey = dayKey
        self.kind = kind
        self.payloadJSON = payloadJSON
        self.state = state
        self.origin = origin
    }
}

public enum MemoryTier: String, Hashable, Codable, Sendable {
    case profile
    case activeConstraint
    case verifiedPattern
}

public struct TieredMemoryRecord: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let tier: MemoryTier
    public var content: String
    public let scopeJSON: String
    public let confidence: Double
    public let expiresAt: Date?
    public let confirmedAt: Date?
    public var retiredAt: Date?

    public init(
        id: UUID = UUID(),
        tier: MemoryTier,
        content: String,
        scopeJSON: String = "{}",
        confidence: Double = 1.0,
        expiresAt: Date? = nil,
        confirmedAt: Date? = Date(),
        retiredAt: Date? = nil
    ) {
        self.id = id
        self.tier = tier
        self.content = content
        self.scopeJSON = scopeJSON
        self.confidence = min(1.0, max(0.0, confidence))
        self.expiresAt = expiresAt
        self.confirmedAt = confirmedAt
        self.retiredAt = retiredAt
    }

    public func isActive(at now: Date = Date()) -> Bool {
        guard retiredAt == nil else { return false }
        if let expiresAt, expiresAt <= now { return false }
        return true
    }
}

public enum ActionAuditDecision: String, Hashable, Codable, Sendable {
    case applied
    case rejected
    case failed
}

public struct ActionAuditEntry: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let proposalJSON: String
    public let origin: ActionProposal.Origin
    public let decision: ActionAuditDecision
    public let decidedAt: Date
    public let affectedIDs: [String]

    public init(
        id: UUID = UUID(),
        proposalJSON: String,
        origin: ActionProposal.Origin,
        decision: ActionAuditDecision,
        decidedAt: Date = Date(),
        affectedIDs: [String] = []
    ) {
        self.id = id
        self.proposalJSON = proposalJSON
        self.origin = origin
        self.decision = decision
        self.decidedAt = decidedAt
        self.affectedIDs = affectedIDs
    }
}

public enum PatternFindingStatus: String, Hashable, Codable, Sendable {
    case candidate
    case confirmed
    case dismissed
}

public struct PatternFindingRecord: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let statement: String
    public let effect: Double
    public let ciLow: Double
    public let ciHigh: Double
    public let sampleSize: Int
    public let method: String
    public let modelVersion: String
    public var status: PatternFindingStatus

    public init(
        id: UUID = UUID(),
        statement: String,
        effect: Double,
        ciLow: Double,
        ciHigh: Double,
        sampleSize: Int,
        method: String,
        modelVersion: String,
        status: PatternFindingStatus = .candidate
    ) {
        self.id = id
        self.statement = statement
        self.effect = effect
        self.ciLow = ciLow
        self.ciHigh = ciHigh
        self.sampleSize = sampleSize
        self.method = method
        self.modelVersion = modelVersion
        self.status = status
    }
}

// MARK: - Typed ActionProposal Payloads

public struct AnnotateWorkoutPayload: Hashable, Codable, Sendable {
    public let workoutUUID: String
    public let rawText: String
    public let parserVersion: AlgorithmVersion
    public let muscleLoads: [WorkoutMuscleLoadRecord]
    public let reviewState: WorkoutReviewState

    public init(
        workoutUUID: String,
        rawText: String,
        parserVersion: AlgorithmVersion = .workoutParserV1,
        muscleLoads: [WorkoutMuscleLoadRecord] = [],
        reviewState: WorkoutReviewState = .annotated
    ) {
        self.workoutUUID = workoutUUID
        self.rawText = rawText
        self.parserVersion = parserVersion
        self.muscleLoads = muscleLoads
        self.reviewState = reviewState
    }
}

public struct CommitMemoryPayload: Hashable, Codable, Sendable {
    public let memory: TieredMemoryRecord

    public init(memory: TieredMemoryRecord) {
        self.memory = memory
    }
}

public struct RetireMemoryPayload: Hashable, Codable, Sendable {
    public let memoryID: UUID
    public let retiredAt: Date

    public init(memoryID: UUID, retiredAt: Date = Date()) {
        self.memoryID = memoryID
        self.retiredAt = retiredAt
    }
}

public struct AdjustPlanPayload: Hashable, Codable, Sendable {
    public let item: PlanItemRecord

    public init(item: PlanItemRecord) {
        self.item = item
    }
}

public struct RecordCheckInPayload: Hashable, Codable, Sendable {
    public let checkIn: DailyCheckIn

    public init(checkIn: DailyCheckIn) {
        self.checkIn = checkIn
    }
}
