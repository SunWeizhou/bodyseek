import BodySeekCore
import BodySeekStore
import Foundation
import GRDB
import XCTest

/// ADR 0020 动作层：按风险级别执行、审计快照、撤销与冲突。
final class ActionLayerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_795_000_000)
    private let day = DayKey(year: 2026, month: 11, day: 22)

    private func makeStore() throws -> (BodySeekDatabase, BodySeekRepository, ActionExecutor) {
        let db = try BodySeekDatabase.inMemory()
        return (db, BodySeekRepository(database: db), ActionExecutor(database: db))
    }

    private func commitMemory(id: UUID = UUID(), content: String = "右肩前束微痛") throws -> ActionProposal {
        let memory = TieredMemoryRecord(id: id, tier: .profile, content: content, confirmedAt: t0)
        return try ActionProposal(
            kind: .commitMemory,
            origin: .agent,
            encodablePayload: CommitMemoryPayload(memory: memory),
            createdAt: t0
        )
    }

    private func retireMemory(_ id: UUID, at date: Date) throws -> ActionProposal {
        try ActionProposal(
            kind: .retireMemory,
            origin: .agent,
            encodablePayload: RetireMemoryPayload(memoryID: id, retiredAt: date),
            createdAt: date
        )
    }

    private func meal(_ name: String) -> MealEntry {
        MealEntry(dayKey: day, mealType: .lunch, foodName: name, portionAmount: 100, portionUnit: "g", kcal: 200, recordedAt: t0)
    }

    private func logMeal(_ entry: MealEntry) throws -> ActionProposal {
        try ActionProposal(
            kind: .logNutritionMeal,
            origin: .agent,
            encodablePayload: LogNutritionMealPayload(dayKey: day, entry: entry),
            createdAt: t0
        )
    }

    // MARK: - A 级：执行 → 审计 → 撤销

    func testAutoActionWritesAuditThenUndoes() async throws {
        let (_, repo, executor) = try makeStore()
        let memoryID = UUID()
        let outcome = try await executor.executeAction(try commitMemory(id: memoryID), source: ActionSource.coach, now: t0)

        let receipt = try XCTUnwrap(outcome.receipt)
        XCTAssertEqual(receipt.kind, .commitMemory)
        XCTAssertEqual(receipt.risk, .a)
        XCTAssertTrue(receipt.isUndoable)
        XCTAssertNil(receipt.undoDeadline)
        XCTAssertTrue(receipt.detail.contains("右肩前束微痛"))

        let active = try await repo.loadTieredMemories(includeRetired: false)
        XCTAssertEqual(active.map(\.id), [memoryID])

        let audits = try await repo.loadAuditEntries()
        let audit = try XCTUnwrap(audits.first { $0.id == receipt.id })
        XCTAssertEqual(audit.decision, .applied)
        XCTAssertEqual(audit.riskLevel, "a")
        XCTAssertEqual(audit.source, "coach")
        XCTAssertNil(audit.undoDeadline)
        XCTAssertEqual(audit.snapshotVersion, MemoryUndoSnapshot.currentVersion)
        XCTAssertNotNil(audit.snapshotJSON)

        let undo = try await executor.undoAction(originalAuditID: receipt.id, now: t0.addingTimeInterval(60))
        XCTAssertEqual(undo.decision, .undone)
        XCTAssertEqual(undo.undoOf, receipt.id)
        let afterUndo = try await repo.loadTieredMemories(includeRetired: false)
        XCTAssertTrue(afterUndo.isEmpty)

        // 幂等：再次撤销返回同一条撤销审计，不会多写。
        let again = try await executor.undoAction(originalAuditID: receipt.id, now: t0.addingTimeInterval(120))
        XCTAssertEqual(again.id, undo.id)
        let undoRows = try await repo.loadAuditEntries().filter { $0.decision == .undone }
        XCTAssertEqual(undoRows.count, 1)
    }

    func testNutritionActionUndoRestoresPreviousLog() async throws {
        let (_, repo, executor) = try makeStore()
        let first = meal("鸡胸肉")
        _ = try await executor.executeAction(try logMeal(first), source: ActionSource.coach, now: t0)
        let second = meal("米饭")
        let outcome = try await executor.executeAction(try logMeal(second), source: ActionSource.coach, now: t0.addingTimeInterval(10))
        let receipt = try XCTUnwrap(outcome.receipt)
        XCTAssertEqual(receipt.risk, .a)

        let both = try await repo.loadNutritionLogs(from: day, to: day)
        XCTAssertEqual(both.first?.entries.count, 2)

        _ = try await executor.undoAction(originalAuditID: receipt.id, now: t0.addingTimeInterval(20))
        let restored = try await repo.loadNutritionLogs(from: day, to: day)
        XCTAssertEqual(restored.first?.entries.map(\.foodName), ["鸡胸肉"])
    }

    // MARK: - B 级：24 小时撤销期限

    func testHighlightedActionHasTwentyFourHourUndoWindow() async throws {
        let (_, repo, executor) = try makeStore()
        let memoryID = UUID()
        _ = try await executor.execute(try commitMemory(id: memoryID))

        let outcome = try await executor.executeAction(try retireMemory(memoryID, at: t0), source: ActionSource.coach, now: t0)
        let receipt = try XCTUnwrap(outcome.receipt)
        XCTAssertEqual(receipt.risk, .b)
        XCTAssertEqual(receipt.undoDeadline, t0.addingTimeInterval(AppActionCatalog.highlightedUndoWindow))
        XCTAssertEqual(receipt.beforeText, "生效中")
        XCTAssertEqual(receipt.afterText, "已停用")
        XCTAssertTrue(receipt.canUndo(at: t0.addingTimeInterval(3_600)))
        XCTAssertFalse(receipt.canUndo(at: t0.addingTimeInterval(25 * 3_600)))

        let audits = try await repo.loadAuditEntries()
        let audit = try XCTUnwrap(audits.first { $0.id == receipt.id })
        XCTAssertEqual(audit.riskLevel, "b")
        XCTAssertEqual(audit.undoDeadline, receipt.undoDeadline)

        let retired = try await repo.loadTieredMemories(includeRetired: false)
        XCTAssertTrue(retired.isEmpty)
        _ = try await executor.undoAction(originalAuditID: receipt.id, now: t0.addingTimeInterval(3_600))
        let restored = try await repo.loadTieredMemories(includeRetired: false)
        XCTAssertEqual(restored.map(\.id), [memoryID])
    }

    func testUndoAfterDeadlineIsRefused() async throws {
        let (_, repo, executor) = try makeStore()
        let memoryID = UUID()
        _ = try await executor.execute(try commitMemory(id: memoryID))
        let outcome = try await executor.executeAction(try retireMemory(memoryID, at: t0), source: ActionSource.coach, now: t0)
        let receipt = try XCTUnwrap(outcome.receipt)

        do {
            _ = try await executor.undoAction(originalAuditID: receipt.id, now: t0.addingTimeInterval(25 * 3_600))
            XCTFail("超过 24 小时应该拒绝撤销")
        } catch let error as AppActionError {
            XCTAssertEqual(error, .undoWindowExpired)
        }
        let stillRetired = try await repo.loadTieredMemories(includeRetired: false)
        XCTAssertTrue(stillRetired.isEmpty)
    }

    // MARK: - C 级：需要确认

    func testConfirmationLevelActionIsNotExecutedWithoutConfirmation() async throws {
        let (_, repo, executor) = try makeStore()
        let entry = meal("炸鸡")
        _ = try await executor.execute(try logMeal(entry))
        let auditsBefore = try await repo.loadAuditEntries().count

        let delete = try ActionProposal(
            kind: .deleteNutritionMeal,
            origin: .agent,
            encodablePayload: DeleteNutritionMealPayload(dayKey: day, entryID: entry.id),
            createdAt: t0
        )
        let outcome = try await executor.executeAction(delete, source: ActionSource.coach, now: t0)
        XCTAssertEqual(outcome, .needsConfirmation(kind: .deleteNutritionMeal, title: "删除餐食记录"))
        XCTAssertNil(outcome.receipt)

        let logs = try await repo.loadNutritionLogs(from: day, to: day)
        XCTAssertEqual(logs.first?.entries.count, 1)
        let auditsAfter = try await repo.loadAuditEntries().count
        XCTAssertEqual(auditsAfter, auditsBefore, "没有确认就不能写审计")

        let confirmed = try await executor.executeAction(delete, source: ActionSource.page, confirmed: true, now: t0)
        let receipt = try XCTUnwrap(confirmed.receipt)
        XCTAssertEqual(receipt.risk, .c)
        XCTAssertNil(receipt.undoDeadline)
        let afterDelete = try await repo.loadNutritionLogs(from: day, to: day)
        XCTAssertEqual(afterDelete.first?.entries.count, 0)
    }

    func testCatalogRoutesPlanChangeToConfirmation() {
        // 训练计划没有撤销快照：目录里声明为 B，但实际按 C 级处理。
        let descriptor = AppActionCatalog.descriptor(for: .adjustPlan)
        XCTAssertEqual(descriptor.effectiveRisk, .c)
        XCTAssertTrue(descriptor.requiresConfirmation)
    }

    // MARK: - 撤销冲突

    func testUndoConflictWhenMemoryChangedAfterwards() async throws {
        let (_, repo, executor) = try makeStore()
        let memoryID = UUID()
        let saved = try await executor.executeAction(try commitMemory(id: memoryID), source: ActionSource.coach, now: t0)
        let receipt = try XCTUnwrap(saved.receipt)
        // 之后用户在记忆页把它停用了。
        _ = try await executor.execute(try retireMemory(memoryID, at: t0.addingTimeInterval(30)))

        do {
            _ = try await executor.undoAction(originalAuditID: receipt.id, now: t0.addingTimeInterval(60))
            XCTFail("记忆已被停用，撤销应该报冲突")
        } catch BodySeekDatabaseError.undoConflict {
            // 预期。
        }
        let undoRows = try await repo.loadAuditEntries().filter { $0.decision == .undone }
        XCTAssertTrue(undoRows.isEmpty, "冲突时不能写撤销审计")
    }

    func testUndoConflictWhenNutritionLogChangedAfterwards() async throws {
        let (_, repo, executor) = try makeStore()
        let first = try await executor.executeAction(try logMeal(meal("早餐")), source: ActionSource.coach, now: t0)
        let receipt = try XCTUnwrap(first.receipt)
        _ = try await executor.execute(try logMeal(meal("午餐")), now: t0.addingTimeInterval(30))

        do {
            _ = try await executor.undoAction(originalAuditID: receipt.id, now: t0.addingTimeInterval(60))
            XCTFail("当天日志已被改动，撤销应该报冲突")
        } catch BodySeekDatabaseError.undoConflict {
            // 预期。
        }
        let logs = try await repo.loadNutritionLogs(from: day, to: day)
        XCTAssertEqual(logs.first?.entries.count, 2, "冲突时当前数据保持不变")
    }

    // MARK: - 回执存取与最近动作

    func testReceiptsPersistOnMessageAndReflectUndo() async throws {
        let (_, repo, executor) = try makeStore()
        let outcome = try await executor.executeAction(try commitMemory(), source: ActionSource.coach, now: t0)
        let receipt = try XCTUnwrap(outcome.receipt)

        let message = CoachMessage(role: .assistant, text: "已保存", timestamp: t0, appliedActions: [receipt])
        try await repo.appendMessage(message)
        let loaded = try await repo.loadMessages()
        XCTAssertEqual(loaded.first?.appliedActions.map(\.id), [receipt.id])
        XCTAssertNil(loaded.first?.appliedActions.first?.undoneAt)

        _ = try await executor.undoAction(originalAuditID: receipt.id, now: t0.addingTimeInterval(60))
        let reloaded = try await repo.loadMessages()
        XCTAssertNotNil(reloaded.first?.appliedActions.first?.undoneAt)
        let direct = try await repo.loadMessageReceipts(messageID: message.id)
        XCTAssertNotNil(direct.first?.undoneAt)

        let recent = try await repo.loadRecentActionReceipts(limit: 5)
        XCTAssertEqual(recent.first?.id, receipt.id)
        XCTAssertNotNil(recent.first?.undoneAt)
    }

    func testAnnotationUndoGoesThroughSharedImplementation() async throws {
        let (_, repo, executor) = try makeStore()
        let workoutUUID = "W-ACTION-LAYER"
        let start = Date(timeIntervalSince1970: 1_795_000_000)
        try await repo.upsertWorkouts([
            StoredWorkoutRecord(hkUUID: workoutUUID, type: "传统力量训练", start: start, end: start.addingTimeInterval(3_600), energy: 300),
        ])
        let proposal = try ActionProposal(
            kind: .annotateWorkout,
            origin: .agent,
            encodablePayload: AnnotateWorkoutPayload(workoutUUID: workoutUUID, rawText: "练胸 RPE 8"),
            createdAt: t0
        )
        let outcome = try await executor.executeAction(proposal, source: ActionSource.coach, now: t0)
        let receipt = try XCTUnwrap(outcome.receipt)
        XCTAssertEqual(receipt.risk, .a)
        let annotated = try await repo.loadWorkoutAnnotations(workoutUUID: workoutUUID)
        XCTAssertEqual(annotated.count, 1)

        let undo = try await executor.undoAction(originalAuditID: receipt.id, now: t0.addingTimeInterval(60))
        XCTAssertEqual(undo.decision, .undone)
        let afterUndo = try await repo.loadWorkoutAnnotations(workoutUUID: workoutUUID)
        XCTAssertTrue(afterUndo.isEmpty)
    }

    // MARK: - BodyModelStore

    func testBodyModelRevisionChangesAfterAction() async throws {
        let (db, _, executor) = try makeStore()
        let store = BodyModelStore(database: db)
        let before = try await store.current()
        XCTAssertTrue(before.activeMemories.isEmpty)

        _ = try await executor.executeAction(try commitMemory(), source: ActionSource.coach, now: t0)
        let after = try await store.current()
        XCTAssertNotEqual(before.revision, after.revision)
        XCTAssertEqual(after.activeMemories.count, 1)
        XCTAssertEqual(after.recentActions.first?.riskLevel, "a")
    }

    func testBodyModelObservationEmitsOnWrite() async throws {
        let (db, _, executor) = try makeStore()
        let store = BodyModelStore(database: db)
        var iterator = store.observe().makeAsyncIterator()
        let first = try await iterator.next()
        XCTAssertNotNil(first)

        _ = try await executor.executeAction(try commitMemory(), source: ActionSource.coach, now: t0)
        let second = try await iterator.next()
        XCTAssertNotNil(second)
        XCTAssertNotEqual(first?.revision, second?.revision)
        XCTAssertEqual(second?.activeMemories.count, 1)
    }
}
