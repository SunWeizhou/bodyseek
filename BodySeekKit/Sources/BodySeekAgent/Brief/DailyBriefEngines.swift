import BodySeekCore
import Foundation
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - 引擎选择

/// 一次生成里要依次尝试的引擎。
public enum BriefEngineChoice: Equatable, Sendable {
    /// 云端 OpenAI 兼容模型。
    case cloud(endpoint: String, model: String)
    /// Apple 端侧模型。
    case onDevice
    /// 本地模板（始终可用，永远排在最后）。
    case localTemplate

    /// 对应的引擎种类。
    public var engine: BriefEngine {
        switch self {
        case .cloud: .cloud
        case .onDevice: .onDevice
        case .localTemplate: .localTemplate
        }
    }
}

/// 引擎选择规则：云端优先，其次端侧，最后一定是本地模板。
public enum BriefEngineSelector {
    /// 返回按顺序尝试的引擎列表，最后一项永远是 `.localTemplate`。
    ///
    /// - 预览模式：只用本地模板，不碰网络。
    /// - 离线：跳过云端。
    /// - 没有 API Key：跳过云端。
    /// - 端侧模型不可用：跳过端侧。
    public static func candidates(
        isPreview: Bool,
        apiKey: String,
        endpoint: String,
        modelName: String,
        foundationModelsAvailable: Bool,
        isOnline: Bool
    ) -> [BriefEngineChoice] {
        if isPreview { return [.localTemplate] }
        var choices: [BriefEngineChoice] = []
        if isOnline {
            let route = AgentRoutingPolicy.resolve(
                isPreview: false,
                apiKey: apiKey,
                endpoint: endpoint,
                modelName: modelName,
                foundationModelsAvailable: false,
                intent: .briefing
            )
            if case let .cloudOpenAICompatible(resolvedEndpoint, resolvedModel) = route {
                choices.append(.cloud(endpoint: resolvedEndpoint, model: resolvedModel))
            }
        }
        if foundationModelsAvailable {
            choices.append(.onDevice)
        }
        choices.append(.localTemplate)
        return choices
    }
}

// MARK: - 错误

/// 简报引擎的失败原因。
public enum BriefEngineError: Error, LocalizedError, Equatable, Sendable {
    /// 引擎不可用。
    case unavailable(String)
    /// 模型输出无法解析成简报。
    case invalidOutput(String)
    /// 简报里有没有证据的数字。
    case unverifiedNumbers([String])

    public var errorDescription: String? {
        switch self {
        case let .unavailable(reason): "引擎不可用：\(reason)"
        case let .invalidOutput(reason): "模型输出无法解析：\(reason)"
        case let .unverifiedNumbers(tokens): "简报含未核实数字：\(tokens.joined(separator: "、"))"
        }
    }
}

// MARK: - 提示词与解析（云端、端侧共用）

/// 云端与端侧引擎共用的提示词与输出解析。
public enum BriefPrompt {
    /// 系统提示词。
    public static let system = """
    你是 BodySeek 的个人健康教练，为用户写今天的每日简报。
    只能使用「可用事实」里出现过的数字，不得编造、换算或推算新的数字；缺少数据就直说缺什么，不要补零。
    非医学诊断，不使用 HRV、ACWR、RPE 等缩写，用日常说法，简洁克制的中文。
    只输出一个 JSON 对象，不要任何其他文字，格式：
    {"headline":"一句话：现在怎么样","changes":[{"title":"","detail":""}],"actions":[{"title":"","detail":"","basis":"","coachPrompt":""}],"pageNotes":{"today":"","workout":"","nutrition":"","trends":"","coach":""}}
    changes 最多 2 条，actions 最多 2 条，每条 detail 不超过 40 字，pageNotes 每页不超过 60 字。
    """

    /// 用户提示词：把证据列成一行一条。
    public static func user(_ inputs: BriefInputs) -> String {
        var lines: [String] = ["今天是 \(inputs.dayKey.isoString)。", "可用事实："]
        if inputs.facts.isEmpty {
            lines.append("- （今天还没有可用的健康数据）")
        }
        for fact in inputs.facts {
            let title = MetricKind(rawValue: fact.metric)?.title ?? fact.metric
            lines.append("- \(title) \(format(fact.value)) \(unitLabel(fact.unit))（\(fact.scope)\(fact.dayKey.map { "，\($0)" } ?? "")）")
        }
        for key in inputs.contextNumbers.keys.sorted() {
            lines.append("- \(key) = \(format(inputs.contextNumbers[key] ?? 0))")
        }
        return lines.joined(separator: "\n")
    }

    /// 解析模型输出；失败抛 `invalidOutput`。
    public static func parse(
        _ raw: String,
        inputs: BriefInputs,
        engine: BriefEngine,
        generatedAt: Date
    ) throws -> DailyBrief {
        let scrubbed = ToolMarkupScrubber.scrub(raw).cleaned
        let cleaned = ToolMarkupScrubber.cleanJSONArguments(scrubbed)
        guard let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}"), start < end else {
            throw BriefEngineError.invalidOutput("没有找到 JSON 对象")
        }
        let json = String(cleaned[start ... end])
        let payload: RawBrief
        do {
            payload = try JSONDecoder().decode(RawBrief.self, from: Data(json.utf8))
        } catch {
            throw BriefEngineError.invalidOutput(error.localizedDescription)
        }
        let headline = payload.headline.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !headline.isEmpty else { throw BriefEngineError.invalidOutput("headline 为空") }

        let changes = (payload.changes ?? []).prefix(2).enumerated().map { index, item in
            BriefChange(id: "change-\(index)", title: item.title, detail: item.detail ?? "")
        }
        let actions = (payload.actions ?? []).prefix(2).enumerated().map { index, item in
            BriefAction(
                id: "action-\(index)",
                title: item.title,
                detail: item.detail ?? "",
                basis: item.basis ?? "",
                coachPrompt: item.coachPrompt ?? item.title
            )
        }
        var notes: [String: String] = [:]
        for page in BriefPage.allCases {
            if let text = payload.pageNotes?[page.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                notes[page.rawValue] = text
            }
        }
        return DailyBrief(
            dayKey: inputs.dayKey,
            generatedAt: generatedAt,
            modelInputsDigest: inputs.digest,
            engine: engine,
            headline: headline,
            changes: Array(changes),
            actions: Array(actions),
            pageNotes: notes
        )
    }

    private struct RawBrief: Decodable {
        struct Change: Decodable {
            let title: String
            let detail: String?
        }

        struct Action: Decodable {
            let title: String
            let detail: String?
            let basis: String?
            let coachPrompt: String?
        }

        let headline: String
        let changes: [Change]?
        let actions: [Action]?
        let pageNotes: [String: String]?
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func unitLabel(_ unit: String) -> String {
        switch unit {
        case "score_0_100": "分"
        case "minutes": "分钟"
        case "hours": "小时"
        default: unit
        }
    }
}

// MARK: - 云端与端侧引擎

/// 云端引擎：复用 `OpenAICompatibleClient`。
public struct CloudBriefEngine: Sendable {
    private let client: OpenAICompatibleClient
    private let endpoint: String
    private let model: String
    private let apiKey: String

    /// 创建云端引擎。
    public init(client: OpenAICompatibleClient, endpoint: String, model: String, apiKey: String) {
        self.client = client
        self.endpoint = endpoint
        self.model = model
        self.apiKey = apiKey
    }

    /// 生成简报；失败时抛错，由生成器回落。
    public func generate(inputs: BriefInputs, now: Date) async throws -> DailyBrief {
        let text = try await client.runSingleTurnTextCompletion(
            endpointURL: endpoint,
            apiKey: apiKey,
            modelName: model,
            systemPrompt: BriefPrompt.system,
            userPrompt: BriefPrompt.user(inputs),
            maxTokens: 900
        )
        return try BriefPrompt.parse(text, inputs: inputs, engine: .cloud, generatedAt: now)
    }
}

/// 端侧引擎：Apple Foundation Models。
public enum OnDeviceBriefEngine {
    /// 当前设备上端侧模型是否可用。
    public static func isAvailable() -> Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                return true
            }
        }
        #endif
        return false
    }

    /// 生成简报；不可用时抛 `unavailable`。
    public static func generate(inputs: BriefInputs, now: Date) async throws -> DailyBrief {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let session = LanguageModelSession(model: .default, instructions: BriefPrompt.system)
            let response = try await session.respond(to: BriefPrompt.user(inputs))
            return try BriefPrompt.parse(response.content, inputs: inputs, engine: .onDevice, generatedAt: now)
        }
        #endif
        throw BriefEngineError.unavailable("端侧 Apple 智能不可用")
    }
}

// MARK: - 本地模板引擎

/// 本地模板引擎：由 `TodayActionGenerator` 与 `ProactiveInsightEngine` 改造，离线也能生成。
/// 那两个类型本身保持不变。
public enum LocalTemplateBriefEngine {
    /// 生成简报。文字里的数字全部来自 `inputs.facts`；
    /// 来自 `TodayActionGenerator`、`ProactiveInsightEngine` 的句子逐条过数字校验，没有证据的整条丢弃。
    public static func generate(inputs: BriefInputs, now: Date) -> DailyBrief {
        guard inputs.isAuthorized else {
            return DailyBrief(
                dayKey: inputs.dayKey,
                generatedAt: now,
                modelInputsDigest: inputs.digest,
                engine: .localTemplate,
                headline: "连接 Apple 健康后生成每日简报",
                pageNotes: Dictionary(uniqueKeysWithValues: BriefPage.allCases.map { ($0.rawValue, "连接 Apple 健康后显示解读") })
            )
        }

        let planItems = TodayActionGenerator.generateDefaultPlanItems(for: inputs.snapshot, dayKey: inputs.dayKey)
        let actionItems = planItems.compactMap { $0.decodedActionItem() }
        let insights = ProactiveInsightEngine.generate(
            snapshot: inputs.snapshot,
            storedWorkouts: inputs.storedWorkouts,
            enabled: true,
            maxCount: 2
        )

        let changes: [BriefChange] = insights
            .map { BriefChange(id: $0.id, title: $0.title, detail: $0.body) }
            .filter { isVerified("\($0.title)\n\($0.detail)", inputs: inputs) }
        let actions: [BriefAction] = actionItems
            .prefix(2)
            .map {
                BriefAction(
                    id: $0.id.uuidString,
                    title: $0.title,
                    detail: $0.detail,
                    basis: $0.metricBasis,
                    coachPrompt: $0.coachPrompt
                )
            }
            .filter { isVerified("\($0.title)\n\($0.detail)\n\($0.basis)", inputs: inputs) }

        let headline = makeHeadline(inputs: inputs, actions: actions)
        let notes = makePageNotes(inputs: inputs, headline: headline)
        return DailyBrief(
            dayKey: inputs.dayKey,
            generatedAt: now,
            modelInputsDigest: inputs.digest,
            engine: .localTemplate,
            headline: headline,
            changes: changes,
            actions: actions,
            pageNotes: notes
        )
    }

    private static func isVerified(_ text: String, inputs: BriefInputs) -> Bool {
        NumericProvenanceVerifier.verify(responseText: text, toolOutputs: [inputs.provenanceJSON]).unverifiedTokens.isEmpty
    }

    private static func intText(_ fact: EvidenceFact?) -> String? {
        fact.map { String(Int($0.value.rounded())) }
    }

    private static func makeHeadline(inputs: BriefInputs, actions: [BriefAction]) -> String {
        let dayText = inputs.dayKey.isoString
        guard let recovery = intText(inputs.fact("score.recovery.\(dayText)")) else {
            return "今天的恢复数据还没同步，先按平时节奏安排。"
        }
        if let first = actions.first {
            return "恢复 \(recovery) 分：\(first.title)"
        }
        return "恢复 \(recovery) 分，今天按平时节奏安排。"
    }

    private static func makePageNotes(inputs: BriefInputs, headline: String) -> [String: String] {
        let dayText = inputs.dayKey.isoString
        var notes: [String: String] = [BriefPage.today.rawValue: headline]

        let zone = inputs.snapshot.trainingLoad.zone
        notes[BriefPage.workout.rawValue] = "近 7 天训练负荷：\(zone.title)。"

        if let kcal = intText(inputs.fact("nutrition.kcal.\(dayText)")) {
            notes[BriefPage.nutrition.rawValue] = "今天已记录摄入 \(kcal) kcal，记录完整后再看缺口。"
        } else {
            notes[BriefPage.nutrition.rawValue] = "今天还没有饮食记录。"
        }

        if let average = intText(inputs.fact("recovery.avg7d.\(dayText)")) {
            notes[BriefPage.trends.rawValue] = "近 7 天恢复平均 \(average) 分。"
        } else {
            notes[BriefPage.trends.rawValue] = "数据天数还不够，趋势解读需要至少 3 天恢复记录。"
        }

        notes[BriefPage.coach.rawValue] = "可以直接问我今天的恢复、睡眠和训练安排。"
        return notes
    }
}

// MARK: - 证据

/// 把简报里出现过的事实整理成 `EvidenceRef`。
public enum BriefEvidenceBuilder {
    /// 只收录数值真的出现在文字里的事实。
    public static func evidence(for brief: DailyBrief, facts: [EvidenceFact]) -> [EvidenceRef] {
        let text = brief.allUserText
        return facts.compactMap { fact in
            let candidates = numberTexts(fact.value)
            guard candidates.contains(where: { text.contains($0) }) else { return nil }
            let title = MetricKind(rawValue: fact.metric)?.title ?? fact.metric
            return EvidenceRef(
                kind: "metric",
                identifier: fact.key,
                summary: "\(title) \(candidates[0]) \(fact.unit)"
            )
        }
    }

    private static func numberTexts(_ value: Double) -> [String] {
        let integer = String(Int(value.rounded()))
        let decimal = String(format: "%.1f", value)
        return value == value.rounded() ? [integer] : [decimal, integer]
    }
}
