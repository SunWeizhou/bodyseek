import BodySeekCore
import Foundation
import GRDB

/// 动作层写入审计时附带的元数据（落在 v7 新增的 `risk_level`、`source`、`undo_deadline` 列）。
public struct ActionAuditMetadata: Sendable, Equatable {
    /// 风险级别：`a` / `b` / `c`。
    public var riskLevel: String?
    /// 动作来源。
    public var source: String?
    /// 撤销期限。
    public var undoDeadline: Date?

    /// 创建元数据。
    public init(riskLevel: String? = nil, source: String? = nil, undoDeadline: Date? = nil) {
        self.riskLevel = riskLevel
        self.source = source
        self.undoDeadline = undoDeadline
    }
}

/// 动作来源标签。
public enum ActionSource {
    /// Coach 通过工具直接执行。
    public static let coach = "coach"
    /// 用户在页面上点击执行。
    public static let page = "page"
    /// 系统自动写入。
    public static let system = "system"
}

// MARK: - 按风险级别执行

public extension ActionExecutor {
    /// 按动作目录的风险级别执行。
    ///
    /// - A、B 级：直接执行，单事务写入业务数据与 `action_audit`（含 before/after 快照、风险级别、来源、撤销期限），
    ///   返回回执。
    /// - C 级：`confirmed == false` 时不写任何数据，返回 `.needsConfirmation`；`confirmed == true`（用户已点确认）才执行。
    /// - 尚未实现撤销的 B 级动作按 C 级处理（见 `AppActionDescriptor.effectiveRisk`）。
    func executeAction(
        _ proposal: ActionProposal,
        source: String,
        confirmed: Bool = false,
        now: Date = Date()
    ) async throws -> AppActionOutcome {
        let descriptor = AppActionCatalog.descriptor(for: proposal.kind)
        if descriptor.requiresConfirmation, !confirmed {
            return .needsConfirmation(kind: proposal.kind, title: descriptor.title)
        }
        let deadline = descriptor.undoWindow.map { now.addingTimeInterval($0) }
        let metadata = ActionAuditMetadata(
            riskLevel: descriptor.effectiveRisk.rawValue,
            source: source,
            undoDeadline: deadline
        )
        let audit = try await execute(proposal, now: now, metadata: metadata)
        return .executed(Self.makeReceipt(audit: audit, proposal: proposal))
    }

    /// 按原操作 ID 撤销。
    ///
    /// - 训练标注：复用 `undoWorkoutAnnotation`（同一套冲突检查与快照）。
    /// - 记忆、营养日志：读取 `action_audit` 里的 before/after 快照，当前数据与 after 不一致时抛 `undoConflict`。
    /// - B 级动作超过 `undo_deadline` 抛 `AppActionError.undoWindowExpired`。
    /// - 已撤销过的动作再次撤销，返回原来的撤销审计（幂等）。
    @discardableResult
    func undoAction(originalAuditID: UUID, now: Date = Date()) async throws -> ActionAuditEntry {
        let original = try await database.writer.read { db -> ActionAuditEntry? in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM action_audit WHERE id = ?",
                arguments: [originalAuditID.uuidString]
            ) else { return nil }
            return try BodySeekRepository.decodeAuditEntry(row)
        }
        guard let original else {
            throw BodySeekDatabaseError.undoUnsupported(reason: "找不到原操作审计")
        }
        let proposal = try JSONDecoder().decode(ActionProposal.self, from: Data(original.proposalJSON.utf8))
        if proposal.kind == .annotateWorkout {
            return try await undoWorkoutAnnotation(originalAuditID: originalAuditID, now: now)
        }
        if let deadline = original.undoDeadline, original.undoneBy == nil, now > deadline {
            throw AppActionError.undoWindowExpired
        }
        return try await undoSnapshotAction(original: original, proposal: proposal, now: now)
    }

    /// 最近由动作层执行的动作回执（新的在前），已撤销的带 `undoneAt`。
    func recentReceipts(limit: Int) async throws -> [AppActionReceipt] {
        let rows = try await database.writer.read { db -> [ActionAuditEntry] in
            let fetched = try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM action_audit
                WHERE decision = ? AND risk_level IS NOT NULL
                ORDER BY decided_at DESC
                LIMIT ?
                """,
                arguments: [ActionAuditDecision.applied.rawValue, max(1, limit)]
            )
            return try fetched.compactMap(BodySeekRepository.decodeAuditEntry)
        }
        return try await Self.receipts(for: rows, database: database)
    }

    /// 为一批审计记录生成回执，并填上撤销时间。
    internal static func receipts(for audits: [ActionAuditEntry], database: BodySeekDatabase) async throws -> [AppActionReceipt] {
        let decoder = JSONDecoder()
        var result: [AppActionReceipt] = []
        for audit in audits {
            guard let proposal = try? decoder.decode(ActionProposal.self, from: Data(audit.proposalJSON.utf8)) else { continue }
            var receipt = makeReceipt(audit: audit, proposal: proposal)
            if let undoID = audit.undoneBy {
                let undoneAt = try await database.writer.read { db -> Double? in
                    let row = try Row.fetchOne(
                        db,
                        sql: "SELECT decided_at FROM action_audit WHERE id = ?",
                        arguments: [undoID.uuidString]
                    )
                    return row.flatMap { $0["decided_at"] as Double? }
                }
                receipt.undoneAt = undoneAt.map(Date.init(timeIntervalSince1970:))
            }
            result.append(receipt)
        }
        return result
    }
}

// MARK: - 快照撤销（记忆、营养日志）

extension ActionExecutor {
    static func encodeSnapshot<T: Encodable>(_ value: T, encoder: JSONEncoder) throws -> String {
        let data = try encoder.encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw BodySeekDatabaseError.invalidJSONEncoding(context: "ActionUndoSnapshot")
        }
        return text
    }

    /// 营养日志类动作：在同一事务里记录当天日志的 before / after。
    static func captureNutritionSnapshot(
        _ db: Database,
        dayKey: DayKey,
        before: DailyNutritionLog?,
        version: inout Int,
        json: inout String?,
        encoder: JSONEncoder
    ) throws {
        guard let after = try BodySeekRepository.loadDailyNutritionLogSync(db: db, dayKey: dayKey) else {
            throw BodySeekDatabaseError.foreignKeyTargetMissing(table: "daily_nutrition_log", key: dayKey.isoString)
        }
        version = NutritionLogUndoSnapshot.currentVersion
        json = try encodeSnapshot(NutritionLogUndoSnapshot(dayKey: dayKey, before: before, after: after), encoder: encoder)
    }

    private func undoSnapshotAction(
        original: ActionAuditEntry,
        proposal: ActionProposal,
        now: Date
    ) async throws -> ActionAuditEntry {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let originalID = original.id
        return try await database.writer.write { db in
                if let existingRow = try Row.fetchOne(
                    db,
                    sql: "SELECT * FROM action_audit WHERE undo_of = ? AND decision = ?",
                    arguments: [originalID.uuidString, ActionAuditDecision.undone.rawValue]
                ), let existing = try BodySeekRepository.decodeAuditEntry(existingRow) {
                    return existing
                }
                guard original.decision == .applied else {
                    throw BodySeekDatabaseError.undoUnsupported(reason: "只有已提交的操作可以撤销")
                }
                guard let snapshotJSON = original.snapshotJSON else {
                    throw BodySeekDatabaseError.undoUnsupported(reason: "旧版审计没有可撤销快照")
                }
                let affected: [String]
                switch proposal.kind {
                case .commitMemory:
                    let payload = try proposal.decodePayload(CommitMemoryPayload.self)
                    let snapshot = try Self.decodeSnapshot(MemoryUndoSnapshot.self, json: snapshotJSON, version: original.snapshotVersion, expected: MemoryUndoSnapshot.currentVersion)
                    try Self.undoCommitMemory(db, payload: payload, snapshot: snapshot, now: now)
                    affected = [snapshot.memoryID.uuidString]
                case .retireMemory:
                    let payload = try proposal.decodePayload(RetireMemoryPayload.self)
                    let snapshot = try Self.decodeSnapshot(MemoryUndoSnapshot.self, json: snapshotJSON, version: original.snapshotVersion, expected: MemoryUndoSnapshot.currentVersion)
                    try Self.undoRetireMemory(db, payload: payload, snapshot: snapshot)
                    affected = [snapshot.memoryID.uuidString]
                case .logNutritionMeal, .logNutritionMeals, .deleteNutritionMeal, .closeNutritionDay:
                    let snapshot = try Self.decodeSnapshot(NutritionLogUndoSnapshot.self, json: snapshotJSON, version: original.snapshotVersion, expected: NutritionLogUndoSnapshot.currentVersion)
                    try Self.undoNutritionLog(db, snapshot: snapshot)
                    affected = [snapshot.dayKey.isoString]
                case .annotateWorkout, .adjustPlan, .recordCheckIn, .upsertNutritionProfile, .commitNutritionTargets:
                    throw BodySeekDatabaseError.undoUnsupported(reason: "这类操作暂不支持撤销")
                }

                let undoID = UUID()
                let audit = ActionAuditEntry(
                    id: undoID,
                    proposalJSON: original.proposalJSON,
                    origin: .user,
                    decision: .undone,
                    decidedAt: now,
                    affectedIDs: affected,
                    snapshotVersion: original.snapshotVersion,
                    snapshotJSON: original.snapshotJSON,
                    undoOf: originalID,
                    source: ActionSource.page
                )
                try Self.insertAuditSync(db: db, audit: audit, encoder: encoder)
                try db.execute(
                    sql: "UPDATE action_audit SET undone_by = ? WHERE id = ?",
                    arguments: [undoID.uuidString, originalID.uuidString]
                )
                return audit
        }
    }

    private static func decodeSnapshot<T: Decodable>(_ type: T.Type, json: String, version: Int, expected: Int) throws -> T {
        guard version >= expected else {
            throw BodySeekDatabaseError.undoUnsupported(reason: "旧版审计没有可撤销快照")
        }
        do {
            return try JSONDecoder().decode(type, from: Data(json.utf8))
        } catch {
            throw BodySeekDatabaseError.undoUnsupported(reason: "撤销快照无法解析")
        }
    }

    private static func undoCommitMemory(
        _ db: Database,
        payload: CommitMemoryPayload,
        snapshot: MemoryUndoSnapshot,
        now: Date
    ) throws {
        guard !snapshot.existedBefore else {
            throw BodySeekDatabaseError.undoUnsupported(reason: "这条记忆在保存前已存在，无法自动还原")
        }
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT content, retired_at FROM memory WHERE id = ?",
            arguments: [snapshot.memoryID.uuidString]
        ) else {
            throw BodySeekDatabaseError.undoConflict(reason: "这条记忆已被删除")
        }
        let content: String = row["content"]
        let retiredAt: Double? = row["retired_at"]
        guard retiredAt == nil, content == payload.memory.content else {
            throw BodySeekDatabaseError.undoConflict(reason: "这条记忆在保存后已被修改或停用")
        }
        try BodySeekRepository.retireMemorySync(db: db, memoryID: snapshot.memoryID, retiredAt: now)
    }

    private static func undoRetireMemory(
        _ db: Database,
        payload: RetireMemoryPayload,
        snapshot: MemoryUndoSnapshot
    ) throws {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT retired_at FROM memory WHERE id = ?",
            arguments: [snapshot.memoryID.uuidString]
        ) else {
            throw BodySeekDatabaseError.undoConflict(reason: "这条记忆已被删除")
        }
        let current: Double? = row["retired_at"]
        guard let current, abs(current - payload.retiredAt.timeIntervalSince1970) < 0.001 else {
            throw BodySeekDatabaseError.undoConflict(reason: "这条记忆的停用状态在之后又被改过")
        }
        try db.execute(
            sql: "UPDATE memory SET retired_at = ? WHERE id = ?",
            arguments: [snapshot.previousRetiredAt?.timeIntervalSince1970, snapshot.memoryID.uuidString]
        )
    }

    private static func undoNutritionLog(_ db: Database, snapshot: NutritionLogUndoSnapshot) throws {
        let current = try BodySeekRepository.loadDailyNutritionLogSync(db: db, dayKey: snapshot.dayKey)
        guard current == snapshot.after else {
            throw BodySeekDatabaseError.undoConflict(reason: "\(snapshot.dayKey.isoString) 的饮食记录在之后又被修改")
        }
        if let before = snapshot.before {
            try BodySeekRepository.saveDailyNutritionLogSync(db: db, log: before)
        } else {
            try db.execute(sql: "DELETE FROM daily_nutrition_log WHERE day_key = ?", arguments: [snapshot.dayKey.isoString])
        }
    }
}

// MARK: - 回执文案

extension ActionExecutor {
    /// 根据审计记录与提案生成回执；文案只描述事实（做了什么、改在哪里）。
    static func makeReceipt(audit: ActionAuditEntry, proposal: ActionProposal) -> AppActionReceipt {
        let descriptor = AppActionCatalog.descriptor(for: proposal.kind)
        let text = describe(proposal)
        let executed = audit.decision == .applied
        return AppActionReceipt(
            id: audit.id,
            kind: proposal.kind,
            risk: descriptor.effectiveRisk,
            title: descriptor.title,
            detail: text.detail,
            executedAt: audit.decidedAt,
            isUndoable: descriptor.isUndoable && executed,
            undoDeadline: audit.undoDeadline,
            beforeText: text.before,
            afterText: text.after
        )
    }

    private struct ReceiptText {
        let detail: String
        let before: String?
        let after: String?
    }

    private static func describe(_ proposal: ActionProposal) -> ReceiptText {
        switch proposal.kind {
        case .commitMemory:
            let content = (try? proposal.decodePayload(CommitMemoryPayload.self))?.memory.content ?? ""
            return ReceiptText(detail: "已保存记忆：\(String(content.prefix(40)))", before: nil, after: nil)
        case .retireMemory:
            return ReceiptText(detail: "已停用一条记忆", before: "生效中", after: "已停用")
        case .annotateWorkout:
            let raw = (try? proposal.decodePayload(AnnotateWorkoutPayload.self))?.rawText ?? ""
            return ReceiptText(detail: "已给训练补充标注：\(String(raw.prefix(30)))", before: nil, after: nil)
        case .logNutritionMeal:
            let payload = try? proposal.decodePayload(LogNutritionMealPayload.self)
            let day = payload?.dayKey.isoString ?? ""
            let name = payload?.entry.foodName ?? "一餐"
            return ReceiptText(detail: "已记录 \(day) 的 \(name)", before: nil, after: nil)
        case .logNutritionMeals:
            let payload = try? proposal.decodePayload(LogNutritionMealsPayload.self)
            let day = payload?.dayKey.isoString ?? ""
            let count = payload?.entries.count ?? 0
            return ReceiptText(detail: "已记录 \(day) 的 \(count) 条饮食", before: nil, after: nil)
        case .deleteNutritionMeal:
            let day = (try? proposal.decodePayload(DeleteNutritionMealPayload.self))?.dayKey.isoString ?? ""
            return ReceiptText(detail: "已删除 \(day) 的一条饮食记录", before: nil, after: nil)
        case .closeNutritionDay:
            let payload = try? proposal.decodePayload(CloseNutritionDayPayload.self)
            let day = payload?.dayKey.isoString ?? ""
            let complete = payload?.markComplete ?? true
            return ReceiptText(
                detail: "已结账 \(day) 的营养日",
                before: complete ? "未结账" : "已结账",
                after: complete ? "已结账" : "未结账"
            )
        case .adjustPlan:
            return ReceiptText(detail: "已修改训练计划", before: nil, after: nil)
        case .recordCheckIn:
            return ReceiptText(detail: "已记录今日打卡", before: nil, after: nil)
        case .upsertNutritionProfile:
            return ReceiptText(detail: "已修改营养档案", before: nil, after: nil)
        case .commitNutritionTargets:
            return ReceiptText(detail: "已修改营养目标", before: nil, after: nil)
        }
    }
}
