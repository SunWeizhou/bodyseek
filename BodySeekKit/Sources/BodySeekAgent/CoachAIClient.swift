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
        1. 先调用只读工具核实数据（get_today_context / get_metric_trend / get_weekly_recovery_evidence / get_workouts_and_muscles / get_sleep_detail / get_patterns / find_similar_days / get_eating_context / get_personal_forecast / search_exercise_catalog）。
        2. 严格区分四态真值：missing / excluded 的指标绝不当作 0，也绝不编造任何健康数字；回答中引用的每个健康数值都必须直接来自本轮工具返回结果。
        3. 肌群恢复百分比必须标注为「启发式估计」（recovery-heuristic-v1）；用户手打用力（EffortUser）与 Apple 系统估算（Estimated）分开陈述。
        4. get_patterns、find_similar_days 与 get_personal_forecast 仅为相关性、历史相似日类比或带不确定度区间的个人统计预测，绝不宣称“证明了因果关系”、不冒充医学诊断，也不进行反事实捏造。
        5. 任何写操作只能通过提案工具生成待确认卡片：
           - 训练课表建议 -> search_exercise_catalog 后调用 propose_plan_change
           - 长期偏好/短期伤病约束记忆 -> propose_memory（activeConstraint 默认 14 天过期；未经 confirmed 的 pattern_finding 不得提出 verifiedPattern）
           - 手表力量训练一句话标定 -> propose_workout_annotation
        6. 绝对不要输出 <tool_call>、<|DSML|> 等 XML 或内部标签，直接用简洁克制的中文回复。
        7. 按工具提供的日期范围与单位比较。历史训练标注中的「今天」「昨天」以该条训练的 dayKey 为准。把用户确认记录、设备记录、估算和建议分开写。饮食未完成时只谈已记录部分，缺失日不计作零。饮食工具返回热量区间时优先陈述上下限；kcal 中点仅供汇总。有缺项时称为已记录小计。历史聊天只用于理解指代，请用本轮工具核对数据。
        8. 先用一小段话回答问题。信息较多时用 Markdown 小标题和短列表分段，只在需要比较多项数据时使用简短表格。
        9. 当用户问「这周/近 7 天恢复为什么下降」或比较最近一周时，必须调用 get_weekly_recovery_evidence，不要用 get_metric_trend 的 30 天中位数代替。
           - 先回答恢复是否下降、下降多少、与哪个 7 天/28 天窗口比较；再看覆盖率与样本数是否足以判断。
           - 然后分别列出：有证据的因素（睡眠、训练负荷、体感、饮食）、只是线索的因素、以及数据缺口。不要把共现写成因果。
           - 每个关键数字带上日期或窗口、指标和单位。覆盖率与统计样本数分开表述。
           - 进食时刻未知时保持未知；recorded_at 只是保存时间，绝不能当作进食时间。咖啡只能作为未确认的观察线索。

        与本轮对话相关的已激活三层记忆：
        \(memoryLines)

        今日背景摘要（请以工具返回的四态 JSON 为准）：
        \(context.snapshot.today.factualSummary)
        """
    }

    static func conversationTurns(_ context: AgentExecutionContext) -> [OpenAIChatMessage] {
        context.conversationHistory.map {
            OpenAIChatMessage(role: $0.role.rawValue, content: conversationText($0, limit: 1_200))
        }
    }

    static func conversationText(_ message: CoachMessage, limit: Int) -> String {
        guard let template = message.workoutProposal?.template else { return String(message.text.prefix(limit)) }
        let exercises = template.exercises.map { exercise in
            let name = ExerciseCatalog.find(id: exercise.exerciseID)?.name ?? exercise.exerciseID
            return "\(name) \(exercise.targetSets)组×\(exercise.targetReps)次"
        }.joined(separator: "，")
        let summary = "上轮训练提案 \(template.title) · \(exercises)"
        let plan = summary.prefix(limit * 2 / 3)
        return String(message.text.prefix(limit - plan.count - 1)) + "\n" + plan
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
        ] + conversationTurns(context) + [OpenAIChatMessage(role: "user", content: question)]

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
        if lower.contains("这周") || lower.contains("近7天") || lower.contains("近 7 天")
            || (lower.contains("恢复") && (lower.contains("下降") || lower.contains("为什么"))) {
            _ = await CoachToolRegistry.execute(
                name: "get_weekly_recovery_evidence",
                argumentsJSON: "{}",
                context: context
            )
            let answer: String
            if let evidence = try? WeeklyRecoveryEvidenceBuilder.build(
                endDayKey: nil,
                asOf: context.asOf,
                context: context
            ) {
                let recovery = evidence.recovery
                let target = recovery.targetMedian.map(String.init) ?? "--"
                let control = recovery.controlMedian.map(String.init) ?? "--"
                let delta = recovery.delta.map { $0 > 0 ? "+\($0)" : "\($0)" } ?? "--"
                let direction = switch recovery.direction {
                case "declined": "下降"
                case "improved": "上升"
                case "stable": "基本持平"
                default: "证据不足"
                }
                answer = "最近 7 天恢复中位 \(target) 分，此前 28 天中位 \(control) 分，变化 \(delta) 分，方向：\(direction)。对照窗有效样本 \(recovery.controlSampleCount)/28 天。这是固定窗口的点估计，不构成因果或显著性结论。"
                    + (recovery.evidenceSufficient ? "" : " 对照窗样本不足，不能判断趋势。")
            } else {
                answer = "近 7 天恢复证据不足，暂不能判断是否下降或给出原因。"
            }
            let toolOutputs = await context.effects.toolOutputs
            let toolsInvoked = await context.effects.toolsInvoked
            let provenance = NumericProvenanceVerifier.verify(
                responseText: answer,
                toolOutputs: toolOutputs,
                userQuestion: question
            )
            return CoachMessage(
                role: .assistant,
                text: provenance.annotatedText,
                engineLabel: "预览演示 · 四态工具引擎",
                evidenceMetric: .recovery,
                unverifiedNumbers: provenance.unverifiedTokens,
                toolsInvoked: toolsInvoked
            )
        }
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
        let date = todayJSON.isEmpty ? "" : "（\(today.dayKey.isoString)）"
        let observations = parts.map { "- \($0)" }.joined(separator: "\n")
        let rawReply = "## 身体状态简报\n\n已调用工具核实四态观测\(date)。\n\n\(observations)"

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
        let annotationCandidates = await context.effects.workoutAnnotationCandidates

        return CoachMessage(
            role: .assistant,
            text: provenance.annotatedText,
            engineLabel: "预览演示 · 四态工具引擎",
            evidenceMetric: inferredMetric(from: question),
            workoutProposal: workoutProposal,
            memorySavedNote: memoryProposal.map { "待你确认记忆 [\($0.tier.titleLabel)]：\($0.content)" },
            memoryProposal: memoryProposal,
            workoutAnnotationProposal: annotationProposal,
            workoutAnnotationCandidates: annotationCandidates,
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
    public var analyzeMeal: @Sendable (_ text: String, _ jpeg: Data?) async throws -> [MealDraftCandidate] = { _, _ in
        throw MealDraftAnalysisError.unconfigured
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
                    return .generated(
                        text: "今天练到还有余力就好，不必加量。",
                        engineName: "预览模式"
                    )
                }

                let prompt = """
                为今日看板下面的 AI 建议写一句纯中文，最多 45 字。
                今日日期为 \(context.asOf.physiologicalDayKey().isoString)。先核实今日数据与近 7 天训练。
                按训练记录的 dayKey 区分日期，历史记录不得当作今天完成的训练。只给一个今天能做的行动，用日常说法。
                不加标题和列表，不重复看板分数，不用 HRV、ACWR、RPE 等缩写。
                如果数据不足以给建议，说清缺什么。有证据表明无需调整时，直接说可维持原计划。
                """
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
            analyzeMeal: { text, jpeg in
                if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard") {
                    return [
                        .init(name: "白米饭", amount: 150, unit: "g", meal: .lunch),
                        .init(name: "水煮蛋", amount: 100, unit: "g", meal: .breakfast,
                              reportedPortion: "2 个", isEstimatedPortion: true),
                        .init(name: "燕麦", amount: 20, unit: "g", meal: .breakfast,
                              reportedPortion: "2 勺", isEstimatedPortion: true,
                              additionalEstimates: ["diet_minerals::镁": 20, "diet_vitamins::B1": 0.04]),
                        .init(name: "火锅", amount: nil, unit: nil, meal: .dinner,
                              reportedPortion: "人均 ¥120"),
                        .init(name: "少甜混合果汁", amount: 1_000, unit: "ml", meal: .dinner,
                              reportedPortion: "1 L"),
                        .init(name: "浓缩咖啡", amount: nil, unit: nil, meal: .snack,
                              reportedPortion: "4 份单份浓缩"),
                    ]
                }
                let key = try KeychainCredentialStore.live.loadAPIKey()
                let config = storedConfiguration()
                return try await httpClient.analyzeMeal(
                    endpointURL: config.endpointURL, apiKey: key, modelName: config.modelName, input: text, jpeg: jpeg
                )
            },
            loadAPIKey: {
                try KeychainCredentialStore.live.loadAPIKey()
            },
            saveAPIKey: { key in
                try KeychainCredentialStore.live.saveAPIKey(key)
            },
            loadConfig: { storedConfiguration() },
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

    private static func storedConfiguration() -> CoachAIConfig {
        CoachAIConfig(
            endpointURL: UserDefaults.standard.string(forKey: endpointStorageKey) ?? "https://api.deepseek.com/v1",
            modelName: UserDefaults.standard.string(forKey: modelStorageKey) ?? "deepseek-chat"
        )
    }

    public static let previewValue = CoachAIClient(
        reply: { question, context in
            await CoachAgentOrchestrator.runPreviewFixture(question: question, context: context)
        },
        generateBriefing: { _ in
            .generated(
                text: "今天练到还有余力就好，不必加量。",
                engineName: "预览模式"
            )
        },
        analyzeMeal: { _, _ in
            [.init(name: "白米饭", amount: 150, unit: "g"), .init(name: "鸡蛋", amount: nil, unit: nil)]
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
            FMMetricTrendTool(context: context),
            FMWeeklyRecoveryEvidenceTool(context: context),
            FMEatingContextTool(context: context),
            FMProposeMemoryTool(context: context),
            FMProposePlanTool(context: context),
        ]
        let session: LanguageModelSession
        if context.conversationHistory.isEmpty {
            session = LanguageModelSession(model: .default, tools: tools, instructions: instructions)
        } else {
            let definitions = tools.map { Transcript.ToolDefinition(tool: $0) }
            let instruction = Transcript.Entry.instructions(.init(
                segments: [.text(.init(content: instructions))], toolDefinitions: definitions
            ))
            let turns: [Transcript.Entry] = context.conversationHistory.suffix(4).map { message in
                let segments: [Transcript.Segment] = [.text(.init(content: CoachAgentOrchestrator.conversationText(message, limit: 450)))]
                switch message.role {
                case .user: return .prompt(.init(segments: segments))
                case .assistant: return .response(.init(assetIDs: [], segments: segments))
                }
            }
            session = LanguageModelSession(model: .default, tools: tools, transcript: Transcript(entries: [instruction] + turns))
        }
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
        let annotationProposal = await context.effects.workoutAnnotationProposal
        let annotationCandidates = await context.effects.workoutAnnotationCandidates

        return CoachMessage(
            role: .assistant,
            text: provenance.annotatedText,
            engineLabel: "Apple 端侧模型",
            evidenceMetric: CoachAgentOrchestrator.inferredMetric(from: question),
            workoutProposal: proposal,
            memorySavedNote: memProposal.map { "待你确认记忆 [\($0.tier.titleLabel)]：\($0.content)" },
            memoryProposal: memProposal,
            workoutAnnotationProposal: annotationProposal,
            workoutAnnotationCandidates: annotationCandidates,
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
private struct FMMetricTrendTool: Tool {
    let name = "get_metric_trend"
    let description = "查询指标随时间的变化与数据覆盖"
    let context: AgentExecutionContext

    @Generable
    struct Arguments {
        @Guide(description: "recovery, sleep, strain, stress, energy")
        var metric: String
        @Guide(description: "7d, 30d, 6m, 3y")
        var horizon: String
    }

    func call(arguments: Arguments) async throws -> String {
        let json = try JSONEncoder().encode(["metric": arguments.metric, "horizon": arguments.horizon])
        return await CoachToolRegistry.execute(name: name, argumentsJSON: String(decoding: json, as: UTF8.self),
                                               context: context)
    }
}

@available(iOS 26.0, macOS 26.0, *)
private struct FMWeeklyRecoveryEvidenceTool: Tool {
    let name = "get_weekly_recovery_evidence"
    let description = "比较最近 7 天与此前 28 天的恢复、睡眠、训练、体感和饮食，返回逐日观测、覆盖率与四态计数"
    let context: AgentExecutionContext

    @Generable
    struct Arguments {
        @Guide(description: "结束日 YYYY-MM-DD；留空表示当前生理日")
        var endDayKey: String
    }

    func call(arguments: Arguments) async throws -> String {
        let key = arguments.endDayKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let args = key.isEmpty ? "{}" : "{\"end_day_key\":\"\(key)\"}"
        return await CoachToolRegistry.execute(name: name, argumentsJSON: args, context: context)
    }
}

@available(iOS 26.0, macOS 26.0, *)
private struct FMEatingContextTool: Tool {
    let name = "get_eating_context"
    let description = "查询近期饮食摄入、采用的营养目标、估算与缺项"
    let context: AgentExecutionContext

    @Generable
    struct Arguments {
        @Guide(description: "回看天数，1 到 30")
        var days: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await CoachToolRegistry.execute(name: name, argumentsJSON: "{\"days\":\(arguments.days)}", context: context)
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
