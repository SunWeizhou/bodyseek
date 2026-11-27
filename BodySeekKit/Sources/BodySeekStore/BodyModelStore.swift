import BodySeekCore
import Foundation
import GRDB
import os

/// 身体模型"有没有变"的指纹：只覆盖动作层会写的业务表，不含高频的健康指标表
/// （健康指标由 `BodySeekReadModel.observeDashboard` 负责）。
public struct BodyModelRevision: Equatable, Hashable, Sendable {
    /// 记忆总数。
    public let memoryCount: Int
    /// 记忆最近的确认 / 停用时间戳之和；保存、停用、撤销都会让它变化。
    public let memoryStamp: Double
    /// 审计总数。
    public let auditCount: Int
    /// 最近一次审计时间。
    public let lastAuditAt: Double
    /// 营养日志天数。
    public let nutritionLogCount: Int
    /// 营养日志最近更新时间。
    public let nutritionStamp: Double
    /// 计划项的状态摘要（数量、id、状态拼接）。
    public let planItemDigest: String
    /// 打卡总数。
    public let checkInCount: Int
    /// 每日简报最近生成时间。
    public let briefStamp: Double
    /// 训练标注总数；标注和撤销标注都会让它变化。
    public let annotationCount: Int

    /// 创建指纹。
    public init(
        memoryCount: Int,
        memoryStamp: Double,
        auditCount: Int,
        lastAuditAt: Double,
        nutritionLogCount: Int,
        nutritionStamp: Double,
        planItemDigest: String,
        checkInCount: Int,
        briefStamp: Double,
        annotationCount: Int = 0
    ) {
        self.memoryCount = memoryCount
        self.memoryStamp = memoryStamp
        self.auditCount = auditCount
        self.lastAuditAt = lastAuditAt
        self.nutritionLogCount = nutritionLogCount
        self.nutritionStamp = nutritionStamp
        self.planItemDigest = planItemDigest
        self.checkInCount = checkInCount
        self.briefStamp = briefStamp
        self.annotationCount = annotationCount
    }
}

/// 身体模型的只读快照：由数据库观察广播，页面只读，不通过它写入。
public struct BodyModelSnapshot: Equatable, Sendable {
    /// 变化指纹。
    public let revision: BodyModelRevision
    /// 生效中的记忆。
    public let activeMemories: [TieredMemoryRecord]
    /// 最近由动作层执行的审计（新的在前，最多 20 条）。
    public let recentActions: [ActionAuditEntry]

    /// 创建快照。
    public init(revision: BodyModelRevision, activeMemories: [TieredMemoryRecord], recentActions: [ActionAuditEntry]) {
        self.revision = revision
        self.activeMemories = activeMemories
        self.recentActions = recentActions
    }
}

/// 用 GRDB `ValueObservation` 广播身体模型的只读快照。
///
/// 放在 `BodySeekStore` 而不是 `BodySeekFeatures`：它只依赖 Core 与 GRDB，
/// 依赖方向是 Core ← Store ← Health ← Agent ← Features；Features 通过
/// `BodySeekStoreClient.observeBodyModel` 订阅，不直接接触 GRDB。
public final class BodyModelStore: Sendable {
    /// 底层数据库。
    public let database: BodySeekDatabase
    private static let logger = Logger(subsystem: "com.sunweizhou.Vela4", category: "BodyModelStore")

    /// 创建存储。
    public init(database: BodySeekDatabase) {
        self.database = database
    }

    /// 读取当前快照。
    public func current() async throws -> BodyModelSnapshot {
        try await database.writer.read { db in
            try Self.loadSync(db)
        }
    }

    /// 订阅快照；业务表变化且指纹不同才会发出新值，第一个值是当前状态。
    public func observe() -> AsyncThrowingStream<BodyModelSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let observation = ValueObservation
                    .tracking { db in try Self.loadSync(db) }
                    .removeDuplicates()
                do {
                    for try await snapshot in observation.values(in: database.writer) {
                        continuation.yield(snapshot)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    Self.logger.error("BodyModel ValueObservation failed: \(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    static func loadSync(_ db: Database) throws -> BodyModelSnapshot {
        let revision = try loadRevision(db)
        let memoryRows = try Row.fetchAll(
            db,
            sql: """
            SELECT id, tier, content, scope_json, confidence, expires_at, confirmed_at, retired_at
            FROM memory WHERE retired_at IS NULL ORDER BY confirmed_at DESC
            """
        )
        let memories = memoryRows.compactMap(decodeMemory)
        let auditRows = try Row.fetchAll(
            db,
            sql: """
            SELECT * FROM action_audit
            WHERE decision = ? AND risk_level IS NOT NULL
            ORDER BY decided_at DESC LIMIT 20
            """,
            arguments: [ActionAuditDecision.applied.rawValue]
        )
        let audits = try auditRows.compactMap(BodySeekRepository.decodeAuditEntry)
        return BodyModelSnapshot(revision: revision, activeMemories: memories, recentActions: audits)
    }

    private static func loadRevision(_ db: Database) throws -> BodyModelRevision {
        let memoryCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM memory") ?? 0
        let memoryConfirmed = try Double.fetchOne(db, sql: "SELECT COALESCE(MAX(confirmed_at), 0) FROM memory") ?? 0
        let memoryRetired = try Double.fetchOne(db, sql: "SELECT COALESCE(MAX(retired_at), 0) FROM memory") ?? 0
        let auditCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM action_audit") ?? 0
        let lastAudit = try Double.fetchOne(db, sql: "SELECT COALESCE(MAX(decided_at), 0) FROM action_audit") ?? 0
        let nutritionCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM daily_nutrition_log") ?? 0
        let nutritionStamp = try Double.fetchOne(db, sql: "SELECT COALESCE(MAX(updated_at), 0) FROM daily_nutrition_log") ?? 0
        let planDigest = try String.fetchOne(
            db,
            sql: "SELECT COALESCE(group_concat(id || ':' || state, ','), '') FROM (SELECT id, state FROM plan_item ORDER BY id)"
        ) ?? ""
        let checkInCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM check_in") ?? 0
        let briefStamp = try Double.fetchOne(db, sql: "SELECT COALESCE(MAX(generated_at), 0) FROM daily_brief") ?? 0
        let annotationCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workout_annotation") ?? 0
        return BodyModelRevision(
            memoryCount: memoryCount,
            memoryStamp: memoryConfirmed + memoryRetired,
            auditCount: auditCount,
            lastAuditAt: lastAudit,
            nutritionLogCount: nutritionCount,
            nutritionStamp: nutritionStamp,
            planItemDigest: planDigest,
            checkInCount: checkInCount,
            briefStamp: briefStamp,
            annotationCount: annotationCount
        )
    }

    private static func decodeMemory(_ row: Row) -> TieredMemoryRecord? {
        guard let id = UUID(uuidString: row["id"]),
              let tier = MemoryTier(rawValue: row["tier"])
        else { return nil }
        let expires: Double? = row["expires_at"]
        let confirmed: Double? = row["confirmed_at"]
        let retired: Double? = row["retired_at"]
        return TieredMemoryRecord(
            id: id,
            tier: tier,
            content: row["content"],
            scopeJSON: row["scope_json"],
            confidence: row["confidence"],
            expiresAt: expires.map(Date.init(timeIntervalSince1970:)),
            confirmedAt: confirmed.map(Date.init(timeIntervalSince1970:)),
            retiredAt: retired.map(Date.init(timeIntervalSince1970:))
        )
    }
}
