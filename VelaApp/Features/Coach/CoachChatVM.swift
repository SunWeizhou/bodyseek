import SwiftUI
import SwiftData
import UIKit

// MARK: - Shared Types

enum CoachScreenSurface: String, Codable, Hashable, Sendable {
    case coach
    case home
    case trends
    case plan
    case metricDetail = "metric_detail"
    case workoutDetail = "workout_detail"
    case journal
    case nutrition
    case biology
    case training
}

struct CoachScreenContext: Codable, Hashable, Sendable {
    var surface: CoachScreenSurface
    var entityType: String? = nil
    var selectedDate: Date? = nil

    func json() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

struct CoachContextFocus: Hashable, Sendable {
    var title: String
    var systemContext: String
    var screenContext: CoachScreenContext

    init(
        title: String,
        systemContext: String,
        screenContext: CoachScreenContext = CoachScreenContext(surface: .coach)
    ) {
        self.title = title
        self.systemContext = systemContext
        self.screenContext = screenContext
    }

    static var general: CoachContextFocus {
        CoachContextFocus(
            title: L10n.t("General Coach", "通用教练"),
            systemContext: L10n.t(
                "General health coaching across recovery, sleep, strain, stress, energy, and journal context.",
                "围绕恢复、睡眠、负荷、压力、能量和日记上下文进行综合健康分析。"
            ),
            screenContext: CoachScreenContext(surface: .coach)
        )
    }

    static func routed(
        from surface: CoachScreenSurface,
        selectedDate: Date? = nil
    ) -> CoachContextFocus {
        let screenContext = CoachScreenContext(
            surface: surface,
            selectedDate: selectedDate
        )

        switch surface {
        case .home:
            return CoachContextFocus(
                title: L10n.t("Today", "今日"),
                systemContext: L10n.t(
                    "Explain the independent health scores, their baseline deviations, and likely relationships before discussing downstream actions.",
                    "先解释五个独立身体分数、个人基线偏离和可能联系，再讨论下游行动。"
                ),
                screenContext: screenContext
            )
        case .trends:
            return CoachContextFocus(
                title: L10n.t("Trends", "趋势"),
                systemContext: L10n.t(
                    "Explain the selected time-series horizon, distinguish current deviation from temporal trend, and avoid claiming causality without evidence.",
                    "解释选定时间尺度，区分当前基线偏离与时间趋势；没有证据时不得声称因果。"
                ),
                screenContext: screenContext
            )
        case .plan:
            return CoachContextFocus(
                title: L10n.t("Plan", "计划"),
                systemContext: L10n.t(
                    "Explain how current body evidence relates to the user-owned Daily Operating Plan. Propose material changes for explicit confirmation instead of silently applying them.",
                    "解释当前身体证据与用户拥有的每日行动计划如何关联；实质变更只能形成候选并等待用户确认。"
                ),
                screenContext: screenContext
            )
        case .metricDetail:
            return CoachContextFocus(
                title: L10n.t("Metric detail", "指标详情"),
                systemContext: L10n.t(
                    "Explain the selected metric using its current value, baseline, contributors, coverage, and time series.",
                    "结合当前值、个人基线、贡献因子、数据覆盖和时间序列解释所选指标。"
                ),
                screenContext: screenContext
            )
        case .journal:
            return CoachContextFocus(
                title: L10n.t("Lived state", "主观状态"),
                systemContext: L10n.t(
                    "Relate the user's lived state to objective signals without treating an unreported symptom as absent.",
                    "把用户的主观感受与客观身体信号联系起来，未报告的感受不得视为不存在。"
                ),
                screenContext: screenContext
            )
        case .nutrition:
            return CoachContextFocus(
                title: L10n.t("Nutrition", "营养"),
                systemContext: L10n.t(
                    "Discuss nutrition in proportion to the current body evidence and avoid compensatory actions.",
                    "结合当前身体证据讨论营养，不提出补偿性饮食或运动行为。"
                ),
                screenContext: screenContext
            )
        case .training, .workoutDetail:
            return CoachContextFocus(
                title: L10n.t("Training", "训练"),
                systemContext: L10n.t(
                    "Treat training as a downstream capability of the Daily Operating Plan and explain boundaries from current body evidence.",
                    "把训练视为每日行动计划的下游能力，并从当前身体证据解释执行边界。"
                ),
                screenContext: screenContext
            )
        case .biology:
            return CoachContextFocus(
                title: L10n.t("Biology", "生理"),
                systemContext: L10n.t(
                    "Explain long-term physiology from bounded evidence and personal baselines.",
                    "依据有边界的证据与个人基线解释长期生理变化。"
                ),
                screenContext: screenContext
            )
        case .coach:
            return .general
        }
    }
}

enum CoachRequestContinuity {
    static func shouldRetryAfterInterruption(isAppActive: Bool) -> Bool {
        !isAppActive
    }
}

@MainActor
private final class CoachResponseBackgroundLease {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private var expirationHandler: (() -> Void)?

    func begin(expirationHandler: @escaping () -> Void) {
        end()
        self.expirationHandler = expirationHandler
        identifier = UIApplication.shared.beginBackgroundTask(withName: "CoachResponse") { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.expirationHandler?()
                self.end()
            }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
        expirationHandler = nil
    }
}

// MARK: - ViewModel

@MainActor
final class CoachChatVM: ObservableObject {

    struct ChatMsg: Identifiable, Hashable, Codable {
        var id: UUID = UUID()
        var role: Role
        var content: String
        var timestamp: Date = Date()
        var isStreaming: Bool = false
        var wikiUpdates: [String] = []
        var recoveryAction: LLMErrorRecoveryAction?

        enum Role: String, Codable, Hashable {
            case user
            case assistant
        }

        enum CodingKeys: String, CodingKey {
            case id, role, content, timestamp, wikiUpdates, recoveryAction
        }

        init(
            id: UUID = UUID(),
            role: Role,
            content: String,
            timestamp: Date = Date(),
            isStreaming: Bool = false,
            wikiUpdates: [String] = [],
            recoveryAction: LLMErrorRecoveryAction? = nil
        ) {
            self.id = id
            self.role = role
            self.content = content
            self.timestamp = timestamp
            self.isStreaming = isStreaming
            self.wikiUpdates = wikiUpdates
            self.recoveryAction = recoveryAction
        }
    }

    /// 重试目标：以失败气泡身份为锚点，找到它对应的用户消息——
    /// 用户在 Q1 失败后又问了 Q2 时，点 Q1 的重试必须重发 Q1。
    static func userMessageForRetry(
        in messages: [ChatMsg],
        retryBubbleId: UUID? = nil
    ) -> (text: String, retryBubbleId: UUID)? {
        guard let retryIndex = messages.lastIndex(where: {
            $0.role == .assistant
                && $0.recoveryAction?.destination == .retry
                && (retryBubbleId == nil || $0.id == retryBubbleId)
        }),
        let userIndex = messages[..<retryIndex].lastIndex(where: { $0.role == .user }) else {
            return nil
        }
        return (messages[userIndex].content, messages[retryIndex].id)
    }

    @Published var messages: [ChatMsg] = []
    @Published var draft = ""
    @Published var isStreaming = false
    @Published var isReady = false
    @Published var streamingContent: String = ""
    @Published var isAnalyzingFood = false
    @Published var isAwaitingForegroundRetry = false
    @Published var persistenceError: String?
    /// 会话操作被守卫拦截时的提示（与 sessionStore.interactionHint 同步展示）。
    @Published var interactionHint: String?
    @Published private(set) var isGhostMode = false
    /// 写/破坏类工具等待用户确认（ADR 0008：AI 提议、用户确认）。
    @Published var pendingToolConfirmation: ToolCallDescription?
    private var toolConfirmationContinuation: CheckedContinuation<Bool, Never>?
    private var toolConfirmationTimeoutTask: Task<Void, Never>?
    private var pendingStreamDeltas = ""
    private var streamFlushTask: Task<Void, Never>?
    private static let streamFlushIntervalNanoseconds: UInt64 = 40_000_000

    /// All Coach writes go through the shared gate so a failure remains a
    /// visible typed UI state instead of disappearing behind `try?`.
    private func savePersistence(_ modelContext: ModelContext, operation: String) {
        do {
            try PersistenceWriteGate.shared.withSerializedWrite(
                operation: operation,
                modelContext: modelContext
            ) {
                try modelContext.save()
            }
        } catch {
            persistenceError = "对话内容未保存。请稍后重试。"
            VelaAppState.shared.logDebug("[CoachPersistence] \(operation) failed: \(error.localizedDescription)")
        }
    }

    /// Providers often emit one token at a time. Publishing every token invalidates
    /// the entire conversation tree, so coalesce deltas to roughly one UI update per frame pair.
    private func enqueueStreamDelta(_ delta: String) {
        pendingStreamDeltas += delta
        guard streamFlushTask == nil else { return }

        streamFlushTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.streamFlushIntervalNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.flushPendingStreamDeltas()
        }
    }

    private func flushPendingStreamDeltas() {
        streamFlushTask = nil
        guard !pendingStreamDeltas.isEmpty else { return }
        streamingContent += pendingStreamDeltas
        pendingStreamDeltas = ""
    }

    private func resetStreamingContent() {
        streamFlushTask?.cancel()
        streamFlushTask = nil
        pendingStreamDeltas = ""
        streamingContent = ""
    }

    let quickQuestions: [String] = [
        L10n.t("Today's training advice", "今天的训练建议"),
        L10n.t("Weekly trend analysis", "本周趋势分析"),
        L10n.t("Analyze my sleep", "分析我的睡眠"),
        L10n.t("Update my profile", "更新我的档案"),
    ]

    func contextualQuickQuestions(
        todayPlan: DailyOperatingPlanRecord? = nil,
        dashboard: DashboardSummary? = nil
    ) -> [String] {
        var questions: [String] = []

        if let dashboard {
            if dashboard.recovery.hasData {
                questions.append("为什么我今天的恢复是 \(Int(dashboard.recovery.score.rounded()))？主要受哪些身体信号影响？")
            }

            if dashboard.sleepScore.hasData || dashboard.stress.hasData {
                let sleep = dashboard.sleepScore.hasData
                    ? "睡眠 \(Int(dashboard.sleepScore.score.rounded()))"
                    : "睡眠数据"
                let stress = dashboard.stress.hasData
                    ? "压力 \(Int(dashboard.stress.score.rounded()))"
                    : "压力数据"
                questions.append("\(sleep) 与\(stress)之间可能有什么联系？")
            }

            if let notable = dashboard.personalHealthBrief?.notableChanges.first,
               notable.isAvailable {
                questions.append("\(notable.metric.shortTitle)相对我的个人基线发生了什么变化？")
            } else {
                questions.append("这五个身体分数和我的个人基线相比，有哪些变化值得注意？")
            }
        }

        if todayPlan != nil {
            questions.append("这些身体变化是否需要调整今天的计划？先解释依据，再给候选方案。")
        } else {
            questions.append("根据当前身体状态，今天的健康行动应该怎样安排？")
        }

        let fallbacks = [
            "我目前有哪些身体数据可用，哪些还在建立个人基线？",
            "恢复、睡眠、负荷、压力和能量之间有哪些可能联系？",
            "最近 30 天有哪些指标偏离了我的正常范围？",
            "把当前身体状态转述成一句容易理解的话"
        ]

        for fallback in fallbacks {
            if questions.count < 4 && !questions.contains(fallback) {
                questions.append(fallback)
            }
        }

        return Array(questions.prefix(4))
    }

    /// 根据助手最近一次的回答内容动态生成 2-3 个跟进提问建议（Gemini Mobile 交互风格）。
    func followUpSuggestions(for lastAssistantMessage: String) -> [String] {
        var suggestions: [String] = []
        let lower = lastAssistantMessage.lowercased()

        if lower.contains("训练") || lower.contains("workout") || lower.contains("计划") || lower.contains("容量") {
            suggestions.append("细化今天的热身与主组动作")
            suggestions.append("如果感觉疲劳，推荐哪些替代动作？")
        } else if lower.contains("睡眠") || lower.contains("sleep") || lower.contains("深睡") || lower.contains("入睡") {
            suggestions.append("推荐改善入睡的呼吸法或习惯")
            suggestions.append("分析睡眠对近期力量表现的影响")
        } else if lower.contains("恢复") || lower.contains("hrv") || lower.contains("心率") || lower.contains("压力") {
            suggestions.append("说明 HRV 变化背后的生理原因")
            suggestions.append("今天需要把 RPE 控制在多少以内？")
        } else if lower.contains("饮食") || lower.contains("热量") || lower.contains("营养") || lower.contains("蛋白") {
            suggestions.append("训练日前后该如何安排碳水和蛋白质？")
            suggestions.append("推荐一份轻负担的高蛋白餐食组合")
        }

        if suggestions.isEmpty {
            suggestions.append("把上述建议转化为 3 个具体行动")
            suggestions.append("有哪些需要注意的潜在限制因素？")
        }

        return Array(suggestions.prefix(2))
    }

    // Delegated stores/helpers
    private let sessionStore = CoachSessionStore()
    private let assembler = CoachContextAssembler()
    private let runner = CoachRequestRunner()
    private let writer = CoachPersistenceWriter()
    private let foodWorkflow = FoodPhotoWorkflow()

    private let keychain = KeychainService.shared
    private let apiKeyAccount = "deepseek_api_key"
    private let kimiApiKeyAccount = FoodPhotoAnalyzer.keychainAccount
    private let backgroundLease = CoachResponseBackgroundLease()
    
    private var pendingRequest: PendingRequest?
    private var activeResponseTask: Task<Void, Never>?
    private var isAppActive = true
    private weak var serviceHost: VelaServices?

    private struct PendingRequest {
        var text: String
        var dashboard: DashboardSummary
        var modelContext: ModelContext
        var journalEntries: [JournalEntryRecord]
        var savedReports: [AIReportRecord]
        var focus: CoachContextFocus
        var coverageSummary: DataCoverageSummaryModel?
    }

    var sessions: [CoachSessionRecord] {
        sessionStore.sessions
    }

    var currentSession: CoachSessionRecord? {
        sessionStore.currentSession
    }

    init() {
        // Wire up persistence error tracking
        sessionStore.$persistenceError
            .assign(to: &$persistenceError)
    }

    static func historyBeforeCurrentPrompt(from messages: [ChatMsg], limit: Int) -> [ChatMsg] {
        Array(messages.filter { !$0.isStreaming }.dropLast().suffix(limit))
    }

    static func timestampedHistoryContent(
        for message: ChatMsg,
        calendar: Calendar = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let timestamp = formatter.string(from: message.timestamp)
        return "[Sent at \(timestamp) \(calendar.timeZone.identifier)]\n\(message.content)"
    }

    func refreshKeyState() {
        do {
            isReady = !(try keychain.read(account: apiKeyAccount) ?? "").isEmpty
        } catch {
            isReady = false
        }
    }

    // MARK: - Session Delegation

    func loadSessions(modelContext: ModelContext) {
        sessionStore.loadSessions(
            modelContext: modelContext,
            isStreaming: isStreaming,
            isAwaitingForegroundRetry: isAwaitingForegroundRetry
        ) { [weak self] msgs in
            self?.messages = msgs
        }
    }

    func createNewSession(modelContext: ModelContext) {
        sessionStore.createNewSession(
            modelContext: modelContext,
            isStreaming: isStreaming,
            isAwaitingForegroundRetry: isAwaitingForegroundRetry
        ) { [weak self] msgs in
            self?.messages = msgs
        }
        interactionHint = sessionStore.interactionHint
    }

    func selectSession(_ session: CoachSessionRecord, modelContext: ModelContext) {
        sessionStore.selectSession(
            session,
            modelContext: modelContext,
            isStreaming: isStreaming,
            isAwaitingForegroundRetry: isAwaitingForegroundRetry
        ) { [weak self] msgs in
            self?.messages = msgs
        }
        interactionHint = sessionStore.interactionHint
    }

    func deleteSession(_ session: CoachSessionRecord, modelContext: ModelContext) {
        sessionStore.deleteSession(
            session,
            modelContext: modelContext,
            isStreaming: isStreaming,
            isAwaitingForegroundRetry: isAwaitingForegroundRetry
        ) { [weak self] msgs in
            self?.messages = msgs
        }
        interactionHint = sessionStore.interactionHint
    }

    func renameSession(_ session: CoachSessionRecord, to newTitle: String, modelContext: ModelContext) {
        sessionStore.renameSession(
            session,
            to: newTitle,
            modelContext: modelContext,
            isStreaming: isStreaming,
            isAwaitingForegroundRetry: isAwaitingForegroundRetry
        ) { [weak self] msgs in
            self?.messages = msgs
        }
    }

    func sessionStoreHintCleared() {
        sessionStore.interactionHint = nil
    }

    func persistThread(modelContext: ModelContext) {
        guard !isGhostMode else { return }
        do {
            try writer.persistThread(messages: messages, currentSession: currentSession, modelContext: modelContext)
        } catch {
            persistenceError = "对话内容未保存。请稍后重试。"
        }
    }

    func clearConversation(modelContext: ModelContext) {
        messages = []
        persistThread(modelContext: modelContext)
    }

    func setGhostMode(_ enabled: Bool, modelContext: ModelContext) {
        guard !isStreaming, enabled != isGhostMode else { return }
        isGhostMode = enabled
        messages = []
        draft = ""
        if !enabled {
            loadSessions(modelContext: modelContext)
        }
    }

    func appendLocalExchange(
        userText: String,
        response: String,
        modelContext: ModelContext
    ) {
        let cleanText = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }
        messages.removeAll { $0.isStreaming }
        messages.append(ChatMsg(role: .user, content: cleanText))
        messages.append(ChatMsg(role: .assistant, content: response))

        if !isGhostMode, let current = currentSession,
           current.title == "新对话" || current.title == "New Chat" || current.title == "New Session" || current.title.isEmpty {
            current.title = String(cleanText.prefix(12)) + (cleanText.count > 12 ? "..." : "")
            savePersistence(modelContext, operation: "coach.renameSession")
        }
        persistThread(modelContext: modelContext)
    }

    // MARK: - Food Photo Workflow Delegation

    func analyzeFoodPhoto(
        _ image: UIImage,
        dashboard: DashboardSummary,
        modelContext: ModelContext,
        journalEntries: [JournalEntryRecord],
        savedReports: [AIReportRecord],
        focus: CoachContextFocus = .general,
        services: VelaServices? = nil
    ) async {
        guard let apiKey = try? keychain.read(account: kimiApiKeyAccount), !apiKey.isEmpty else {
            messages.append(ChatMsg(
                role: .assistant,
                content: L10n.t("Please add your Kimi API key in Settings first for food photo analysis.", "请先在设置中添加 Kimi 密钥，用于食物照片识别。")
            ))
            return
        }
        await foodWorkflow.analyzeFoodPhoto(
            image,
            apiKey: apiKey,
            dashboard: dashboard,
            modelContext: modelContext,
            journalEntries: journalEntries,
            savedReports: savedReports,
            focus: focus,
            services: services,
            chatVM: self
        )
    }

    // MARK: - Send request flow

    @discardableResult
    func ensureActiveSession(modelContext: ModelContext) -> CoachSessionRecord {
        if let current = currentSession { return current }
        let session = CoachSessionRecord(
            id: UUID(),
            title: "新对话",
            createdAt: Date(),
            updatedAt: Date(),
            serializedMessages: "[]"
        )
        modelContext.insert(session)
        savePersistence(modelContext, operation: "coach.createSession")
        sessionStore.currentSession = session
        if !sessionStore.sessions.contains(where: { $0.id == session.id }) {
            sessionStore.sessions.append(session)
        }
        return session
    }

    func submit(
        text: String? = nil,
        dashboard: DashboardSummary,
        modelContext: ModelContext,
        journalEntries: [JournalEntryRecord],
        savedReports: [AIReportRecord],
        focus: CoachContextFocus = .general,
        services: VelaServices? = nil,
        coverageSummary: DataCoverageSummaryModel? = nil
    ) {
        guard activeResponseTask == nil else {
            interactionHint = "正在回复中，完成后即可再次发送。"
            return
        }
        let targetText = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetText.isEmpty else { return }
        draft = ""
        ensureActiveSession(modelContext: modelContext)
        serviceHost = services
        // 算法打通（深度专项批次 1）：isStreaming 同步置位——此前要等异步 send()
        // 跑到后半段才翻转，会话新建/切换/删除守卫只看 isStreaming，存在窄窗口
        // 可绕过守卫，让在途回复写进错误会话（数据破坏级）。
        isStreaming = true
        pendingRequest = PendingRequest(
            text: targetText,
            dashboard: dashboard,
            modelContext: modelContext,
            journalEntries: journalEntries,
            savedReports: savedReports,
            focus: focus,
            coverageSummary: coverageSummary
        )
        startPendingRequest(appendingUserMessage: true)
    }

    func handleAppActiveChange(isActive: Bool) {
        isAppActive = isActive
        guard isActive, isAwaitingForegroundRetry else { return }
        startPendingRequest(appendingUserMessage: false)
    }

    func retryLastFailedRequest(
        dashboard: DashboardSummary,
        modelContext: ModelContext,
        journalEntries: [JournalEntryRecord],
        savedReports: [AIReportRecord],
        focus: CoachContextFocus = .general,
        services: VelaServices? = nil,
        retryBubbleId: UUID? = nil
    ) {
        guard activeResponseTask == nil,
              let retryTarget = Self.userMessageForRetry(in: messages, retryBubbleId: retryBubbleId) else {
            return
        }

        messages.removeAll { $0.id == retryTarget.retryBubbleId }
        serviceHost = services
        pendingRequest = PendingRequest(
            text: retryTarget.text,
            dashboard: dashboard,
            modelContext: modelContext,
            journalEntries: journalEntries,
            savedReports: savedReports,
            focus: focus
        )
        startPendingRequest(appendingUserMessage: false)
    }

    private func startPendingRequest(appendingUserMessage: Bool) {
        guard activeResponseTask == nil, let pendingRequest else { return }
        isAwaitingForegroundRetry = false
        // 深度专项批次 1：与 submit() 一致，重试路径同样同步置位 isStreaming。
        isStreaming = true
        activeResponseTask = Task { [weak self] in
            guard let self else { return }
            await self.send(
                text: pendingRequest.text,
                dashboard: pendingRequest.dashboard,
                modelContext: pendingRequest.modelContext,
                journalEntries: pendingRequest.journalEntries,
                savedReports: pendingRequest.savedReports,
                focus: pendingRequest.focus,
                services: self.serviceHost,
                appendingUserMessage: appendingUserMessage,
                coverageSummary: pendingRequest.coverageSummary
            )
            self.activeResponseTask = nil
            if self.isAwaitingForegroundRetry {
                if self.isAppActive {
                    self.startPendingRequest(appendingUserMessage: false)
                }
            } else {
                self.pendingRequest = nil
            }
        }
    }

    private func handleBackgroundTimeExpired() {
        guard activeResponseTask != nil else { return }
        isAwaitingForegroundRetry = true
        activeResponseTask?.cancel()
    }

    /// Cancel the in-flight assistant response (user tapped "stop").
    func cancelActiveResponse() {
        guard activeResponseTask != nil else { return }
        // 深度专项批次 1：stop() 立即按拒绝收尾挂起的工具确认卡——
        // 此前要等流结束后才 confirmToolCall(false)，确认卡最多挂满 60s，
        // 且期间 activeResponseTask 非空、后续发送被挡。
        if pendingToolConfirmation != nil {
            confirmToolCall(false)
        }
        activeResponseTask?.cancel()
    }

    func send(
        text: String,
        dashboard: DashboardSummary,
        modelContext: ModelContext,
        journalEntries: [JournalEntryRecord],
        savedReports: [AIReportRecord],
        focus: CoachContextFocus = .general,
        services: VelaServices? = nil,
        appendingUserMessage: Bool = true,
        coverageSummary: DataCoverageSummaryModel? = nil
    ) async {
        let userText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 深度专项批次 1：isStreaming 已在 submit/startPendingRequest 同步置位，
        // 此处不再用它挡双重入口（activeResponseTask 守卫已保证唯一在途请求）。
        guard !userText.isEmpty else { return }
        draft = ""
        refreshKeyState()

        messages.removeAll { $0.isStreaming }
        resetStreamingContent()
        if appendingUserMessage {
            messages.append(ChatMsg(role: .user, content: userText))
            // 深度专项批次 2：用户消息立即落盘——此前整条线程要到流式完成/出错才
            // 首次持久化，流式中被杀 App 连用户提问一起丢失。
            persistThread(modelContext: modelContext)
        }

        if !isGhostMode, appendingUserMessage, let current = currentSession, (current.title == "新对话" || current.title == "New Chat" || current.title == "New Session" || current.title.isEmpty) {
            let cleanQuery = userText.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayTitle = String(cleanQuery.prefix(12)) + (cleanQuery.count > 12 ? "..." : "")
            current.title = displayTitle.isEmpty ? "新对话" : displayTitle
            savePersistence(modelContext, operation: "coach.renameSessionFromPrompt")
        }

        guard let apiKey = try? keychain.read(account: apiKeyAccount), !apiKey.isEmpty else {
            let providerError = LLMProviderError.missingAPIKey
            messages.append(ChatMsg(
                role: .assistant,
                content: providerError.userFacingMessage(isChinese: AppLanguage.stored.isChinese),
                recoveryAction: providerError.recoveryAction(isChinese: AppLanguage.stored.isChinese)
            ))
            isReady = false
            persistThread(modelContext: modelContext)
            isStreaming = false
            return
        }

        isStreaming = true
        backgroundLease.begin { [weak self] in
            self?.handleBackgroundTimeExpired()
        }
        defer { backgroundLease.end() }

        let assistantId = UUID()
        messages.append(ChatMsg(id: assistantId, role: .assistant, content: "", isStreaming: true))

        do {
            let requestContext = await assembler.buildRequestContext(
                userText: userText,
                dashboard: dashboard,
                journalEntries: journalEntries,
                savedReports: savedReports,
                focus: focus,
                modelContext: modelContext,
                messages: messages,
                coverageSummary: coverageSummary
            )
            let chatMessages = requestContext.messages

            // Non-casual Coach artifacts and interactions must point at the
            // canonical facts used by this request. Casual compatibility
            // requests have no snapshot and retain the message-content hash.
            let contextHash = requestContext.agentFactSnapshot?.contextHash
                ?? ContentHash.hash(chatMessages.map { $0.content }.joined(separator: "\n"))

            let loopResult = try await runner.runRequest(
                userText: userText,
                apiKey: apiKey,
                chatMessages: chatMessages,
                dashboard: dashboard,
                agentFactSnapshot: requestContext.agentFactSnapshot,
                modelContext: modelContext,
                services: services,
                isGhostMode: isGhostMode,
                onStreamDelta: { [weak self] delta in
                    self?.enqueueStreamDelta(delta)
                },
                onConfirmToolCall: { [weak self] description in
                    guard let self else { return false }
                    return await self.requestToolConfirmation(description)
                }
            )

            var wikiFiles = loopResult.wikiFiles
            var wikiUpdateSummaries = loopResult.wikiUpdateSummaries
            var fullResponse = loopResult.response

            if fullResponse.isEmpty {
                fullResponse = L10n.t(
                    "I wasn't able to generate a response. Please try again.",
                    "我无法生成回复，请再试一次。"
                )
            }

            // Parse and extract structured <artifact>...</artifact> tags
            var finalResponseProcessed = fullResponse
            let artifactRegex = try? NSRegularExpression(pattern: "<artifact>\\s*(.*?)\\s*</artifact>", options: [.dotMatchesLineSeparators])
            if let regex = artifactRegex {
                let range = NSRange(fullResponse.startIndex..<fullResponse.endIndex, in: fullResponse)
                let matches = regex.matches(in: fullResponse, options: [], range: range)
                
                // Process in reverse order so replacements don't shift indices
                for match in matches.reversed() {
                    guard let matchRange = Range(match.range(at: 0), in: fullResponse),
                          let contentRange = Range(match.range(at: 1), in: fullResponse) else { continue }
                    
                    let artifactRaw = String(fullResponse[contentRange])
                    if isGhostMode {
                        finalResponseProcessed.replaceSubrange(matchRange, with: "")
                        continue
                    }
                    if let parsedArtifact = try? CoachArtifactParser.parse(artifactRaw, sourceContextHash: contextHash) {
                        // Persist to SwiftData
                        let record = CoachArtifactRecord(artifact: parsedArtifact)
                        modelContext.insert(record)
                        savePersistence(modelContext, operation: "coach.persistArtifact")
                        
                        // Replace the xml tag in the response text with inline artifact tag
                        let inlineTag = "[ARTIFACT:\(parsedArtifact.type.rawValue):\(record.id.uuidString)]"
                        finalResponseProcessed.replaceSubrange(matchRange, with: inlineTag)
                    }
                }
            }

            let parsed = AgentActionParser.parse(finalResponseProcessed)
            // 双通道去重：AgentLoop 路径的 wiki 更新已由 update_user_wiki 工具
            // （带用户确认）处理，legacy [ACTION:update_wiki] 解析仅在 casual
            // 短回复路径（无工具通道）保留。
            let isCasualPath = ResponseLengthPolicy.forQuery(userText, lang: AppLanguage.stored) == .casual
            if !isGhostMode && isCasualPath {
                let ledger = MemoryLedger(modelContext: modelContext)
                for action in parsed.actions where action.type == .updateWiki {
                    let memType = WikiFileRole.memoryTypeFor(filename: action.target)
                    let proposal = try? ledger.createProposal(
                        targetFile: action.target,
                        memoryType: memType,
                        content: action.content,
                        evidence: "Coach conversation — AI detected pattern worth recording.",
                        confidence: 0.5,
                        source: "coach_legacy_parser"
                    )
                    if proposal != nil, !wikiFiles.contains(action.target) {
                        wikiFiles.append(action.target)
                        wikiUpdateSummaries.append("\(action.target): \(action.content)")
                    }
                }
            }

            let finalText = parsed.displayText.isEmpty ? fullResponse : parsed.displayText
            
            if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                messages[idx] = ChatMsg(
                    id: assistantId,
                    role: .assistant,
                    content: finalText,
                    wikiUpdates: wikiFiles
                )
            }

            if !isGhostMode {
                do {
                    persistThread(modelContext: modelContext)
                    try writer.persistInteraction(
                        userText: userText,
                        assistantText: finalText,
                        focus: focus,
                        contextHash: contextHash,
                        currentSession: currentSession,
                        modelContext: modelContext
                    )

                    var agentTrace = loopResult.trace
                    agentTrace.finalResponse = finalText
                    agentTrace.endedAt = Date()
                    try writer.persistAgentTrace(agentTrace, modelContext: modelContext)

                    try? DailyLogService.recordInteraction(
                        dashboard: dashboard,
                        userText: userText,
                        assistantText: finalText,
                        wikiUpdates: wikiFiles,
                        coachArchiveSummary: wikiUpdateSummaries.isEmpty
                            ? nil
                            : "本轮 Coach 主动提出长期档案更新：" + wikiUpdateSummaries.joined(separator: "；")
                    )
                } catch {
                    // 持久化失败 ≠ 请求失败：已成功的回复保留在界面上，只暴露持久化错误。
                    persistenceError = error.localizedDescription
                    persistThread(modelContext: modelContext)
                }
            }

            isReady = true
            isAwaitingForegroundRetry = false
        } catch {
            let isUserCancellation = error is CancellationError
                || (error as? URLError)?.code == .cancelled
            if isUserCancellation {
                // 用户主动停止：把已流出的部分内容固化进气泡（与注释一致），
                // 不追加伪造的「服务不可用」错误气泡；无内容则移除空泡。
                flushPendingStreamDeltas()
                let partial = streamingContent
                if partial.isEmpty {
                    messages.removeAll { $0.id == assistantId }
                } else if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                    messages[idx] = ChatMsg(
                        id: assistantId,
                        role: .assistant,
                        content: partial,
                        wikiUpdates: messages[idx].wikiUpdates
                    )
                }
                resetStreamingContent()
            } else {
                resetStreamingContent()
                messages.removeAll { $0.id == assistantId }
                let shouldRetry = pendingRequest != nil
                    && (isAwaitingForegroundRetry
                        || CoachRequestContinuity.shouldRetryAfterInterruption(isAppActive: isAppActive))
                if shouldRetry {
                    isAwaitingForegroundRetry = true
                } else {
                    let providerError = LLMProviderError.classify(error)
                    messages.append(ChatMsg(
                        id: assistantId,
                        role: .assistant,
                        content: providerError.userFacingMessage(isChinese: AppLanguage.stored.isChinese),
                        recoveryAction: providerError.recoveryAction(isChinese: AppLanguage.stored.isChinese)
                    ))
                }
            }
            persistThread(modelContext: modelContext)
        }

        resetStreamingContent()
        isStreaming = false
        // 流式结束/取消时若确认弹窗仍挂起（用户未响应），自动按拒绝收尾，
        // 避免 continuation 泄漏导致任务悬挂。
        if pendingToolConfirmation != nil {
            confirmToolCall(false)
        }
    }

    /// 等待用户在界面上确认写/破坏类工具调用；60 秒未响应按拒绝处理，
    /// 避免确认挂起卡死整个 Agent 循环。
    @MainActor
    private func requestToolConfirmation(_ description: ToolCallDescription) async -> Bool {
        await withCheckedContinuation { continuation in
            toolConfirmationContinuation = continuation
            pendingToolConfirmation = description
            toolConfirmationTimeoutTask?.cancel()
            toolConfirmationTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard let self, self.toolConfirmationContinuation != nil else { return }
                self.confirmToolCall(false)
            }
        }
    }

    /// 用户对工具确认弹窗作出选择。
    func confirmToolCall(_ approved: Bool) {
        guard let continuation = toolConfirmationContinuation else { return }
        toolConfirmationTimeoutTask?.cancel()
        toolConfirmationTimeoutTask = nil
        toolConfirmationContinuation = nil
        pendingToolConfirmation = nil
        continuation.resume(returning: approved)
    }
}
