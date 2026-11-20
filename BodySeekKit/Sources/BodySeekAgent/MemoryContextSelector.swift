import BodySeekCore
import Foundation

public enum MemoryContextSelector {
    /// Returns active memories (neither retired nor expired as of `now`).
    public static func activeMemories(from records: [TieredMemoryRecord], now: Date) -> [TieredMemoryRecord] {
        records.filter { $0.isActive(at: now) }
    }

    /// Selects only prompt-relevant active memories across the 3 tiers:
    /// - `profile`: long-term goals / preferences
    /// - `activeConstraint`: expiring injury/schedule constraints
    /// - `verifiedPattern`: confirmed findings only
    public static func selectRelevant(
        query: String,
        memories: [TieredMemoryRecord],
        now: Date,
        maxCount: Int = 6
    ) -> [TieredMemoryRecord] {
        let active = activeMemories(from: memories, now: now)
        guard !active.isEmpty else { return [] }

        let q = query.lowercased()
        let queryDomains = detectDomains(in: q)

        struct ScoredMemory {
            let record: TieredMemoryRecord
            let score: Int
        }

        let scored: [ScoredMemory] = active.compactMap { rec in
            let text = rec.content.lowercased()
            let memDomains = detectDomains(in: text)
            let overlapCount = queryDomains.intersection(memDomains).count

            var score = overlapCount * 10
            if rec.tier == .activeConstraint && (queryDomains.contains(.training) || queryDomains.contains(.recovery)) {
                score += 6
            }
            if rec.tier == .verifiedPattern && overlapCount > 0 {
                score += 4
            }
            if queryDomains.isEmpty && rec.tier == .profile {
                score += 2
            }

            // Include directly matching domain memories; for general planning queries include high-priority constraints.
            guard score > 0 || (queryDomains.isEmpty && rec.tier != .verifiedPattern) else {
                return nil
            }
            return ScoredMemory(record: rec, score: score)
        }

        let sorted = scored.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return (lhs.record.confirmedAt ?? .distantPast) > (rhs.record.confirmedAt ?? .distantPast)
        }
        return Array(sorted.prefix(max(1, maxCount)).map(\.record))
    }

    /// Enforces V5 invariant: `verifiedPattern` memories may only be committed from a confirmed `pattern_finding`.
    public static func validateCandidateMemory(
        tier: MemoryTier,
        linkedPatternID: UUID?,
        confirmedFindings: [PatternFindingRecord]
    ) -> (allowed: Bool, reason: String?) {
        switch tier {
        case .profile, .activeConstraint:
            return (true, nil)
        case .verifiedPattern:
            guard let linkedPatternID else {
                return (false, "Verified Pattern 记忆必须关联已确认的 pattern_finding 记录")
            }
            let matched = confirmedFindings.contains { $0.id == linkedPatternID && $0.status == .confirmed }
            if matched {
                return (true, nil)
            }
            return (false, "找不到状态为 confirmed 的 pattern_finding（\(linkedPatternID.uuidString)），拒绝写入 Verified Pattern")
        }
    }

    public static func bridgeFromLegacy(_ items: [AthleteMemoryItem]) -> [TieredMemoryRecord] {
        items.map { item in
            let tier: MemoryTier = (item.category == .injury) ? .activeConstraint : .profile
            let expiresAt: Date? = (item.category == .injury) ? item.updatedAt.addingTimeInterval(14 * 86_400) : nil
            return TieredMemoryRecord(
                id: item.id,
                tier: tier,
                content: item.content,
                scopeJSON: "{\"category\":\"\(item.category.rawValue)\"}",
                confidence: 1.0,
                expiresAt: expiresAt,
                confirmedAt: item.updatedAt,
                retiredAt: nil
            )
        }
    }

    private enum TopicDomain: Hashable {
        case training
        case sleep
        case recovery
        case nutrition
        case injury
    }

    private static func detectDomains(in lower: String) -> Set<TopicDomain> {
        var domains = Set<TopicDomain>()
        let rules: [(TopicDomain, [String])] = [
            (.training, ["练", "训", "深蹲", "卧推", "硬拉", "跑步", "羽毛球", "负荷", "acwr", "肌群", "减量", "课表", "复盘", "rpe"]),
            (.injury, ["痛", "疼", "紧", "伤", "膝", "肩", "腰", "肘", "腕", "踝", "受限", "拉伤", "避免"]),
            (.sleep, ["睡", "入睡", "深睡", "rem", "清醒", "失眠", "熬夜", "作息", "晚睡"]),
            (.recovery, ["恢复", "hrv", "心率", "rhr", "压力", "精力", "能量", "疲", "酸痛"]),
            (.nutrition, ["吃", "食", "餐", "营养", "蛋白", "碳水", "热量", "kcal", "缺口", "盈余", "喝水", "咖啡", "酒"]),
        ]
        for (domain, keywords) in rules {
            if keywords.contains(where: { lower.contains($0) }) {
                domains.insert(domain)
                if domain == .injury {
                    domains.insert(.training)
                }
            }
        }
        return domains
    }
}
