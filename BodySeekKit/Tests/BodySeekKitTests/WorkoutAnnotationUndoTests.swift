import BodySeekCore
import BodySeekStore
import Foundation
import GRDB
import XCTest

final class WorkoutAnnotationUndoTests: XCTestCase {
    private let workoutUUID = "W-UNDO-1"
    private let messageID = UUID(uuidString: "00000000-0000-4000-8000-000000000777")!

    private func makeDB() async throws -> (BodySeekDatabase, BodySeekRepository, ActionExecutor) {
        let db = try BodySeekDatabase.inMemory()
        let repo = BodySeekRepository(database: db)
        let executor = ActionExecutor(database: db)
        let start = Date(timeIntervalSince1970: 1_795_000_000)
        try await repo.upsertWorkouts([
            StoredWorkoutRecord(
                hkUUID: workoutUUID,
                type: "传统力量训练",
                start: start,
                end: start.addingTimeInterval(3600),
                energy: 300,
                reviewState: .unreviewed
            ),
        ])
        return (db, repo, executor)
    }

    private func proposal(
        rawText: String = "昨晚练腿，深蹲 5 组，RPE 8",
        decision: ActionAuditDecision = .applied,
        expected: WorkoutAnnotationRecordState? = nil
    ) throws -> ActionProposal {
        let loads = [
            WorkoutMuscleLoadRecord(
                workoutUUID: workoutUUID,
                muscle: .quadriceps,
                role: .primary,
                load: 1.2
            ),
        ]
        return try ActionProposal(
            id: messageID,
            kind: .annotateWorkout,
            origin: .agent,
            encodablePayload: AnnotateWorkoutPayload(
                workoutUUID: workoutUUID,
                rawText: rawText,
                muscleLoads: loads,
                coachAnnotationDecision: decision,
                expectedRecordState: expected
            )
        )
    }

    func testCommitSnapshotAndIdempotentRetry() async throws {
        let (_, repo, executor) = try await makeDB()
        let first = try await executor.execute(try proposal())
        XCTAssertEqual(first.decision, .applied)
        XCTAssertEqual(first.snapshotVersion, 2)
        XCTAssertNotNil(first.snapshotJSON)
        let annotationsAfterCommit = try await repo.loadWorkoutAnnotations(workoutUUID: workoutUUID)
        let loadsAfterCommit = try await repo.loadMuscleLoads(workoutUUID: workoutUUID)
        XCTAssertEqual(annotationsAfterCommit.count, 1)
        XCTAssertEqual(loadsAfterCommit.count, 1)

        let retried = try await executor.execute(try proposal())
        XCTAssertEqual(retried.id, first.id)
        XCTAssertEqual(retried.decidedAt.timeIntervalSince1970, first.decidedAt.timeIntervalSince1970, accuracy: 0.001)
        let annotationsAfterRetry = try await repo.loadWorkoutAnnotations(workoutUUID: workoutUUID)
        XCTAssertEqual(annotationsAfterRetry.count, 1)
    }

    func testUndoRestoresAnnotationLoadsAndReviewState() async throws {
        let (_, repo, executor) = try await makeDB()
        _ = try await executor.execute(try proposal())
        let beforeUndo = try await repo.loadWorkoutAnnotations(workoutUUID: workoutUUID)
        XCTAssertEqual(beforeUndo.count, 1)

        let undo = try await executor.undoWorkoutAnnotation(originalAuditID: messageID)
        XCTAssertEqual(undo.decision, .undone)
        XCTAssertEqual(undo.undoOf, messageID)
        let annotationsAfterUndo = try await repo.loadWorkoutAnnotations(workoutUUID: workoutUUID)
        let loadsAfterUndo = try await repo.loadMuscleLoads(workoutUUID: workoutUUID)
        XCTAssertEqual(annotationsAfterUndo.count, 0)
        XCTAssertEqual(loadsAfterUndo.count, 0)
        let workouts = try await repo.loadWorkouts(limit: 10)
        XCTAssertEqual(workouts.first?.reviewState, .unreviewed)

        let secondUndo = try await executor.undoWorkoutAnnotation(originalAuditID: messageID)
        XCTAssertEqual(secondUndo.id, undo.id)
        let audits = try await repo.loadAuditEntries()
        XCTAssertEqual(audits.filter { $0.decision == .undone }.count, 1)
    }

    func testUndoRestoresPreviousAnnotationAndLoads() async throws {
        let (db, repo, executor) = try await makeDB()
        let oldID = UUID(uuidString: "00000000-0000-4000-8000-000000000111")!
        let oldLoad = WorkoutMuscleLoadRecord(
            workoutUUID: workoutUUID,
            muscle: .chest,
            role: .primary,
            load: 0.7
        )
        let uuidForFixture = workoutUUID
        let oldIDString = oldID.uuidString
        let oldMuscle = oldLoad.muscle.rawValue
        let oldRole = oldLoad.role.rawValue
        let oldAlgorithmVersion = oldLoad.algorithmVersion.description
        try await db.writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO workout_annotation (id, workout_uuid, raw_text, parser_version, confirmed_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [oldIDString, uuidForFixture, "之前练胸", "workout-parser-v1@1.0.0", 100.0]
            )
            try db.execute(
                sql: """
                INSERT INTO workout_muscle_load (workout_uuid, muscle_id, role, load, algorithm_version)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [uuidForFixture, oldMuscle, oldRole, oldLoad.load, oldAlgorithmVersion]
            )
            try db.execute(
                sql: "UPDATE workout SET review_state = ? WHERE hk_uuid = ?",
                arguments: [WorkoutReviewState.annotated.rawValue, uuidForFixture]
            )
        }
        _ = try await executor.execute(try proposal())
        let afterNew = try await repo.loadWorkoutAnnotations(workoutUUID: workoutUUID)
        XCTAssertEqual(afterNew.count, 2)

        _ = try await executor.undoWorkoutAnnotation(originalAuditID: messageID)
        let restoredAnnotations = try await repo.loadWorkoutAnnotations(workoutUUID: workoutUUID)
        XCTAssertEqual(restoredAnnotations.map(\.id), [oldID])
        XCTAssertEqual(restoredAnnotations.first?.rawText, "之前练胸")
        let restoredLoads = try await repo.loadMuscleLoads(workoutUUID: workoutUUID)
        XCTAssertEqual(restoredLoads.count, 1)
        XCTAssertEqual(restoredLoads.first?.muscle, .chest)
        let workouts = try await repo.loadWorkouts(limit: 10)
        XCTAssertEqual(workouts.first?.reviewState, .annotated)
    }

    func testUndoDecisionSurvivesMessageReload() async throws {
        let (_, repo, executor) = try await makeDB()
        let coachMessage = CoachMessage(
            id: messageID,
            role: .assistant,
            text: "确认这条训练复盘",
            workoutAnnotationProposal: CoachWorkoutAnnotationProposal(
                workoutUUID: workoutUUID,
                workoutTitle: "传统力量训练",
                rawText: "昨晚练腿",
                proposal: WorkoutAnnotationProposal(rawText: "昨晚练腿", primaryMuscles: [.quadriceps]),
                muscleLoads: []
            )
        )
        try await repo.appendMessage(coachMessage)
        _ = try await executor.execute(try proposal())
        let applied = try await repo.loadMessages()
        XCTAssertEqual(applied.first?.annotationDecision, .applied)

        _ = try await executor.undoWorkoutAnnotation(originalAuditID: messageID)
        let undone = try await repo.loadMessages()
        XCTAssertEqual(undone.first?.annotationDecision, .undone)
    }

    func testUndoRefusesWhenAnnotationChangedAfterCommit() async throws {
        let (db, repo, executor) = try await makeDB()
        _ = try await executor.execute(try proposal())
        let uuidForInsert = workoutUUID
        try await db.writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO workout_annotation (id, workout_uuid, raw_text, parser_version, confirmed_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [UUID().uuidString, uuidForInsert, "用户手改", "workout-parser-v1@1.0.0", Date().timeIntervalSince1970]
            )
        }
        do {
            _ = try await executor.undoWorkoutAnnotation(originalAuditID: messageID)
            XCTFail("expected conflict")
        } catch let error as BodySeekDatabaseError {
            guard case .undoConflict = error else { return XCTFail("unexpected \(error)") }
        }
        let annotationsAfterManualEdit = try await repo.loadWorkoutAnnotations(workoutUUID: workoutUUID)
        XCTAssertEqual(annotationsAfterManualEdit.count, 2)
    }

    func testUndoRefusesDeletedWorkout() async throws {
        let (_, repo, executor) = try await makeDB()
        _ = try await executor.execute(try proposal())
        _ = try await repo.applyWorkoutDeletions([workoutUUID])
        do {
            _ = try await executor.undoWorkoutAnnotation(originalAuditID: messageID)
            XCTFail("expected deleted")
        } catch let error as BodySeekDatabaseError {
            guard case .recordDeleted = error else { return XCTFail("unexpected \(error)") }
        }
    }

    func testOldAuditWithoutSnapshotCannotUndo() async throws {
        let (db, _, executor) = try await makeDB()
        let auditIDString = messageID.uuidString
        try await db.writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO action_audit (id, proposal_json, origin, decision, decided_at, affected_ids_json)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    auditIDString,
                    #"{"id":"00000000-0000-4000-8000-000000000777","kind":"annotateWorkout","origin":"agent","payload":{},"createdAt":0}"#,
                    "agent",
                    "applied",
                    Date().timeIntervalSince1970,
                    "[]",
                ]
            )
        }
        do {
            _ = try await executor.undoWorkoutAnnotation(originalAuditID: messageID)
            XCTFail("expected unsupported")
        } catch let error as BodySeekDatabaseError {
            guard case .undoUnsupported = error else { return XCTFail("unexpected \(error)") }
        }
    }

    func testRejectedProposalRetryReturnsRejectedAudit() async throws {
        let (_, repo, executor) = try await makeDB()
        let rejected = try await executor.execute(try proposal(decision: .rejected))
        XCTAssertEqual(rejected.decision, .rejected)
        let annotationsAfterReject = try await repo.loadWorkoutAnnotations(workoutUUID: workoutUUID)
        XCTAssertEqual(annotationsAfterReject.count, 0)
        let retried = try await executor.execute(try proposal(decision: .rejected))
        XCTAssertEqual(retried.id, rejected.id)
        XCTAssertEqual(retried.decision, .rejected)
    }

    func testRecordStateBindingDetectsChangeBeforeCommit() async throws {
        let (db, _, executor) = try await makeDB()
        let state = WorkoutAnnotationRecordState(
            workoutUUID: workoutUUID,
            start: Date(timeIntervalSince1970: 1_795_000_000),
            end: Date(timeIntervalSince1970: 1_795_003_600),
            type: "传统力量训练",
            reviewState: .unreviewed
        )
        let uuidForUpdate = workoutUUID
        try await db.writer.write { db in
            try db.execute(
                sql: "UPDATE workout SET review_state = ? WHERE hk_uuid = ?",
                arguments: [WorkoutReviewState.skipped.rawValue, uuidForUpdate]
            )
        }
        do {
            _ = try await executor.execute(try proposal(expected: state))
            XCTFail("expected recordChanged")
        } catch let error as BodySeekDatabaseError {
            guard case .recordChanged = error else { return XCTFail("unexpected \(error)") }
        }
    }
}
