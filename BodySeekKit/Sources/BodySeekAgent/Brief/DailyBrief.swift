import BodySeekCore
import Foundation

/// 简报引擎（ADR 0021）：云端、端侧、本地模板。
public enum BriefEngine: String, Codable, Hashable, Sendable, CaseIterable {
    /// OpenAI 兼容云端模型。
    case cloud
    /// Apple Foundation Models 端侧模型。
    case onDevice
    /// 由 `TodayActionGenerator` 与 `ProactiveInsightEngine` 改造的本地模板；离线或模型不可用时使用。
    case localTemplate

    /// 面向用户的引擎名称。
    public var title: String {
        switch self {
        case .cloud: "云端模型"
        case .onDevice: "Apple 端侧模型"
        case .localTemplate: "本地规则"
        }
    }
}

/// 页面解读槽位对应的一级页面。用字符串键编码，避免枚举键字典在 JSON 里变成数组。
public enum BriefPage: String, Codable, Hashable, Sendable, CaseIterable {
    case today
    case workout
    case nutrition
    case trends
    case coach
}

/// 简报里"最近值得注意的变化"。
public struct BriefChange: Codable, Hashable, Sendable, Identifiable {
    /// 稳定标识。
    public let id: String
    /// 一句话标题。
    public let title: String
    /// 说明；其中的数字必须能在 `evidence` 里找到。
    public let detail: String

    /// 创建变化。
    public init(id: String, title: String, detail: String) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

/// 简报里"要不要行动"的一条建议。
public struct BriefAction: Codable, Hashable, Sendable, Identifiable {
    /// 稳定标识。
    public let id: String
    /// 建议标题。
    public let title: String
    /// 建议详情。
    public let detail: String
    /// 依据（来自证据的一句话）。
    public let basis: String
    /// 想追问时发给 Coach 的问题。
    public let coachPrompt: String

    /// 创建建议。
    public init(id: String, title: String, detail: String, basis: String, coachPrompt: String) {
        self.id = id
        self.title = title
        self.detail = detail
        self.basis = basis
        self.coachPrompt = coachPrompt
    }
}

/// 每日简报：唯一的结论对象。所有页面只引用它，不再各自产出结论。
public struct DailyBrief: Codable, Hashable, Sendable {
    /// 生理日。
    public let dayKey: DayKey
    /// 生成时间。
    public let generatedAt: Date
    /// 输入快照摘要；数据变化时摘要变化，旧简报即视为过期。
    public let modelInputsDigest: String
    /// 生成引擎。
    public let engine: BriefEngine
    /// 一句话：现在怎么样。
    public let headline: String
    /// 最近值得注意的变化。
    public let changes: [BriefChange]
    /// 要不要行动。
    public let actions: [BriefAction]
    /// 各页面解读槽位的文案，键是 `BriefPage.rawValue`。
    public let pageNotes: [String: String]
    /// 所有数字的溯源。
    public let evidence: [EvidenceRef]

    /// 创建简报。
    public init(
        dayKey: DayKey,
        generatedAt: Date,
        modelInputsDigest: String,
        engine: BriefEngine,
        headline: String,
        changes: [BriefChange] = [],
        actions: [BriefAction] = [],
        pageNotes: [String: String] = [:],
        evidence: [EvidenceRef] = []
    ) {
        self.dayKey = dayKey
        self.generatedAt = generatedAt
        self.modelInputsDigest = modelInputsDigest
        self.engine = engine
        self.headline = headline
        self.changes = changes
        self.actions = actions
        self.pageNotes = pageNotes
        self.evidence = evidence
    }

    /// 某一页的解读文案；没有专门文案时退回一句话结论。
    public func note(for page: BriefPage) -> String {
        let text = pageNotes[page.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? headline : text
    }

    /// 简报里所有面向用户的文字，用于数字溯源校验。
    public var allUserText: String {
        var parts: [String] = [headline]
        parts += changes.flatMap { [$0.title, $0.detail] }
        parts += actions.flatMap { [$0.title, $0.detail, $0.basis] }
        parts += BriefPage.allCases.compactMap { pageNotes[$0.rawValue] }
        return parts.joined(separator: "\n")
    }

    /// 替换证据，其余不变。
    public func withEvidence(_ evidence: [EvidenceRef]) -> DailyBrief {
        DailyBrief(
            dayKey: dayKey,
            generatedAt: generatedAt,
            modelInputsDigest: modelInputsDigest,
            engine: engine,
            headline: headline,
            changes: changes,
            actions: actions,
            pageNotes: pageNotes,
            evidence: evidence
        )
    }
}
