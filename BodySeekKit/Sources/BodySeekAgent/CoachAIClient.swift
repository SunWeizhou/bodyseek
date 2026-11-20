import BodySeekCore
import BodySeekHealth
import Dependencies
import DependenciesMacros
import Foundation
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

public struct CoachAIConfig: Equatable, Sendable, Codable {
    public var endpointURL: String
    public var modelName: String

    public init(
        endpointURL: String = "https://api.deepseek.com/v1",
        modelName: String = "deepseek-chat"
    ) {
        self.endpointURL = endpointURL
        self.modelName = modelName
    }
}

public enum CoachAgentOrchestrator {
    private static let logger = Logger(subsystem: "com.sunweizhou.Vela4", category: "CoachAgentOrchestrator")

    public static func buildSystemPrompt(
        query: String,
        context: AgentExecutionContext,
        now: Date = Date()
    ) -> String {
        let relevantMemories = MemoryContextSelector.selectRelevant(
            query: query,
            memories: context.tieredMemories,
            now: now,
            maxCount: 6
        )

        let memoryLines: String
        if relevantMemories.isEmpty {
            memoryLines = "当前查询无匹配的激活记忆。"
        } else {
            memoryLines = relevantMemories.map { rec in
                let expNote = rec.expiresAt.map { "（有效期至 \($0.physiologicalDayKey().isoString)）" } ?? ""
                return "- [\(rec.tier.rawValue)] \(rec.content)\(expNote)"
            }.joined(separator: "\n")
        }

        return """
        你是 BodySeek 的专业运动科学与生理数据智能体，服务 Watch-First 力量与耐力训练用户。
        核心守则（严格遵守）：
        1. 先调用只读工具核实数据（get_today_context / get_metric_trend / get_workouts_and_muscles / get_sleep_detail / get_patterns / find_similar_days / get_eating_context / get_personal_forecast / search_exercise_catalog）。
        2. 严格区分四态真值：missing / excluded 的指标绝不当作 0，也绝不编造任何健康数字；回答中引用的每个健康数值都必须直接来自本轮工具返回结果。
        3. 肌群恢复百分比必须标注为「启发式估计」（recovery-heuristic-v1）；用户手打用力（EffortUser）与 Apple 系统估算（Estimated）分开陈述。
        4. get_patterns、find_similar_days 与 get_personal_forecast 仅为相关性、历史相似日类比或带不确定度区间的个人统计预测，绝不宣称“证明了因果关系”、不冒充医学诊断，也不进行反事实捏造。
        5. 任何写操作只能通过提案工具生成待确认卡片：
           - 训练课表建议 -> search_exercise_catalog 后调用 propose_plan_change
           - 长期偏好/短期伤病约束记忆 -> propose_memory（activeConstraint 默认 14 天过期；未经 confirmed 的 pattern_finding 不得提出 verifiedPattern）
           - 手表力量训练一句话标定 -> propose_workout_annotation
        6. 绝对不要输出 <tool_call>、<|DSML|> 等 XML 或内部标签，直接用简洁克制的中文回复。

        与本轮对话相关的已激活三层记忆：
        \(memoryLines)

        今日背景摘要（请以工具返回的四态 JSON 为准）：
        \(context.snapshot.today.factualSummary)
        """
    }

    public static func runCloudCompletion(
        question: String,
        context: AgentExecutionContext,
        endpointURL: String,
        apiKey: String,
        modelName: String,
        client: OpenAICompatibleClient,
        preferStreaming: Bool = true
    ) async throws -> CoachMessage {
        let systemPrompt = buildSystemPrompt(
            query: question,
            context: context,
            now: context.snapshot.referenceDate
        )
        let messages = [
            OpenAIChatMessage(role: "system", content: systemPrompt),
            OpenAIChatMessage(role: "user", content: question),
        ]

        let completion = try await client.runChatCompletionLoop(
            endpointURL: endpointURL,
            apiKey: apiKey,
            modelName: modelName,
            messages: messages,
            tools: CoachToolRegistry.openAIToolDefinitions,
            temperature: 0.3,
            preferStreaming: preferStreaming
        ) { toolName, argsJSON in
            await CoachToolRegistry.execute(name: toolName, argumentsJSON: argsJSON, context: context)
        }

        let toolOutputs = await context.effects.toolOutputs
        let toolsInvoked = await context.effects.toolsInvoked
        let provenance = NumericProvenanceVerifier.verify(
            responseText: completion.content,
            toolOutputs: toolOutputs,
            userQuestion: question
        )

        let workoutProposal = await context.effects.workoutProposal
        let memoryProposal = await context.effects.memoryProposal
        let annotationProposal = await context.effects.workoutAnnotationProposal

        let finalBody = provenance.annotatedText.isEmpty
            ? "已通过工具完成核查。"
            : provenance.annotatedText

        return CoachMessage(
            role: .assistant,
            text: finalBody,
            engineLabel: "云端智能体 · \(modelName)",
            evidenceMetric: inferredMetric(from: question),
            workoutProposal: workoutProposal,
            memorySavedNote: memoryProposal.map { "待你确认记忆 [\($0.tier.titleLabel)]：\($0.content)" },
            memoryProposal: memoryProposal,
            workoutAnnotationProposal: annotationProposal,
            unverifiedNumbers: provenance.unverifiedTokens,
            toolsInvoked: toolsInvoked
        )
    }

    public static func runPreviewFixture(
        question: String,
        context: AgentExecutionContext
    ) async -> CoachMessage {
        let lower = question.lowercased()
        let todayJSON = await CoachToolRegistry.execute(name: "get_today_context", argumentsJSON: "{}", context: context)

        if lower.contains("睡") || lower.contains("sleep") {
            _ = await CoachToolRegistry.execute(name: "get_sleep_detail", argumentsJSON: "{}", context: context)
        }
        if lower.contains("类似") || lower.contains("相似") || lower.contains("基线") {
            _ = await CoachToolRegistry.execute(name: "find_similar_days", argumentsJSON: "{}", context: context)
        }
        if lower.contains("预测") || lower.contains("明天") || lower.contains("次日") || lower.contains("forecast") {
            _ = await CoachToolRegistry.execute(name: "get_personal_forecast", argumentsJSON: "{}", context: context)
        }
        if lower.contains("吃") || lower.contains("餐") || lower.contains("饮食") || lower.contains("营养") {
            _ = await CoachToolRegistry.execute(name: "get_eating_context", argumentsJSON: #"{"days":7}"#, context: context)
        }
        if lower.contains("练") || lower.contains("肌") || lower.contains("复盘") || lower.contains("减量") || lower.contains("课表") {
            _ = await CoachToolRegistry.execute(name: "get_workouts_and_muscles", argumentsJSON: #"{"days":7}"#, context: context)
        }

        let wantsMemory = lower.contains("记住") || lower.contains("膝") || lower.contains("肩") || lower.contains("腰") || lower.contains("忌口")
        if wantsMemory {
            let cleanMem = question
                .replacingOccurrences(of: "记住我", with: "")
                .replacingOccurrences(of: "记住", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let memArgs = """
            {"tier":"activeConstraint","category":"injury","expiresDays":14,"content":"\(escapeJSON(cleanMem.isEmpty ? question : cleanMem))"}
            """
            _ = await CoachToolRegistry.execute(name: "propose_memory", argumentsJSON: memArgs, context: context)
        }

        let wantsAnnotation = lower.contains("标注") || (lower.contains("复盘") && (lower.contains("卧推") || lower.contains("深蹲") || lower.contains("rpe")))
        if wantsAnnotation {
            let annArgs = """
            {"rawText":"\(escapeJSON(question))"}
            """
            _ = await CoachToolRegistry.execute(name: "propose_workout_annotation", argumentsJSON: annArgs, context: context)
        }

        let wantsWorkout = lower.contains("减量") || lower.contains("课表") || lower.contains("排") || lower.contains("调整")
        if wantsWorkout {
            _ = await CoachToolRegistry.execute(name: "search_exercise_catalog", argumentsJSON: #"{"query":"chest"}"#, context: context)
            let recVal = context.snapshot.today.recovery.value
            let rationale = if let recVal {
                "基于今日恢复 \(recVal) 分与近期肌群负荷（启发式估计），建议将训练容量控制在维持减量区间并延长组间休息。"
            } else {
                "当前部分客观恢复数据待同步，稳妥采用低关节压力的维持性上肢课表。"
            }
            let planArgs = """
            {"title":"适配减量上肢控制训练","focusTag":"AI 处方","exerciseIDsCSV":"barbell-bench-press,lat-pulldown,face-pull","intensityMultiplier":0.75,"restSeconds":105,"rationale":"\(escapeJSON(rationale))"}
            """
            _ = await CoachToolRegistry.execute(name: "propose_plan_change", argumentsJSON: planArgs, context: context)
        }

        var parts: [String] = []
        let today = context.snapshot.today
        if let rec = today.recovery.value {
            parts.append("今日恢复 \(rec) 分（\(today.recovery.badge)）")
        } else {
            parts.append("今日恢复数据待同步")
        }
        if let sleepMin = today.raw.sleepAsleepMinutes {
            parts.append(String(format: "睡眠 %d 分钟（%.1f 小时）", sleepMin, Double(sleepMin) / 60.0))
        }
        if let acwr = context.snapshot.trainingLoad.acwrRatio {
            parts.append(String(format: "ACWR 处于 %@（近 7 天急负荷 %.0f）", context.snapshot.trainingLoad.zone.title, context.snapshot.trainingLoad.acute7dLoad))
            _ = acwr
        }
        if wantsMemory {
            parts.append("已为你准备一条 14 天短期约束记忆提案，请在下方确认后再写入记忆库")
        }
        if wantsWorkout {
            parts.append("已结合肌群启发式估计状态生成待确认处方卡")
        }
        let rawReply = "已调用工具核实四态观测（\((todayJSON.isEmpty ? "" : context.snapshot.today.dayKey.isoString))）：\n" + parts.joined(separator: "；") + "。"

        let toolOutputs = await context.effects.toolOutputs
        let toolsInvoked = await context.effects.toolsInvoked
        let provenance = NumericProvenanceVerifier.verify(
            responseText: rawReply,
            toolOutputs: toolOutputs,
            userQuestion: question
        )

        let workoutProposal = await context.effects.workoutProposal
        let memoryProposal = await context.effects.memoryProposal
        let annotationProposal = await context.effects.workoutAnnotationProposal

        return CoachMessage(
            role: .assistant,
            text: provenance.annotatedText,
            engineLabel: "预览演示 · 四态工具引擎",
            evidenceMetric: inferredMetric(from: question),
            workoutProposal: workoutProposal,
            memorySavedNote: memoryProposal.map { "待你确认记忆 [\($0.tier.titleLabel)]：\($0.content)" },
            memoryProposal: memoryProposal,
            workoutAnnotationProposal: annotationProposal,
            unverifiedNumbers: provenance.unverifiedTokens,
            toolsInvoked: toolsInvoked
        )
    }

    public static func inferredMetric(from question: String) -> MetricKind {
        let lower = question.lowercased()
        if lower.contains("睡") || lower.contains("sleep") { return .sleep }
        if lower.contains("负荷") || lower.contains("练") || lower.contains("acwr") { return .strain }
        if lower.contains("压") || lower.contains("stress") { return .stress }
        if lower.contains("能") || lower.contains("电") || lower.contains("energy") { return .energy }
        return .recovery
    }

    private static func escapeJSON(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

extension MemoryTier {
    public var titleLabel: String {
        switch self {
        case .profile: "长期档案"
        case .activeConstraint: "短期约束"
        case .verifiedPattern: "已验证规律"
        }
    }
}

// MARK: - Dependency Client

@DependencyClient
public struct CoachAIClient: Sendable {
    public var reply: @Sendable (_ question: String, _ context: AgentExecutionContext) async -> CoachMessage = { _, context in
        CoachMessage(
            role: .assistant,
            text: "当前处于离线状态（\(context.snapshot.today.factualSummary)）。"
        )
    }
    public var generateBriefing: @Sendable (_ context: AgentExecutionContext) async -> AIBriefingStatus = { _ in
        .unconfigured(reason: "连接 DeepSeek / OpenAI 兼容接口或在支持 Apple 智能的设备开启端侧模型")
    }
    public var loadAPIKey: @Sendable () throws -> String = { "" }
    public var saveAPIKey: @Sendable (_ key: String) throws -> Void = { _ in }
    public var loadConfig: @Sendable () -> CoachAIConfig = { CoachAIConfig() }
    public var saveConfig: @Sendable (_ config: CoachAIConfig) -> Void = { _ in }
    public var testConnection: @Sendable (_ apiKey: String, _ config: CoachAIConfig) async -> String? = { _, _ in nil }
    public var lastOutboundPayload: @Sendable () async -> AgentOutboundPayloadSnapshot? = { nil }
}

extension CoachAIClient: DependencyKey {
    public static let endpointStorageKey = "bodyseek.coach.endpoint"
    public static let modelStorageKey = "bodyseek.coach.model"
    private static let logger = Logger(subsystem: "com.sunweizhou.Vela4", category: "CoachAIClient")

    public static let liveValue: CoachAIClient = {
        let httpClient = OpenAICompatibleClient()
        return CoachAIClient(
            reply: { question, context in
                let isPreview = ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard")
                var keychainWarning: String?
                let apiKey: String
                do {
                    apiKey = try KeychainCredentialStore.live.loadAPIKey()
                } catch {
                    logger.error("Failed reading API key from Keychain: \(error.localizedDescription, privacy: .public)")
                    keychainWarning = "读取 Keychain 凭据失败：\(error.localizedDescription)"
                    apiKey = ""
                }

                let endpoint = UserDefaults.standard.string(forKey: endpointStorageKey) ?? "https://api.deepseek.com/v1"
                let modelName = UserDefaults.standard.string(forKey: modelStorageKey) ?? "deepseek-chat"
                let fmAvailable = isFoundationModelsAvailable()

                let route = AgentRoutingPolicy.resolve(
                    isPreview: isPreview,
                    apiKey: apiKey,
                    endpoint: endpoint,
                    modelName: modelName,
                    foundationModelsAvailable: fmAvailable,
                    intent: .chat
                )

                switch route {
                case .previewFixture:
                    return await CoachAgentOrchestrator.runPreviewFixture(question: question, context: context)

                case let .cloudOpenAICompatible(resolvedEndpoint, resolvedModel):
                    do {
                        return try await CoachAgentOrchestrator.runCloudCompletion(
                            question: question,
                            context: context,
                            endpointURL: resolvedEndpoint,
                            apiKey: apiKey,
                            modelName: resolvedModel,
                            client: httpClient
                        )
                    } catch {
                        logger.error("Cloud AI reply failed: \(error.localizedDescription, privacy: .public)")
                        return CoachMessage(
                            role: .assistant,
                            text: "云端 AI 请求失败：\(error.localizedDescription)\n\n请检查设置中的 API Endpoint、模型名称与 Keychain 中的 API Key。\n客观数据参考：\(context.snapshot.today.factualSummary)",
                            engineLabel: "云端连接异常",
                            evidenceMetric: CoachAgentOrchestrator.inferredMetric(from: question)
                        )
                    }

                case .onDeviceFoundationModels:
                    #if canImport(FoundationModels)
                    if #available(iOS 26.0, macOS 26.0, *) {
                        do {
                            return try await runFoundationModelsAgent(question: question, context: context)
                        } catch {
                            logger.error("FoundationModels reply failed: \(error.localizedDescription, privacy: .public)")
                            return unconfiguredFallbackMessage(
                                diagnostic: "端侧 Apple 智能执行失败：\(error.localizedDescription)",
                                question: question,
                                context: context
                            )
                        }
                    }
                    #endif
                    return unconfiguredFallbackMessage(diagnostic: keychainWarning, question: question, context: context)

                case let .unconfigured(reason):
                    return unconfiguredFallbackMessage(
                        diagnostic: keychainWarning ?? reason,
                        question: question,
                        context: context
                    )
                }
            },
            generateBriefing: { context in
                let isPreview = ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard")
                if isPreview {
                    let day = context.snapshot.today
                    return .generated(
                        text: "示例简报：今日恢复 \(day.recovery.formattedScore)，近 7 天负荷比 \(context.snapshot.trainingLoad.acwrRatio.map { String(format: "%.2f", $0) } ?? "--")（\(context.snapshot.trainingLoad.zone.title)），建议按中等 RPE 完成训练。",
                        engineName: "预览模式"
                    )
                }

                let prompt = "基于提供的今日四态身体数据与近7天训练负荷，直接用不超过65个汉字给出一句精准、克制、非因果夸大的今日状态点评与训练取向建议。只输出纯中文文本。"
                let apiKey: String
                do {
                    apiKey = try KeychainCredentialStore.live.loadAPIKey()
                } catch {
                    logger.error("Failed reading API key during briefing: \(error.localizedDescription, privacy: .public)")
                    return .unconfigured(reason: "Keychain 读取失败：\(error.localizedDescription)")
                }

                let endpoint = UserDefaults.standard.string(forKey: endpointStorageKey) ?? "https://api.deepseek.com/v1"
                let modelName = UserDefaults.standard.string(forKey: modelStorageKey) ?? "deepseek-chat"
                let route = AgentRoutingPolicy.resolve(
                    isPreview: false,
                    apiKey: apiKey,
                    endpoint: endpoint,
                    modelName: modelName,
                    foundationModelsAvailable: isFoundationModelsAvailable(),
                    intent: .briefing
                )

                switch route {
                case .previewFixture:
                    return .unconfigured(reason: "预览模式")
                case let .cloudOpenAICompatible(resolvedEndpoint, resolvedModel):
                    do {
                        let msg = try await CoachAgentOrchestrator.runCloudCompletion(
                            question: prompt,
                            context: context,
                            endpointURL: resolvedEndpoint,
                            apiKey: apiKey,
                            modelName: resolvedModel,
                            client: httpClient
                        )
                        return .generated(text: msg.text, engineName: resolvedModel)
                    } catch {
                        logger.error("Cloud briefing failed: \(error.localizedDescription, privacy: .public)")
                        return .unconfigured(reason: "云端 AI 连接失败：\(error.localizedDescription)")
                    }
                case .onDeviceFoundationModels:
                    #if canImport(FoundationModels)
                    if #available(iOS 26.0, macOS 26.0, *) {
                        do {
                            let msg = try await runFoundationModelsAgent(question: prompt, context: context)
                            return .generated(text: msg.text, engineName: "Apple 端侧模型")
                        } catch {
                            logger.error("FoundationModels briefing failed: \(error.localizedDescription, privacy: .public)")
                            return .unconfigured(reason: "Apple 端侧简报生成失败：\(error.localizedDescription)")
                        }
                    }
                    #endif
                    return .unconfigured(reason: "端侧 Apple 智能不可用")
                case let .unconfigured(reason):
                    return .unconfigured(reason: reason)
                }
            },
            loadAPIKey: {
                try KeychainCredentialStore.live.loadAPIKey()
            },
            saveAPIKey: { key in
                try KeychainCredentialStore.live.saveAPIKey(key)
            },
            loadConfig: {
                CoachAIConfig(
                    endpointURL: UserDefaults.standard.string(forKey: endpointStorageKey) ?? "https://api.deepseek.com/v1",
                    modelName: UserDefaults.standard.string(forKey: modelStorageKey) ?? "deepseek-chat"
                )
            },
            saveConfig: { config in
                UserDefaults.standard.set(config.endpointURL, forKey: endpointStorageKey)
                UserDefaults.standard.set(config.modelName, forKey: modelStorageKey)
            },
            testConnection: { apiKey, config in
                await httpClient.testConnection(
                    endpointURL: config.endpointURL,
                    apiKey: apiKey,
                    modelName: config.modelName
                )
            },
            lastOutboundPayload: {
                await AgentPayloadRecorder.shared.latest()
            }
        )
    }()

    public static let previewValue = CoachAIClient(
        reply: { question, context in
            await CoachAgentOrchestrator.runPreviewFixture(question: question, context: context)
        },
        generateBriefing: { context in
            .generated(
                text: "示例简报：恢复 \(context.snapshot.today.recovery.formattedScore)，ACWR 处于\(context.snapshot.trainingLoad.zone.title)，适合维持力量刺激。",
                engineName: "预览模式"
            )
        },
        loadAPIKey: { "" },
        saveAPIKey: { _ in },
        loadConfig: { CoachAIConfig() },
        saveConfig: { _ in },
        testConnection: { _, _ in nil },
        lastOutboundPayload: { await AgentPayloadRecorder.shared.latest() }
    )

    private static func isFoundationModelsAvailable() -> Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                return true
            }
        }
        #endif
        return false
    }

    private static func unconfiguredFallbackMessage(
        diagnostic: String?,
        question: String,
        context: AgentExecutionContext
    ) -> CoachMessage {
        let diagBlock = (diagnostic?.isEmpty == false) ? "\n诊断信息：\(diagnostic ?? "")\n" : ""
        return CoachMessage(
            role: .assistant,
            text: """
            未检测到可用的 AI 模型。请任选其一启用真 AI 驱动：
            1. 在「设置」中填入 DeepSeek 或 OpenAI 兼容 API Key；
            2. 在支持 Apple 智能的真机上开启端侧模型。
            \(diagBlock)
            客观数据参考：\(context.snapshot.today.factualSummary)
            """,
            engineLabel: "需要启用 AI",
            evidenceMetric: CoachAgentOrchestrator.inferredMetric(from: question)
        )
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private static func runFoundationModelsAgent(
        question: String,
        context: AgentExecutionContext
    ) async throws -> CoachMessage {
        let instructions = CoachAgentOrchestrator.buildSystemPrompt(query: question, context: context)
        let tools: [any Tool] = [
            FMTodayContextTool(context: context),
            FMWorkoutsAndMusclesTool(context: context),
            FMSleepDetailTool(context: context),
            FMProposeMemoryTool(context: context),
            FMProposePlanTool(context: context),
        ]
        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            tools: tools,
            instructions: instructions
        )
        let response = try await session.respond(to: question)
        let cleaned = ToolMarkupScrubber.scrub(response.content).cleaned
        let toolOutputs = await context.effects.toolOutputs
        let toolsInvoked = await context.effects.toolsInvoked
        let provenance = NumericProvenanceVerifier.verify(
            responseText: cleaned,
            toolOutputs: toolOutputs,
            userQuestion: question
        )
        let proposal = await context.effects.workoutProposal
        let memProposal = await context.effects.memoryProposal

        return CoachMessage(
            role: .assistant,
            text: provenance.annotatedText,
            engineLabel: "Apple 端侧模型",
            evidenceMetric: CoachAgentOrchestrator.inferredMetric(from: question),
            workoutProposal: proposal,
            memorySavedNote: memProposal.map { "待你确认记忆 [\($0.tier.titleLabel)]：\($0.content)" },
            memoryProposal: memProposal,
            unverifiedNumbers: provenance.unverifiedTokens,
            toolsInvoked: toolsInvoked
        )
    }
    #endif
}

public extension DependencyValues {
    var coachAIClient: CoachAIClient {
        get { self[CoachAIClient.self] }
        set { self[CoachAIClient.self] = newValue }
    }
}

// MARK: - Apple FoundationModels Tool Adapters

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
private struct FMTodayContextTool: Tool {
    let name = "get_today_context"
    let description = "查询今日四态恢复、睡眠、负荷、ACWR与体征"
    let context: AgentExecutionContext

    @Generable
    struct Arguments {
        @Guide(description: "聚焦维度，例如 all")
        var aspect: String
    }

    func call(arguments: Arguments) async throws -> String {
        _ = arguments.aspect
        return await CoachToolRegistry.execute(name: "get_today_context", argumentsJSON: "{}", context: context)
    }
}

@available(iOS 26.0, macOS 26.0, *)
private struct FMWorkoutsAndMusclesTool: Tool {
    let name = "get_workouts_and_muscles"
    let description = "查询近期Watch训练与肌群启发式恢复状态"
    let context: AgentExecutionContext

    @Generable
    struct Arguments {
        @Guide(description: "回看天数，例如 7")
        var days: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await CoachToolRegistry.execute(
            name: "get_workouts_and_muscles",
            argumentsJSON: "{\"days\":\(max(1, arguments.days))}",
            context: context
        )
    }
}

@available(iOS 26.0, macOS 26.0, *)
private struct FMSleepDetailTool: Tool {
    let name = "get_sleep_detail"
    let description = "查询昨晚睡眠时长与分期详情"
    let context: AgentExecutionContext

    @Generable
    struct Arguments {
        @Guide(description: "日期YYYY-MM-DD或today")
        var day: String
    }

    func call(arguments: Arguments) async throws -> String {
        let json = arguments.day == "today" ? "{}" : "{\"day\":\"\(arguments.day)\"}"
        return await CoachToolRegistry.execute(name: "get_sleep_detail", argumentsJSON: json, context: context)
    }
}

@available(iOS 26.0, macOS 26.0, *)
private struct FMProposeMemoryTool: Tool {
    let name = "propose_memory"
    let description = "生成一条待确认的profile或activeConstraint记忆提案"
    let context: AgentExecutionContext

    @Generable
    struct Arguments {
        @Guide(description: "profile 或 activeConstraint")
        var tier: String
        @Guide(description: "记忆内容")
        var content: String
    }

    func call(arguments: Arguments) async throws -> String {
        let escaped = arguments.content.replacingOccurrences(of: "\"", with: "\\\"")
        let json = "{\"tier\":\"\(arguments.tier)\",\"content\":\"\(escaped)\",\"expiresDays\":14}"
        return await CoachToolRegistry.execute(name: "propose_memory", argumentsJSON: json, context: context)
    }
}

@available(iOS 26.0, macOS 26.0, *)
private struct FMProposePlanTool: Tool {
    let name = "propose_plan_change"
    let description = "生成一条待确认的今日力量或恢复课表提案"
    let context: AgentExecutionContext

    @Generable
    struct Arguments {
        @Guide(description: "课表标题")
        var title: String
        @Guide(description: "强度标签")
        var focusTag: String
        @Guide(description: "动作ID逗号列表")
        var exerciseIDsCSV: String
        @Guide(description: "强度系数 0.6~1.1")
        var intensityMultiplier: Double
        @Guide(description: "组间休息秒数")
        var restSeconds: Int
        @Guide(description: "推荐理由")
        var rationale: String
    }

    func call(arguments: Arguments) async throws -> String {
        let payload = "{\"title\":\"\(arguments.title)\",\"focusTag\":\"\(arguments.focusTag)\",\"exerciseIDsCSV\":\"\(arguments.exerciseIDsCSV)\",\"intensityMultiplier\":\(arguments.intensityMultiplier),\"restSeconds\":\(arguments.restSeconds),\"rationale\":\"\(arguments.rationale)\"}"
        return await CoachToolRegistry.execute(name: "propose_plan_change", argumentsJSON: payload, context: context)
    }
}
#endif
