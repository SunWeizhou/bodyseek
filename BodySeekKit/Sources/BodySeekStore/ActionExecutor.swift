import BodySeekCore
import Foundation
import GRDB
import os

/// Single transactional write gate for `ActionProposal` mutations + `action_audit` trail.
public final class ActionExecutor: Sendable {
    public let database: BodySeekDatabase
    private static let logger = Logger(subsystem: "com.sunweizhou.Vela4", category: "ActionExecutor")

    public init(database: BodySeekDatabase) {
        self.database = database
    }

    @discardableResult
    public func execute(_ proposal: ActionProposal, now: Date = Date()) async throws -> ActionAuditEntry {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let proposalData = try encoder.encode(proposal)
        guard let proposalJSON = String(data: proposalData, encoding: .utf8) else {
            throw BodySeekDatabaseError.invalidJSONEncoding(context: "ActionProposal")
        }

        do {
            return try await database.writer.write { db in
                let affectedIDs: [String]
                switch proposal.kind {
                case .annotateWorkout:
                    let payload = try proposal.decodePayload(AnnotateWorkoutPayload.self)
                    let exists = try Int.fetchOne(
                        db,
                        sql: "SELECT COUNT(*) FROM workout WHERE hk_uuid = ?",
                        arguments: [payload.workoutUUID]
                    ) ?? 0
                    guard exists > 0 else {
                        throw BodySeekDatabaseError.foreignKeyTargetMissing(
                            table: "workout",
                            key: payload.workoutUUID
                        )
                    }

                    let annotationID = UUID()
                    try db.execute(
                        sql: """
                        INSERT INTO workout_annotation (id, workout_uuid, raw_text, parser_version, confirmed_at)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                        arguments: [
                            annotationID.uuidString,
                            payload.workoutUUID,
                            payload.rawText,
                            payload.parserVersion.description,
                            now.timeIntervalSince1970,
                        ]
                    )

                    try db.execute(
                        sql: "DELETE FROM workout_muscle_load WHERE workout_uuid = ?",
                        arguments: [payload.workoutUUID]
                    )
                    for muscleLoad in payload.muscleLoads {
                        try db.execute(
                            sql: """
                            INSERT INTO workout_muscle_load (workout_uuid, muscle_id, role, load, algorithm_version)
                            VALUES (?, ?, ?, ?, ?)
                            """,
                            arguments: [
                                payload.workoutUUID,
                                muscleLoad.muscle.rawValue,
                                muscleLoad.role.rawValue,
                                muscleLoad.load,
                                muscleLoad.algorithmVersion.description,
                            ]
                        )
                    }

                    try db.execute(
                        sql: "UPDATE workout SET review_state = ? WHERE hk_uuid = ?",
                        arguments: [payload.reviewState.rawValue, payload.workoutUUID]
                    )
                    affectedIDs = [payload.workoutUUID, annotationID.uuidString]

                case .commitMemory:
                    let payload = try proposal.decodePayload(CommitMemoryPayload.self)
                    try BodySeekRepository.saveTieredMemorySync(db: db, record: payload.memory)
                    affectedIDs = [payload.memory.id.uuidString]

                case .retireMemory:
                    let payload = try proposal.decodePayload(RetireMemoryPayload.self)
                    try BodySeekRepository.retireMemorySync(db: db, memoryID: payload.memoryID, retiredAt: payload.retiredAt)
                    affectedIDs = [payload.memoryID.uuidString]

                case .adjustPlan:
                    let payload = try proposal.decodePayload(AdjustPlanPayload.self)
                    try BodySeekRepository.savePlanItemSync(db: db, item: payload.item)
                    affectedIDs = [payload.item.id.uuidString]

                case .recordCheckIn:
                    let payload = try proposal.decodePayload(RecordCheckInPayload.self)
                    try BodySeekRepository.saveCheckInSync(db: db, checkIn: payload.checkIn)
                    affectedIDs = [payload.checkIn.id.uuidString, payload.checkIn.dayKey.isoString]

                case .upsertNutritionProfile:
                    let payload = try proposal.decodePayload(UpsertNutritionProfilePayload.self)
                    try BodySeekRepository.saveNutritionProfileSync(db: db, profile: payload.profile)
                    affectedIDs = [payload.profile.id.uuidString]

                case .commitNutritionTargets:
                    let payload = try proposal.decodePayload(CommitNutritionTargetsPayload.self)
                    try BodySeekRepository.saveNutritionTargetPlanSync(db: db, plan: payload.plan)
                    affectedIDs = [payload.plan.id.uuidString, payload.plan.targetVersion]

                case .logNutritionMeal, .logNutritionMeals:
                    let dayKey: DayKey
                    let entries: [MealEntry]
                    let fields: [String]
                    let note: String?
                    if proposal.kind == .logNutritionMeal {
                        let payload = try proposal.decodePayload(LogNutritionMealPayload.self)
                        dayKey = payload.dayKey
                        entries = [payload.entry]
                        fields = payload.partialFields
                        note = payload.note
                    } else {
                        let payload = try proposal.decodePayload(LogNutritionMealsPayload.self)
                        dayKey = payload.dayKey
                        entries = payload.entries
                        fields = entries.filter {
                            $0.kcal == nil || $0.proteinG == nil || $0.carbsG == nil || $0.fatG == nil
                        }.map { $0.mealType.rawValue }
                        note = nil
                    }
                    guard !entries.isEmpty, entries.allSatisfy({ $0.dayKey == dayKey }) else {
                        throw BodySeekDatabaseError.invalidProposalPayload(kind: proposal.kind)
                    }
                    var log = try BodySeekRepository.loadDailyNutritionLogSync(db: db, dayKey: dayKey)
                        ?? DailyNutritionLog(dayKey: dayKey)
                    for entry in entries {
                        if let idx = log.entries.firstIndex(where: { $0.id == entry.id }) {
                            log.entries[idx] = entry
                        } else {
                            log.entries.append(entry)
                        }
                    }
                    log.dietPartialFields = Set(log.dietPartialFields).union(fields).sorted()
                    if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        log.notes.append(note)
                    }
                    log.updatedAt = now
                    log.recalculateTotals()
                    try BodySeekRepository.saveDailyNutritionLogSync(db: db, log: log)
                    affectedIDs = [dayKey.isoString] + entries.map { $0.id.uuidString }

                case .closeNutritionDay:
                    let payload = try proposal.decodePayload(CloseNutritionDayPayload.self)
                    var log = try BodySeekRepository.loadDailyNutritionLogSync(db: db, dayKey: payload.dayKey)
                        ?? DailyNutritionLog(dayKey: payload.dayKey)
                    log.dietDayComplete = payload.markComplete
                    if let sportHours = payload.sportHours { log.sportHours = sportHours }
                    if let sportKcal = payload.sportKcal { log.sportKcal = sportKcal }
                    if let steps = payload.steps { log.steps = steps }
                    if let bmr = payload.bmrKcalUsed { log.bmrKcalUsed = bmr }
                    if let review = payload.reviewSummary { log.reviewSummary = review }
                    log.updatedAt = now
                    log.recalculateTotals()
                    try BodySeekRepository.saveDailyNutritionLogSync(db: db, log: log)
                    affectedIDs = [payload.dayKey.isoString]
                }

                let audit = ActionAuditEntry(
                    id: UUID(),
                    proposalJSON: proposalJSON,
                    origin: proposal.origin,
                    decision: .applied,
                    decidedAt: now,
                    affectedIDs: affectedIDs
                )
                try Self.insertAuditSync(db: db, audit: audit, encoder: encoder)
                return audit
            }
        } catch {
            Self.logger.error("ActionExecutor failed executing \(proposal.kind.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    @discardableResult
    public func reject(_ proposal: ActionProposal, now: Date = Date()) async throws -> ActionAuditEntry {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let proposalData = try encoder.encode(proposal)
        guard let proposalJSON = String(data: proposalData, encoding: .utf8) else {
            throw BodySeekDatabaseError.invalidJSONEncoding(context: "ActionProposal")
        }

        return try await database.writer.write { db in
            let audit = ActionAuditEntry(
                id: UUID(),
                proposalJSON: proposalJSON,
                origin: proposal.origin,
                decision: .rejected,
                decidedAt: now,
                affectedIDs: []
            )
            try Self.insertAuditSync(db: db, audit: audit, encoder: encoder)
            return audit
        }
    }

    private static func insertAuditSync(db: Database, audit: ActionAuditEntry, encoder: JSONEncoder) throws {
        let affectedData = try encoder.encode(audit.affectedIDs)
        guard let affectedJSON = String(data: affectedData, encoding: .utf8) else {
            throw BodySeekDatabaseError.invalidJSONEncoding(context: "ActionAuditEntry.affectedIDs")
        }
        try db.execute(
            sql: """
            INSERT INTO action_audit (id, proposal_json, origin, decision, decided_at, affected_ids_json)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                audit.id.uuidString,
                audit.proposalJSON,
                audit.origin.rawValue,
                audit.decision.rawValue,
                audit.decidedAt.timeIntervalSince1970,
                affectedJSON,
            ]
        )
    }
}
