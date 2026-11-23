import BodySeekCore
import CryptoKit
import Foundation

/// 生成简报用的输入：从 `AgentExecutionContext` 提取，保证每个能写进简报的数字都有类型化的证据。
public struct BriefInputs: Sendable, Equatable {
    /// 生理日。
    public let dayKey: DayKey
    /// 参考时间。
    public let referenceDate: Date
    /// 是否已连接健康数据。
    public let isAuthorized: Bool
    /// 类型化证据：数值、单位、指标、日期。
    public let facts: [EvidenceFact]
    /// 非类型化的上下文数字（例如 ACWR 比值），只作为"允许出现的数字"。
    public let contextNumbers: [String: Double]
    /// 数据快照，本地模板引擎用。
    public let snapshot: BodySeekDashboardSnapshot
    /// 训练记录，主动洞察用。
    public let storedWorkouts: [StoredWorkoutRecord]
    /// 生效中的记忆标识，参与摘要。
    public let activeMemoryIDs: [String]
    /// 输入快照摘要：任一事实、记忆、训练复盘状态变化，摘要就会变化。
    public let digest: String

    /// 从 Agent 上下文提取输入。
    public static func make(from context: AgentExecutionContext) -> BriefInputs {
        let snapshot = context.snapshot
        let today = snapshot.today
        let dayText = today.dayKey.isoString
        var facts: [EvidenceFact] = []

        for kind in MetricKind.allCases {
            guard let value = today.score(for: kind).value else { continue }
            facts.append(EvidenceFact(
                key: "score.\(kind.rawValue).\(dayText)",
                value: Double(value),
                unit: "score_0_100",
                metric: kind.rawValue,
                scope: "day",
                dayKey: dayText
            ))
        }
        if let hrv = today.raw.hrvMs {
            facts.append(EvidenceFact(key: "hrv.\(dayText)", value: rounded(hrv), unit: "ms", metric: "hrv", scope: "day", dayKey: dayText))
        }
        if let rhr = today.raw.restingHeartRateBpm {
            facts.append(EvidenceFact(
                key: "rhr.\(dayText)", value: rounded(rhr), unit: "bpm", metric: "resting_heart_rate", scope: "day", dayKey: dayText
            ))
        }
        if let minutes = today.raw.sleepAsleepMinutes {
            facts.append(EvidenceFact(
                key: "sleep.minutes.\(dayText)", value: Double(minutes), unit: "minutes", metric: "sleep_asleep", scope: "day", dayKey: dayText
            ))
            facts.append(EvidenceFact(
                key: "sleep.hours.\(dayText)", value: rounded(Double(minutes) / 60.0), unit: "hours", metric: "sleep_asleep", scope: "day", dayKey: dayText
            ))
        }
        let recent = snapshot.historyDays.suffix(7).compactMap { $0.recovery.value }
        if recent.count >= 3 {
            let average = Double(recent.reduce(0, +)) / Double(recent.count)
            facts.append(EvidenceFact(
                key: "recovery.avg7d.\(dayText)", value: average.rounded(), unit: "score_0_100", metric: "recovery", scope: "7d", dayKey: nil
            ))
        }
        if let log = context.todayNutritionLog, let kcal = log.dietKcal {
            facts.append(EvidenceFact(
                key: "nutrition.kcal.\(dayText)", value: kcal.rounded(), unit: "kcal", metric: "nutrition_kcal", scope: "day", dayKey: log.dayKey.isoString
            ))
        }

        var contextNumbers: [String: Double] = [:]
        if let acwr = snapshot.trainingLoad.acwrRatio { contextNumbers["acwrRatio"] = rounded(acwr, places: 2) }
        contextNumbers["acute7dLoad"] = snapshot.trainingLoad.acute7dLoad.rounded()

        let memoryIDs = MemoryContextSelector
            .activeMemories(from: context.tieredMemories, now: context.asOf)
            .map { $0.id.uuidString }
            .sorted()
        let sortedFacts = facts.sorted { $0.key < $1.key }
        return BriefInputs(
            dayKey: today.dayKey,
            referenceDate: snapshot.referenceDate,
            isAuthorized: snapshot.isAuthorized,
            facts: sortedFacts,
            contextNumbers: contextNumbers,
            snapshot: snapshot,
            storedWorkouts: context.storedWorkouts,
            activeMemoryIDs: memoryIDs,
            digest: computeDigest(
                dayKey: today.dayKey,
                isAuthorized: snapshot.isAuthorized,
                facts: sortedFacts,
                contextNumbers: contextNumbers,
                memoryIDs: memoryIDs,
                workouts: context.storedWorkouts
            )
        )
    }

    /// 给引擎和校验器用的"工具输出"JSON：`evidence` 是类型化证据，`context` 是只允许出现的数字。
    public var provenanceJSON: String {
        struct Envelope: Encodable {
            let evidence: [EvidenceFact]
            let context: [String: Double]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(Envelope(evidence: facts, context: contextNumbers)),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    /// 查找证据；`key` 精确匹配。
    public func fact(_ key: String) -> EvidenceFact? {
        facts.first { $0.key == key }
    }

    public static func == (lhs: BriefInputs, rhs: BriefInputs) -> Bool {
        lhs.digest == rhs.digest && lhs.dayKey == rhs.dayKey
    }

    private static func rounded(_ value: Double, places: Int = 1) -> Double {
        let scale = pow(10.0, Double(places))
        return (value * scale).rounded() / scale
    }

    private static func computeDigest(
        dayKey: DayKey,
        isAuthorized: Bool,
        facts: [EvidenceFact],
        contextNumbers: [String: Double],
        memoryIDs: [String],
        workouts: [StoredWorkoutRecord]
    ) -> String {
        var lines: [String] = ["day=\(dayKey.isoString)", "auth=\(isAuthorized)"]
        lines += facts.map { "fact=\($0.key):\(String(format: "%.2f", $0.value)):\($0.unit)" }
        lines += contextNumbers.keys.sorted().map { "ctx=\($0):\(String(format: "%.2f", contextNumbers[$0] ?? 0))" }
        lines += memoryIDs.map { "mem=\($0)" }
        lines += workouts.map { "wk=\($0.hkUUID.lowercased()):\($0.reviewState.rawValue)" }.sorted()
        let data = Data(lines.joined(separator: "\n").utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
