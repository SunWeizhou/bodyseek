import BodySeekCore
import BodySeekHealth
import BodySeekStore
import Dependencies
import DependenciesMacros
import Foundation
import os

// MARK: - 缓存存取

/// 简报缓存与反馈的存取；生产环境由 `BodySeekRepository` 实现，测试可以替换。
public protocol DailyBriefStoring: Sendable {
    /// 读取某个输入摘要对应的简报。
    func load(dayKey: DayKey, digest: String) async throws -> DailyBriefRecord?
    /// 读取某一天最新的简报（不论是否过期）。
    func latest(dayKey: DayKey) async throws -> DailyBriefRecord?
    /// 把某一天的所有简报标记为过期。
    func markStale(dayKey: DayKey) async throws
    /// 保存简报。
    func save(_ record: DailyBriefRecord) async throws
    /// 保存反馈。
    func saveFeedback(_ record: BriefFeedbackRecord) async throws
}

/// `daily_brief` / `brief_feedback` 表上的实现（`BodySeekRepository+Brief`）。
public struct RepositoryBriefStore: DailyBriefStoring {
    private let repository: BodySeekRepository

    /// 创建存取。
    public init(repository: BodySeekRepository) {
        self.repository = repository
    }

    public func load(dayKey: DayKey, digest: String) async throws -> DailyBriefRecord? {
        try await repository.loadDailyBrief(dayKey: dayKey, inputsDigest: digest)
    }

    public func latest(dayKey: DayKey) async throws -> DailyBriefRecord? {
        try await repository.loadLatestDailyBrief(dayKey: dayKey)
    }

    public func markStale(dayKey: DayKey) async throws {
        try await repository.markDailyBriefsStale(dayKey: dayKey)
    }

    public func save(_ record: DailyBriefRecord) async throws {
        try await repository.saveDailyBrief(record)
    }

    public func saveFeedback(_ record: BriefFeedbackRecord) async throws {
        try await repository.saveBriefFeedback(record)
    }
}

/// 不落库的存取：预览模式、测试默认值使用。
public struct NoopBriefStore: DailyBriefStoring {
    /// 创建空存取。
    public init() {}
    public func load(dayKey: DayKey, digest: String) async throws -> DailyBriefRecord? { nil }
    public func latest(dayKey: DayKey) async throws -> DailyBriefRecord? { nil }
    public func markStale(dayKey: DayKey) async throws {}
    public func save(_ record: DailyBriefRecord) async throws {}
    public func saveFeedback(_ record: BriefFeedbackRecord) async throws {}
}

// MARK: - 结果

/// 一次取简报的结果。
public struct DailyBriefResult: Equatable, Sendable {
    /// 简报来源。
    public enum Source: String, Equatable, Sendable {
        /// 输入没变，直接用缓存。
        case cacheHit
        /// 重新生成。
        case generated
    }

    /// 简报。
    public let brief: DailyBrief
    /// 来源。
    public let source: Source
    /// 排在前面但失败了的引擎，以及原因（用于解释为什么回落）。
    public let fallbacks: [String]

    /// 创建结果。
    public init(brief: DailyBrief, source: Source, fallbacks: [String] = []) {
        self.brief = brief
        self.source = source
        self.fallbacks = fallbacks
    }
}

// MARK: - 校验

/// 简报里每个数字都要能在证据里找到。
public enum DailyBriefVerifier {
    /// 返回没有证据的数字片段；空数组表示全部通过。
    public static func unverifiedNumbers(in brief: DailyBrief, inputs: BriefInputs) -> [String] {
        NumericProvenanceVerifier.verify(
            responseText: brief.allUserText,
            toolOutputs: [inputs.provenanceJSON]
        ).unverifiedTokens
    }
}

// MARK: - 生成器

/// 每日简报生成器：先查缓存，未命中再按引擎顺序生成；云端 / 端侧失败或含未核实数字时回落，最后一定有本地模板。
public struct DailyBriefGenerator: Sendable {
    /// 运行一个引擎。
    public typealias EngineRunner = @Sendable (BriefEngineChoice, BriefInputs, Date) async throws -> DailyBrief

    private let store: any DailyBriefStoring
    private let run: EngineRunner
    private static let logger = Logger(subsystem: "com.sunweizhou.Vela4", category: "DailyBriefGenerator")

    /// 创建生成器。`run` 默认只会处理本地模板；云端、端侧由调用方注入。
    public init(store: any DailyBriefStoring, run: @escaping EngineRunner) {
        self.store = store
        self.run = run
    }

    /// 取今天的简报。
    /// - Parameters:
    ///   - inputs: 输入快照。
    ///   - choices: 引擎顺序；缺少 `.localTemplate` 时自动补在最后。
    ///   - forceRefresh: 忽略缓存强制重新生成（用户手动刷新）。
    ///   - now: 当前时间。
    public func resolve(
        inputs: BriefInputs,
        choices: [BriefEngineChoice],
        forceRefresh: Bool = false,
        now: Date = Date()
    ) async -> DailyBriefResult {
        if !forceRefresh, let cached = await cachedBrief(inputs: inputs) {
            return DailyBriefResult(brief: cached, source: .cacheHit)
        }

        var ordered = choices
        if !ordered.contains(.localTemplate) { ordered.append(.localTemplate) }
        var fallbacks: [String] = []
        var chosen: DailyBrief?

        for choice in ordered {
            do {
                let candidate = try await run(choice, inputs, now)
                if choice != .localTemplate {
                    let unverified = DailyBriefVerifier.unverifiedNumbers(in: candidate, inputs: inputs)
                    if !unverified.isEmpty { throw BriefEngineError.unverifiedNumbers(unverified) }
                }
                chosen = candidate.withEvidence(BriefEvidenceBuilder.evidence(for: candidate, facts: inputs.facts))
                break
            } catch {
                Self.logger.warning("Brief engine \(choice.engine.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                fallbacks.append("\(choice.engine.title)：\(error.localizedDescription)")
            }
        }

        let brief = chosen ?? LocalTemplateBriefEngine
            .generate(inputs: inputs, now: now)
            .withEvidence([])
        await persist(brief)
        return DailyBriefResult(brief: brief, source: .generated, fallbacks: fallbacks)
    }

    /// 读取某天最新简报（含已过期的），页面先显示它，同时后台重新生成。
    public func latest(dayKey: DayKey) async -> (brief: DailyBrief, isStale: Bool)? {
        do {
            guard let record = try await store.latest(dayKey: dayKey),
                  let brief = Self.decode(record)
            else { return nil }
            return (brief, record.isStale)
        } catch {
            Self.logger.error("Failed loading latest brief: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 写入简报反馈：准 / 不准 / 没用。
    public func submitFeedback(
        _ rating: BriefFeedbackRating,
        dayKey: DayKey,
        note: String? = nil,
        now: Date = Date()
    ) async throws {
        try await store.saveFeedback(BriefFeedbackRecord(dayKey: dayKey, rating: rating, createdAt: now, note: note))
    }

    private func cachedBrief(inputs: BriefInputs) async -> DailyBrief? {
        do {
            guard let record = try await store.load(dayKey: inputs.dayKey, digest: inputs.digest),
                  !record.isStale,
                  let brief = Self.decode(record)
            else { return nil }
            return brief
        } catch {
            Self.logger.error("Failed reading brief cache: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func persist(_ brief: DailyBrief) async {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(brief)
            guard let json = String(data: data, encoding: .utf8) else { return }
            // 输入变化：先把这一天已有的简报标记为过期，再保存新的。
            try await store.markStale(dayKey: brief.dayKey)
            try await store.save(DailyBriefRecord(
                dayKey: brief.dayKey,
                inputsDigest: brief.modelInputsDigest,
                generatedAt: brief.generatedAt,
                engine: brief.engine.rawValue,
                headline: brief.headline,
                payloadJSON: json,
                isStale: false
            ))
        } catch {
            Self.logger.error("Failed persisting brief: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func decode(_ record: DailyBriefRecord) -> DailyBrief? {
        try? JSONDecoder().decode(DailyBrief.self, from: Data(record.payloadJSON.utf8))
    }
}

// MARK: - 依赖客户端

/// 页面取简报的入口：云端 / 端侧 / 本地模板的选择、缓存、反馈都在里面。
@DependencyClient
public struct DailyBriefClient: Sendable {
    /// 取今天的简报；`forceRefresh` 为真时忽略缓存。
    public var current: @Sendable (_ context: AgentExecutionContext, _ forceRefresh: Bool) async -> DailyBriefResult = { context, _ in
        let inputs = BriefInputs.make(from: context)
        let brief = LocalTemplateBriefEngine.generate(inputs: inputs, now: context.asOf)
        return DailyBriefResult(brief: brief.withEvidence(BriefEvidenceBuilder.evidence(for: brief, facts: inputs.facts)), source: .generated)
    }

    /// 读取某天最新简报（含已过期的）。
    public var latest: @Sendable (_ dayKey: DayKey) async -> (brief: DailyBrief, isStale: Bool)? = { _ in nil }

    /// 写入反馈：准 / 不准 / 没用。
    public var submitFeedback: @Sendable (_ rating: BriefFeedbackRating, _ dayKey: DayKey) async throws -> Void = { _, _ in }
}

extension DailyBriefClient: DependencyKey {
    public static let liveValue: DailyBriefClient = {
        let httpClient = OpenAICompatibleClient()
        return DailyBriefClient(
            current: { context, forceRefresh in
                let isPreview = ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard")
                let generator = await makeGenerator(isPreview: isPreview, client: httpClient)
                let inputs = BriefInputs.make(from: context)
                let choices = selectChoices(isPreview: isPreview)
                return await generator.resolve(
                    inputs: inputs,
                    choices: choices,
                    forceRefresh: forceRefresh,
                    now: context.asOf
                )
            },
            latest: { dayKey in
                let isPreview = ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard")
                let generator = await makeGenerator(isPreview: isPreview, client: httpClient)
                return await generator.latest(dayKey: dayKey)
            },
            submitFeedback: { rating, dayKey in
                let isPreview = ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard")
                let generator = await makeGenerator(isPreview: isPreview, client: httpClient)
                try await generator.submitFeedback(rating, dayKey: dayKey)
            }
        )
    }()

    public static let testValue = DailyBriefClient()
    public static let previewValue = DailyBriefClient()

    private static func makeGenerator(isPreview: Bool, client: OpenAICompatibleClient) async -> DailyBriefGenerator {
        let store: any DailyBriefStoring
        if isPreview {
            store = NoopBriefStore()
        } else {
            do {
                store = RepositoryBriefStore(repository: try await BodySeekSharedStore.shared.repository())
            } catch {
                store = NoopBriefStore()
            }
        }
        return DailyBriefGenerator(store: store) { choice, inputs, now in
            switch choice {
            case let .cloud(endpoint, model):
                let apiKey = try KeychainCredentialStore.live.loadAPIKey()
                return try await CloudBriefEngine(client: client, endpoint: endpoint, model: model, apiKey: apiKey)
                    .generate(inputs: inputs, now: now)
            case .onDevice:
                return try await OnDeviceBriefEngine.generate(inputs: inputs, now: now)
            case .localTemplate:
                return LocalTemplateBriefEngine.generate(inputs: inputs, now: now)
            }
        }
    }

    private static func selectChoices(isPreview: Bool) -> [BriefEngineChoice] {
        var apiKey = ""
        do {
            apiKey = try KeychainCredentialStore.live.loadAPIKey()
        } catch {
            apiKey = ""
        }
        let defaults = UserDefaults.standard
        return BriefEngineSelector.candidates(
            isPreview: isPreview,
            apiKey: apiKey,
            endpoint: defaults.string(forKey: CoachAIClient.endpointStorageKey) ?? "https://api.deepseek.com/v1",
            modelName: defaults.string(forKey: CoachAIClient.modelStorageKey) ?? "deepseek-chat",
            foundationModelsAvailable: OnDeviceBriefEngine.isAvailable(),
            isOnline: true
        )
    }
}

public extension DependencyValues {
    var dailyBriefClient: DailyBriefClient {
        get { self[DailyBriefClient.self] }
        set { self[DailyBriefClient.self] = newValue }
    }
}
