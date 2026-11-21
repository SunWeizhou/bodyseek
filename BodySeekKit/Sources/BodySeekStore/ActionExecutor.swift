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
                var auditID = UUID()
                var decision = ActionAuditDecision.applied
                var snapshotVersion = 1
                var snapshotJSON: String?
                switch proposal.kind {
                case .annotateWorkout:
                    let payload = try proposal.decodePayload(AnnotateWorkoutPayload.self)
                    if let requestedDecision = payload.coachAnnotationDecision {
                        guard requestedDecision == .applied || requestedDecision == .rejected else {
                            throw BodySeekDatabaseError.invalidProposalPayload(kind: proposal.kind)
                        }
                        auditID = proposal.id
                        if let row = try Row.fetchOne(db, sql: "SELECT * FROM action_audit WHERE id = ?", arguments: [auditID.uuidString]),
                           let existing = try BodySeekRepository.decodeAuditEntry(row) {
                            return existing
                        }
                        decision = requestedDecision
                        if decision == .rejected {
                            affectedIDs = []
                            break
                        }
                    }
                    if try Self.isWorkoutDeleted(db, uuid: payload.workoutUUID) {
                        throw BodySeekDatabaseError.recordDeleted(table: "workout", key: payload.workoutUUID)
                    }
                    guard let beforeReviewRaw = try String.fetchOne(
                        db,
                        sql: "SELECT review_state FROM workout WHERE hk_uuid = ?",
                        arguments: [payload.workoutUUID]
                    ) else {
                        throw BodySeekDatabaseError.foreignKeyTargetMissing(
                            table: "workout",
                            key: payload.workoutUUID
                        )
                    }
                    let beforeReviewState = WorkoutReviewState(rawValue: beforeReviewRaw) ?? .unreviewed
                    let beforeAnnotations = try Self.fetchAnnotations(db, workoutUUID: payload.workoutUUID)
                    let beforeLoads = try Self.fetchMuscleLoads(db, workoutUUID: payload.workoutUUID)
                    if let expected = payload.expectedRecordState {
                        guard let row = try Row.fetchOne(
                            db,
                            sql: "SELECT start, end, type FROM workout WHERE hk_uuid = ?",
                            arguments: [payload.workoutUUID]
                        ) else {
                            throw BodySeekDatabaseError.recordDeleted(table: "workout", key: payload.workoutUUID)
                        }
                        let latest = beforeAnnotations.first
                        let current = WorkoutAnnotationRecordState(
                            workoutUUID: payload.workoutUUID,
                            start: Date(timeIntervalSince1970: row["start"]),
                            end: Date(timeIntervalSince1970: row["end"]),
                            type: row["type"],
                            reviewState: beforeReviewState,
                            latestAnnotationID: latest?.id,
                            latestAnnotationRawText: latest?.rawText
                        )
                        guard current.start == expected.start,
                              current.end == expected.end,
                              current.type == expected.type,
                              current.reviewState == expected.reviewState,
                              current.latestAnnotationID == expected.latestAnnotationID,
                              current.latestAnnotationRawText == expected.latestAnnotationRawText
                        else {
                            throw BodySeekDatabaseError.recordChanged(table: "workout", key: payload.workoutUUID)
                        }
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
                    let snapshot = WorkoutAnnotationUndoSnapshot(
                        workoutUUID: payload.workoutUUID,
                        beforeReviewState: beforeReviewState,
                        beforeAnnotations: beforeAnnotations,
                        beforeMuscleLoads: beforeLoads,
                        afterAnnotationID: annotationID,
                        afterRawText: payload.rawText,
                        afterParserVersion: payload.parserVersion,
                        afterReviewState: payload.reviewState,
                        afterMuscleLoads: payload.muscleLoads
                    )
                    let snapshotData = try encoder.encode(snapshot)
                    guard let encodedSnapshot = String(data: snapshotData, encoding: .utf8) else {
                        throw BodySeekDatabaseError.invalidJSONEncoding(context: "WorkoutAnnotationUndoSnapshot")
                    }
                    snapshotVersion = WorkoutAnnotationUndoSnapshot.currentVersion
                    snapshotJSON = encodedSnapshot
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
                        var entry = payload.entry
                        entry.isExplicitlyPartial = payload.partialFields.contains(entry.mealType.rawValue)
                        entries = [entry]
                        fields = payload.partialFields
                        note = payload.note
                    } else {
                        let payload = try proposal.decodePayload(LogNutritionMealsPayload.self)
                        dayKey = payload.dayKey
                        entries = payload.entries
                        fields = []
                        note = nil
                    }
                    guard !entries.isEmpty, entries.allSatisfy({ $0.dayKey == dayKey }) else {
                        throw BodySeekDatabaseError.invalidProposalPayload(kind: proposal.kind)
                    }
                    var log = try BodySeekRepository.loadDailyNutritionLogSync(db: db, dayKey: dayKey)
                        ?? DailyNutritionLog(dayKey: dayKey)
                    var affectedMeals = Set(entries.map(\.mealType))
                    for entry in entries {
                        if let idx = log.entries.firstIndex(where: { $0.id == entry.id }) {
                            affectedMeals.insert(log.entries[idx].mealType)
                            log.entries[idx] = entry
                        } else {
                            log.entries.append(entry)
                        }
                    }
                    log.dietPartialFields = Set(log.dietPartialFields).union(fields).sorted()
                    Self.refreshPartialFields(&log, affectedMeals: affectedMeals)
                    if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        log.notes.append(note)
                    }
                    log.updatedAt = now
                    log.recalculateTotals()
                    try BodySeekRepository.saveDailyNutritionLogSync(db: db, log: log)
                    affectedIDs = [dayKey.isoString] + entries.map { $0.id.uuidString }

                case .deleteNutritionMeal:
                    let payload = try proposal.decodePayload(DeleteNutritionMealPayload.self)
                    guard var log = try BodySeekRepository.loadDailyNutritionLogSync(db: db, dayKey: payload.dayKey),
                          let index = log.entries.firstIndex(where: { $0.id == payload.entryID })
                    else { throw BodySeekDatabaseError.invalidProposalPayload(kind: proposal.kind) }
                    let removed = log.entries.remove(at: index)
                    log.dietDayComplete = nil
                    Self.refreshPartialFields(&log, affectedMeals: [removed.mealType])
                    log.updatedAt = now
                    log.recalculateTotals()
                    try BodySeekRepository.saveDailyNutritionLogSync(db: db, log: log)
                    affectedIDs = [payload.dayKey.isoString, payload.entryID.uuidString]

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
                    id: auditID,
                    proposalJSON: proposalJSON,
                    origin: proposal.origin,
                    decision: decision,
                    decidedAt: now,
                    affectedIDs: affectedIDs,
                    snapshotVersion: snapshotVersion,
                    snapshotJSON: snapshotJSON
                )
                try Self.insertAuditSync(db: db, audit: audit, encoder: encoder)
                return audit
            }
        } catch {
            Self.logger.error("ActionExecutor failed executing \(proposal.kind.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Atomically restores the workout annotation state captured by the original
    /// `annotateWorkout` audit. Refuses when the workout was deleted or changed after
    /// the commit; repeated calls return the existing undo audit.
    @discardableResult
    public func undoWorkoutAnnotation(
        originalAuditID: UUID,
        now: Date = Date()
    ) async throws -> ActionAuditEntry {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            return try await database.writer.write { db in
                if let existingRow = try Row.fetchOne(
                    db,
                    sql: "SELECT * FROM action_audit WHERE undo_of = ? AND decision = ?",
                    arguments: [originalAuditID.uuidString, ActionAuditDecision.undone.rawValue]
                ), let existing = try BodySeekRepository.decodeAuditEntry(existingRow) {
                    return existing
                }
                guard let originalRow = try Row.fetchOne(
                    db,
                    sql: "SELECT * FROM action_audit WHERE id = ?",
                    arguments: [originalAuditID.uuidString]
                ), let original = try BodySeekRepository.decodeAuditEntry(originalRow) else {
                    throw BodySeekDatabaseError.undoUnsupported(reason: "找不到原操作审计")
                }
                guard original.decision == .applied else {
                    throw BodySeekDatabaseError.undoUnsupported(reason: "只有已提交的操作可以撤销")
                }
                guard original.snapshotVersion >= WorkoutAnnotationUndoSnapshot.currentVersion,
                      let snapshotJSON = original.snapshotJSON,
                      let snapshotData = snapshotJSON.data(using: .utf8),
                      let snapshot = try? JSONDecoder().decode(WorkoutAnnotationUndoSnapshot.self, from: snapshotData)
                else {
                    throw BodySeekDatabaseError.undoUnsupported(reason: "旧版审计没有可撤销快照")
                }
                if try Self.isWorkoutDeleted(db, uuid: snapshot.workoutUUID) {
                    throw BodySeekDatabaseError.recordDeleted(table: "workout", key: snapshot.workoutUUID)
                }
                guard let currentReviewRaw = try String.fetchOne(
                    db,
                    sql: "SELECT review_state FROM workout WHERE hk_uuid = ?",
                    arguments: [snapshot.workoutUUID]
                ) else {
                    throw BodySeekDatabaseError.recordDeleted(table: "workout", key: snapshot.workoutUUID)
                }
                let currentReview = WorkoutReviewState(rawValue: currentReviewRaw) ?? .unreviewed
                let currentAnnotations = try Self.fetchAnnotations(db, workoutUUID: snapshot.workoutUUID)
                let currentLoads = try Self.fetchMuscleLoads(db, workoutUUID: snapshot.workoutUUID)

                let expectedAnnotationIDs = Set(snapshot.beforeAnnotations.map(\.id)).union([snapshot.afterAnnotationID])
                let currentAnnotationIDs = Set(currentAnnotations.map(\.id))
                guard currentAnnotationIDs == expectedAnnotationIDs,
                      let afterAnnotation = currentAnnotations.first(where: { $0.id == snapshot.afterAnnotationID }),
                      afterAnnotation.rawText == snapshot.afterRawText,
                      afterAnnotation.parserVersion == snapshot.afterParserVersion,
                      currentReview == snapshot.afterReviewState,
                      Self.loadsEqual(currentLoads, snapshot.afterMuscleLoads)
                else {
                    throw BodySeekDatabaseError.undoConflict(reason: "训练标注、肌群负荷或复盘状态已在提交后变化")
                }

                try db.execute(
                    sql: "DELETE FROM workout_annotation WHERE workout_uuid = ?",
                    arguments: [snapshot.workoutUUID]
                )
                for annotation in snapshot.beforeAnnotations {
                    try db.execute(
                        sql: """
                        INSERT INTO workout_annotation (id, workout_uuid, raw_text, parser_version, confirmed_at)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                        arguments: [
                            annotation.id.uuidString,
                            annotation.workoutUUID,
                            annotation.rawText,
                            annotation.parserVersion.description,
                            annotation.confirmedAt?.timeIntervalSince1970,
                        ]
                    )
                }
                try db.execute(
                    sql: "DELETE FROM workout_muscle_load WHERE workout_uuid = ?",
                    arguments: [snapshot.workoutUUID]
                )
                for load in snapshot.beforeMuscleLoads {
                    try db.execute(
                        sql: """
                        INSERT INTO workout_muscle_load (workout_uuid, muscle_id, role, load, algorithm_version)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                        arguments: [
                            load.workoutUUID,
                            load.muscle.rawValue,
                            load.role.rawValue,
                            load.load,
                            load.algorithmVersion.description,
                        ]
                    )
                }
                try db.execute(
                    sql: "UPDATE workout SET review_state = ? WHERE hk_uuid = ?",
                    arguments: [snapshot.beforeReviewState.rawValue, snapshot.workoutUUID]
                )

                let undoID = UUID()
                let audit = ActionAuditEntry(
                    id: undoID,
                    proposalJSON: original.proposalJSON,
                    origin: .user,
                    decision: .undone,
                    decidedAt: now,
                    affectedIDs: [snapshot.workoutUUID, snapshot.afterAnnotationID.uuidString],
                    snapshotVersion: WorkoutAnnotationUndoSnapshot.currentVersion,
                    snapshotJSON: original.snapshotJSON,
                    undoOf: originalAuditID
                )
                try Self.insertAuditSync(db: db, audit: audit, encoder: encoder)
                try db.execute(
                    sql: "UPDATE action_audit SET undone_by = ? WHERE id = ?",
                    arguments: [undoID.uuidString, originalAuditID.uuidString]
                )
                return audit
            }
        } catch {
            Self.logger.error("ActionExecutor failed undo \(originalAuditID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
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

    private static func refreshPartialFields(_ log: inout DailyNutritionLog, affectedMeals: Set<MealType>) {
        var fields = Set(log.dietPartialFields)
        for meal in affectedMeals {
            let hasMissing = log.entries.contains { entry in
                guard entry.mealType == meal else { return false }
                if entry.isExplicitlyPartial == true { return true }
                if meal == .water { return entry.waterMl == nil }
                return entry.kcal == nil || entry.proteinG == nil || entry.carbsG == nil || entry.fatG == nil
            }
            if hasMissing { fields.insert(meal.rawValue) } else { fields.remove(meal.rawValue) }
        }
        log.dietPartialFields = fields.sorted()
    }

    private static func isWorkoutDeleted(_ db: Database, uuid: String) throws -> Bool {
        try Bool.fetchOne(
            db,
            sql: "SELECT 1 FROM deleted_healthkit_workout WHERE uuid = ?",
            arguments: [uuid]
        ) ?? false
    }

    private static func fetchAnnotations(_ db: Database, workoutUUID: String) throws -> [WorkoutAnnotationRecord] {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT id, workout_uuid, raw_text, parser_version, confirmed_at
            FROM workout_annotation
            WHERE workout_uuid = ?
            ORDER BY confirmed_at DESC, id ASC
            """,
            arguments: [workoutUUID]
        )
        return rows.compactMap { row in
            guard let id = UUID(uuidString: row["id"]) else { return nil }
            return WorkoutAnnotationRecord(
                id: id,
                workoutUUID: row["workout_uuid"],
                rawText: row["raw_text"],
                parserVersion: Self.decodeVersion(row["parser_version"] as String, fallback: .workoutParserV1),
                confirmedAt: (row["confirmed_at"] as Double?).map(Date.init(timeIntervalSince1970:))
            )
        }
    }

    private static func fetchMuscleLoads(_ db: Database, workoutUUID: String) throws -> [WorkoutMuscleLoadRecord] {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT workout_uuid, muscle_id, role, load, algorithm_version
            FROM workout_muscle_load
            WHERE workout_uuid = ?
            ORDER BY muscle_id ASC, role ASC
            """,
            arguments: [workoutUUID]
        )
        return rows.compactMap { row in
            guard let muscle = BodyRegionMuscle(rawValue: row["muscle_id"]),
                  let role = MuscleLoadRole(rawValue: row["role"])
            else { return nil }
            return WorkoutMuscleLoadRecord(
                workoutUUID: row["workout_uuid"],
                muscle: muscle,
                role: role,
                load: row["load"],
                algorithmVersion: Self.decodeVersion(row["algorithm_version"] as String, fallback: .recoveryHeuristicV1)
            )
        }
    }

    private static func decodeVersion(_ value: String, fallback: AlgorithmVersion) -> AlgorithmVersion {
        let parts = value.split(separator: "@", maxSplits: 1)
        guard let first = parts.first else { return fallback }
        return AlgorithmVersion(
            id: String(first),
            semver: parts.count > 1 ? String(parts[1]) : "1.0.0"
        )
    }

    private static func loadsEqual(_ lhs: [WorkoutMuscleLoadRecord], _ rhs: [WorkoutMuscleLoadRecord]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        let left = lhs.sorted {
            $0.muscle.rawValue == $1.muscle.rawValue
                ? $0.role.rawValue < $1.role.rawValue
                : $0.muscle.rawValue < $1.muscle.rawValue
        }
        let right = rhs.sorted {
            $0.muscle.rawValue == $1.muscle.rawValue
                ? $0.role.rawValue < $1.role.rawValue
                : $0.muscle.rawValue < $1.muscle.rawValue
        }
        return zip(left, right).allSatisfy {
            $0.workoutUUID.caseInsensitiveCompare($1.workoutUUID) == .orderedSame
                && $0.muscle == $1.muscle
                && $0.role == $1.role
                && abs($0.load - $1.load) < 0.0001
                && $0.algorithmVersion == $1.algorithmVersion
        }
    }

    private static func insertAuditSync(db: Database, audit: ActionAuditEntry, encoder: JSONEncoder) throws {
        let affectedData = try encoder.encode(audit.affectedIDs)
        guard let affectedJSON = String(data: affectedData, encoding: .utf8) else {
            throw BodySeekDatabaseError.invalidJSONEncoding(context: "ActionAuditEntry.affectedIDs")
        }
        try db.execute(
            sql: """
            INSERT INTO action_audit
                (id, proposal_json, origin, decision, decided_at, affected_ids_json,
                 snapshot_version, snapshot_json, undo_of, undone_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                audit.id.uuidString,
                audit.proposalJSON,
                audit.origin.rawValue,
                audit.decision.rawValue,
                audit.decidedAt.timeIntervalSince1970,
                affectedJSON,
                audit.snapshotVersion,
                audit.snapshotJSON,
                audit.undoOf?.uuidString,
                audit.undoneBy?.uuidString,
            ]
        )
    }
}
