import BodySeekCore
import Foundation
import GRDB

/// `daily_brief` 表的一行（ADR 0021）。`payloadJSON` 由 BodySeekAgent 的 `DailyBrief` 编码，存储层不解析它。
public struct DailyBriefRecord: Equatable, Hashable, Sendable {
    /// 生理日。
    public let dayKey: DayKey
    /// 输入快照摘要；输入变化时摘要变化，旧简报即视为过期。
    public let inputsDigest: String
    /// 生成时间。
    public let generatedAt: Date
    /// 生成引擎：`cloud` / `onDevice` / `localTemplate`。
    public let engine: String
    /// 一句话结论，与 `payloadJSON` 里的 headline 一致，方便不解码就能显示。
    public let headline: String
    /// 完整简报的 JSON。
    public let payloadJSON: String
    /// 是否已被标记为过期。
    public let isStale: Bool

    /// 创建一行简报记录。
    public init(
        dayKey: DayKey,
        inputsDigest: String,
        generatedAt: Date,
        engine: String,
        headline: String,
        payloadJSON: String,
        isStale: Bool = false
    ) {
        self.dayKey = dayKey
        self.inputsDigest = inputsDigest
        self.generatedAt = generatedAt
        self.engine = engine
        self.headline = headline
        self.payloadJSON = payloadJSON
        self.isStale = isStale
    }
}

/// 简报反馈：准 / 不准 / 没用。
public enum BriefFeedbackRating: String, Sendable, Codable, CaseIterable {
    /// 准。
    case accurate
    /// 不准。
    case inaccurate
    /// 没用。
    case useless
}

/// `brief_feedback` 表的一行。
public struct BriefFeedbackRecord: Identifiable, Equatable, Hashable, Sendable {
    /// 记录标识。
    public let id: UUID
    /// 被评价的简报所在的生理日。
    public let dayKey: DayKey
    /// 评价。
    public let rating: BriefFeedbackRating
    /// 评价时间。
    public let createdAt: Date
    /// 可选备注。
    public let note: String?

    /// 创建一条反馈。
    public init(
        id: UUID = UUID(),
        dayKey: DayKey,
        rating: BriefFeedbackRating,
        createdAt: Date = Date(),
        note: String? = nil
    ) {
        self.id = id
        self.dayKey = dayKey
        self.rating = rating
        self.createdAt = createdAt
        self.note = note
    }
}

public extension BodySeekRepository {
    /// 保存简报；同一 `dayKey` + `inputsDigest` 已存在时覆盖。
    func saveDailyBrief(_ record: DailyBriefRecord) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO daily_brief (day_key, inputs_digest, generated_at, engine, headline, payload_json, is_stale)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(day_key, inputs_digest) DO UPDATE SET
                    generated_at = excluded.generated_at,
                    engine = excluded.engine,
                    headline = excluded.headline,
                    payload_json = excluded.payload_json,
                    is_stale = excluded.is_stale
                """,
                arguments: [
                    record.dayKey.isoString,
                    record.inputsDigest,
                    record.generatedAt.timeIntervalSince1970,
                    record.engine,
                    record.headline,
                    record.payloadJSON,
                    record.isStale ? 1 : 0,
                ]
            )
        }
    }

    /// 读取指定输入摘要对应的简报。
    func loadDailyBrief(dayKey: DayKey, inputsDigest: String) async throws -> DailyBriefRecord? {
        try await database.writer.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                SELECT day_key, inputs_digest, generated_at, engine, headline, payload_json, is_stale
                FROM daily_brief WHERE day_key = ? AND inputs_digest = ?
                """,
                arguments: [dayKey.isoString, inputsDigest]
            )
            return row.flatMap { Self.decodeDailyBrief($0) }
        }
    }

    /// 读取某一天最新生成的简报（不论是否过期）。
    func loadLatestDailyBrief(dayKey: DayKey) async throws -> DailyBriefRecord? {
        try await database.writer.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                SELECT day_key, inputs_digest, generated_at, engine, headline, payload_json, is_stale
                FROM daily_brief WHERE day_key = ? ORDER BY generated_at DESC LIMIT 1
                """,
                arguments: [dayKey.isoString]
            )
            return row.flatMap { Self.decodeDailyBrief($0) }
        }
    }

    /// 把某一天的所有简报标记为过期（数据变化时调用）。
    func markDailyBriefsStale(dayKey: DayKey) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: "UPDATE daily_brief SET is_stale = 1 WHERE day_key = ?",
                arguments: [dayKey.isoString]
            )
        }
    }

    /// 保存一条简报反馈。
    func saveBriefFeedback(_ record: BriefFeedbackRecord) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO brief_feedback (id, day_key, rating, created_at, note)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [
                    record.id.uuidString,
                    record.dayKey.isoString,
                    record.rating.rawValue,
                    record.createdAt.timeIntervalSince1970,
                    record.note,
                ]
            )
        }
    }

    /// 读取反馈，按时间从新到旧。`since` 为 `nil` 时读取全部。
    func loadBriefFeedback(since: Date? = nil) async throws -> [BriefFeedbackRecord] {
        let cutoff = since?.timeIntervalSince1970 ?? 0
        return try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, day_key, rating, created_at, note
                FROM brief_feedback WHERE created_at >= ? ORDER BY created_at DESC
                """,
                arguments: [cutoff]
            )
            return rows.compactMap { Self.decodeBriefFeedback($0) }
        }
    }

    private static func decodeDailyBrief(_ row: Row) -> DailyBriefRecord? {
        let dayText: String = row["day_key"]
        guard let dayKey = DayKey(isoString: dayText) else { return nil }
        let generatedAt: Double = row["generated_at"]
        let stale: Int = row["is_stale"]
        return DailyBriefRecord(
            dayKey: dayKey,
            inputsDigest: row["inputs_digest"],
            generatedAt: Date(timeIntervalSince1970: generatedAt),
            engine: row["engine"],
            headline: row["headline"],
            payloadJSON: row["payload_json"],
            isStale: stale != 0
        )
    }

    private static func decodeBriefFeedback(_ row: Row) -> BriefFeedbackRecord? {
        let idText: String = row["id"]
        let dayText: String = row["day_key"]
        let ratingText: String = row["rating"]
        guard let id = UUID(uuidString: idText),
              let dayKey = DayKey(isoString: dayText),
              let rating = BriefFeedbackRating(rawValue: ratingText)
        else { return nil }
        let createdAt: Double = row["created_at"]
        return BriefFeedbackRecord(
            id: id,
            dayKey: dayKey,
            rating: rating,
            createdAt: Date(timeIntervalSince1970: createdAt),
            note: row["note"]
        )
    }
}
