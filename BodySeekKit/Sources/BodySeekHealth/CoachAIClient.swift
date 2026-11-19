import BodySeekCore
import Dependencies
import DependenciesMacros
import Foundation
import os
import SpeziLLM
import SpeziLLMOpenAI

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

@DependencyClient
public struct CoachAIClient: Sendable {
    public var reply: @Sendable (_ question: String, _ context: AgentExecutionContext) async -> CoachMessage = { question, context in
        CoachMessage(
            role: .assistant,
            text: "当前处于离线预览状态（\(context.snapshot.today.factualSummary)）。"
        )
    }
    public var generateBriefing: @Sendable (_ context: AgentExecutionContext) async -> AIBriefingStatus = { _ in
        .unconfigured(reason: "连接 DeepSeek / OpenAI 接口或在支持 Apple 智能的设备开启端侧 AI 简报")
    }
    public var loadAPIKey: @Sendable () throws -> String = { "" }
    public var saveAPIKey: @Sendable (_ key: String) throws -> Void = { _ in }
    public var loadConfig: @Sendable () -> CoachAIConfig = { CoachAIConfig() }
    public var saveConfig: @Sendable (_ config: CoachAIConfig) -> Void = { _ in }
    public var testConnection: @Sendable (_ apiKey: String, _ config: CoachAIConfig) async -> String? = { _, _ in nil }
}

extension CoachAIClient: DependencyKey {
    public static let endpointStorageKey = "bodyseek.coach.endpoint"
    public static let modelStorageKey = "bodyseek.coach.model"
    private static let logger = Logger(subsystem: "com.sunweizhou.Vela4", category: "CoachAI")

    public static let liveValue = CoachAIClient(
        reply: { question, context in
            if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard") {
                return await previewAgentReply(question: question, context: context)
            }

            var keychainWarning: String?
            let apiKey: String
            do {
                apiKey = try KeychainCredentialStore.live.loadAPIKey()
            } catch {
                logger.error("Failed reading API key from Keychain: \(error.localizedDescription, privacy: .public)")
                keychainWarning = "读取 Keychain 凭据失败：\(error.localizedDescription)"
                apiKey = ""
            }

            #if os(iOS)
            if !apiKey.isEmpty {
                let modelName = UserDefaults.standard.string(forKey: modelStorageKey) ?? "deepseek-chat"
                let endpoint = UserDefaults.standard.string(forKey: endpointStorageKey) ?? "https://api.deepseek.com/v1"
                var speziErrorDescription: String?
                if let runner = await MainActor.run(body: { BodySeekHealthBridgeModule.shared.currentLLMRunner }) {
                    do {
                        return try await runSpeziOpenAIAgent(
                            runner: runner,
                            apiKey: apiKey,
                            modelName: modelName,
                            question: question,
                            context: context
                        )
                    } catch {
                        speziErrorDescription = error.localizedDescription
                        logger.warning("SpeziOpenAI runner failed (\(error.localizedDescription, privacy: .public)); falling back to direct OpenAI-compatible client.")
                    }
                }
                do {
                    return try await runOpenAICompatibleAgent(
                        endpointURL: endpoint,
                        apiKey: apiKey,
                        modelName: modelName,
                        question: question,
                        context: context
                    )
                } catch {
                    let detail = speziErrorDescription.map { "Spezi: \($0); 直连: \(error.localizedDescription)" }
                        ?? error.localizedDescription
                    logger.error("Cloud AI reply failed: \(detail, privacy: .public)")
                    return CoachMessage(
                        role: .assistant,
                        text: "云端 AI 请求失败：\(detail)\n\n请检查设置中的 API Endpoint、模型名称与 Keychain 中的 API Key。\n客观数据参考：\(context.snapshot.today.factualSummary)",
                        engineLabel: "云端连接异常",
                        evidenceMetric: inferredMetric(from: question)
                    )
                }
            }
            #endif

            var localFailureNote: String?
            #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                let model = SystemLanguageModel.default
                if case .available = model.availability {
                    do {
                        return try await runFoundationModelsAgent(
                            model: model,
                            question: question,
                            context: context
                        )
                    } catch {
                        localFailureNote = "端侧 Apple 智能执行失败：\(error.localizedDescription)"
                        logger.error("FoundationModels reply failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
            #endif

            let extraDiagnostics = [keychainWarning, localFailureNote]
                .compactMap { $0 }
                .joined(separator: "\n")
            let diagnosticBlock = extraDiagnostics.isEmpty ? "" : "\n诊断信息：\(extraDiagnostics)\n"

            return CoachMessage(
                role: .assistant,
                text: """
                未检测到可用的 AI 模型。BodySeek 不再提供硬编码的规则文案，请你任选其一启用真 AI 驱动：
                1. 在「设置」中填入 DeepSeek 或 OpenAI 兼容 API Key；
                2. 在支持 Apple Intelligence 的真机上开启「Apple 智能」端侧模型。
                \(diagnosticBlock)
                客观数据参考：\(context.snapshot.today.factualSummary)
                """,
                engineLabel: extraDiagnostics.isEmpty ? "需要启用 AI" : "AI 引擎不可用",
                evidenceMetric: inferredMetric(from: question)
            )
        },
        generateBriefing: { context in
            if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard") {
                let day = context.snapshot.today
                return .generated(
                    text: "示例简报：今日恢复 \(day.recovery.formattedScore)，近 7 天训练负荷比 \(context.snapshot.trainingLoad.acwrRatio.map { String(format: "%.2f", $0) } ?? "--")（\(context.snapshot.trainingLoad.zone.title)），建议按中等 RPE 节奏完成今日分化训练。",
                    engineName: "预览模式"
                )
            }

            let prompt = "基于下方提供的今日身体数据与近7天训练负荷，直接用不超过65个汉字给出一句精准、可执行的今日状态点评与训练取向建议。只输出纯中文文本，不要调用工具，不要输出任何JSON或XML标签。"
            var keychainFailure: String?
            let apiKey: String
            do {
                apiKey = try KeychainCredentialStore.live.loadAPIKey()
            } catch {
                logger.error("Failed reading API key during briefing: \(error.localizedDescription, privacy: .public)")
                keychainFailure = "Keychain 读取失败：\(error.localizedDescription)"
                apiKey = ""
            }

            #if os(iOS)
            if !apiKey.isEmpty {
                let modelName = UserDefaults.standard.string(forKey: modelStorageKey) ?? "deepseek-chat"
                let endpoint = UserDefaults.standard.string(forKey: endpointStorageKey) ?? "https://api.deepseek.com/v1"
                if let runner = await MainActor.run(body: { BodySeekHealthBridgeModule.shared.currentLLMRunner }) {
                    do {
                        let msg = try await runSpeziOpenAIAgent(
                            runner: runner,
                            apiKey: apiKey,
                            modelName: modelName,
                            question: prompt,
                            context: context
                        )
                        return .generated(text: msg.text, engineName: modelName)
                    } catch {
                        logger.warning("SpeziOpenAI briefing failed (\(error.localizedDescription, privacy: .public)); falling back to direct client.")
                    }
                }
                do {
                    let msg = try await runOpenAICompatibleAgent(
                        endpointURL: endpoint,
                        apiKey: apiKey,
                        modelName: modelName,
                        question: prompt,
                        context: context
                    )
                    return .generated(text: msg.text, engineName: modelName)
                } catch {
                    logger.error("Cloud briefing failed: \(error.localizedDescription, privacy: .public)")
                    return .unconfigured(reason: "云端 AI 连接失败：\(error.localizedDescription)")
                }
            }
            #endif

            var localFailure: String?
            #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                let model = SystemLanguageModel.default
                if case .available = model.availability {
                    do {
                        let msg = try await runFoundationModelsAgent(
                            model: model,
                            question: prompt,
                            context: context
                        )
                        return .generated(text: msg.text, engineName: "Apple 端侧模型")
                    } catch {
                        localFailure = "Apple 端侧简报生成失败：\(error.localizedDescription)"
                        logger.error("FoundationModels briefing failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
            #endif

            let failureNote = [keychainFailure, localFailure].compactMap { $0 }.joined(separator: "；")
            if !failureNote.isEmpty {
                return .unconfigured(reason: failureNote)
            }
            return .unconfigured(reason: "配置 DeepSeek/OpenAI Key 或启用 Apple 智能后，由 AI 实时生成今日简报与处方。")
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
            let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty else {
                return "请先填写 API Key"
            }
            guard let baseURL = DynamicServerURLMiddleware.normalizeBaseURL(config.endpointURL) else {
                return "API Endpoint 格式无效：\(config.endpointURL)"
            }
            let chatURL = baseURL.appendingPathComponent("chat/completions")
            var request = URLRequest(url: chatURL)
            request.httpMethod = "POST"
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
            let body: [String: Any] = [
                "model": config.modelName.trimmingCharacters(in: .whitespacesAndNewlines),
                "messages": [["role": "user", "content": "ping"]],
                "max_tokens": 5,
            ]
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    return "未收到有效 HTTP 响应"
                }
                if (200..<300).contains(http.statusCode) {
                    return nil
                }
                let serverMsg = String(data: data.prefix(240), encoding: .utf8) ?? ""
                return "HTTP \(http.statusCode)：\(serverMsg)"
            } catch {
                logger.error("Connection test failed: \(error.localizedDescription, privacy: .public)")
                return "网络请求失败：\(error.localizedDescription)"
            }
        }
    )

    public static let previewValue = CoachAIClient(
        reply: { question, context in
            await previewAgentReply(question: question, context: context)
        },
        generateBriefing: { context in
            .generated(
                text: "示例简报：恢复 \(context.snapshot.today.recovery.formattedScore)，ACWR 处于\(context.snapshot.trainingLoad.zone.title)，适合维持正常力量刺激。",
                engineName: "预览模式"
            )
        },
        loadAPIKey: { "" },
        saveAPIKey: { _ in },
        loadConfig: { CoachAIConfig() },
        saveConfig: { _ in },
        testConnection: { _, _ in nil }
    )

    // MARK: - Cloud Engine via SpeziLLMOpenAI + Tool Calling

    #if os(iOS)
    private static func runSpeziOpenAIAgent(
        runner: LLMRunner,
        apiKey: String,
        modelName: String,
        question: String,
        context: AgentExecutionContext
    ) async throws -> CoachMessage {
        let systemPrompt = buildSystemPrompt(context: context)
        let schema = LLMOpenAISchema(
            parameters: .init(
                modelType: OpenAIPlatformDefinition.ModelType(rawValue: modelName),
                systemPrompt: systemPrompt,
                modelAccessTest: false,
                overwritingAuthToken: .constant(apiKey)
            )
        ) {
            SpeziPhysiologyTool(context: context)
            SpeziSearchExercisesTool()
            SpeziSaveMemoryTool(context: context)
            SpeziProposeWorkoutTool(context: context)
        }

        let session = runner(with: schema)
        await MainActor.run {
            session.context.append(userInput: question)
        }

        let stream = try await session.generate()
        var accumulated = ""
        for try await token in stream {
            accumulated.append(token)
        }

        let proposal = await context.effects.workoutProposal
        let savedMems = await context.effects.savedMemories
        let memNote = savedMems.last.map { "已更新长期记忆[\($0.category.title)]：\($0.content)" }

        let cleaned = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
        return CoachMessage(
            role: .assistant,
            text: cleaned.isEmpty ? "已调用工具完成分析。" : cleaned,
            engineLabel: "云端智能体 · \(modelName)",
            evidenceMetric: inferredMetric(from: question),
            workoutProposal: proposal,
            memorySavedNote: memNote
        )
    }

    private static func runOpenAICompatibleAgent(
        endpointURL: String,
        apiKey: String,
        modelName: String,
        question: String,
        context: AgentExecutionContext
    ) async throws -> CoachMessage {
        guard let baseURL = DynamicServerURLMiddleware.normalizeBaseURL(endpointURL) else {
            throw NSError(domain: "BodySeekAI", code: 400, userInfo: [NSLocalizedDescriptionKey: "Endpoint 无效：\(endpointURL)"])
        }
        let chatURL = baseURL.appendingPathComponent("chat/completions")
        let report = AgentToolLogic.physiologyAndTrainingReport(context: context)
        let systemPrompt = """
        \(buildSystemPrompt(context: context))

        当前实时生理与训练摘要：
        \(report)
        """
        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": question],
            ],
            "tools": openAIToolsSchema(),
            "tool_choice": "auto",
            "temperature": 0.4,
        ]
        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": question],
        ]
        var finalContent = ""

        for _ in 0..<4 {
            var currentPayload = payload
            currentPayload["messages"] = messages
            request.httpBody = try JSONSerialization.data(withJSONObject: currentPayload)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw NSError(domain: "BodySeekAI", code: -1, userInfo: [NSLocalizedDescriptionKey: "未收到 HTTP 响应"])
            }
            guard (200..<300).contains(http.statusCode) else {
                let errText = String(data: data.prefix(240), encoding: .utf8) ?? ""
                throw NSError(domain: "BodySeekAI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) \(errText)"])
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let choices = json?["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any] ?? [:]
            let rawText = (message["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            if let toolCalls = message["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
                messages.append(message)
                for call in toolCalls {
                    let callID = call["id"] as? String ?? UUID().uuidString
                    let fn = call["function"] as? [String: Any]
                    let name = fn?["name"] as? String ?? ""
                    let argsStr = fn?["arguments"] as? String ?? "{}"
                    let result = await executeOpenAITool(name: name, argumentsJSON: argsStr, context: context)
                    messages.append([
                        "role": "tool",
                        "tool_call_id": callID,
                        "content": result,
                    ])
                }
                continue
            }

            finalContent = stripLeakedToolMarkup(rawText)
            break
        }

        let proposal = await context.effects.workoutProposal
        let savedMems = await context.effects.savedMemories
        let memNote = savedMems.last.map { "已更新长期记忆[\($0.category.title)]：\($0.content)" }

        return CoachMessage(
            role: .assistant,
            text: finalContent.isEmpty ? "已完成分析。" : finalContent,
            engineLabel: "云端 · \(modelName)",
            evidenceMetric: inferredMetric(from: question),
            workoutProposal: proposal,
            memorySavedNote: memNote
        )
    }

    private static func stripLeakedToolMarkup(_ text: String) -> String {
        var cleaned = text
        let patterns = [
            "<tool_call>[\\s\\S]*?</tool_call>",
            "<[｜|]DSML[｜|]calls>[\\s\\S]*?</[｜|]DSML[｜|]calls>",
        ]
        for pattern in patterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [])
                cleaned = regex.stringByReplacingMatches(
                    in: cleaned,
                    range: NSRange(cleaned.startIndex..., in: cleaned),
                    withTemplate: ""
                )
            } catch {
                logger.error("Invalid regex pattern in stripLeakedToolMarkup: \(error.localizedDescription, privacy: .public)")
            }
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func openAIToolsSchema() -> [[String: Any]] {
        [
            [
                "type": "function",
                "function": [
                    "name": "query_physiology_and_training",
                    "description": "查询用户今日恢复、睡眠、负荷、ACWR与近期训练记录。",
                    "parameters": ["type": "object", "properties": [:], "required": []],
                ],
            ],
            [
                "type": "function",
                "function": [
                    "name": "search_exercise_catalog",
                    "description": "按肌群或关键词检索内置动作库 ID 与名称。",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "query": ["type": "string", "description": "部位或动作关键词，如 chest、背、push"],
                        ],
                        "required": ["query"],
                    ],
                ],
            ],
            [
                "type": "function",
                "function": [
                    "name": "save_athlete_memory",
                    "description": "保存用户的伤病限制、训练偏好、作息或长期目标。",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "category": ["type": "string", "description": "injury, goal, preference 或 schedule"],
                            "content": ["type": "string", "description": "记忆内容"],
                        ],
                        "required": ["category", "content"],
                    ],
                ],
            ],
            [
                "type": "function",
                "function": [
                    "name": "propose_adapted_workout",
                    "description": "生成一条可确认的今日结构化训练课表卡片。",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "title": ["type": "string", "description": "课表标题"],
                            "focusTag": ["type": "string", "description": "强度标签，如 减量、维持、推进"],
                            "exerciseIDsCSV": ["type": "string", "description": "逗号分隔的动作 ID"],
                            "intensityMultiplier": ["type": "number", "description": "0.5 到 1.2"],
                            "restSeconds": ["type": "integer", "description": "组间休息秒数"],
                            "rationale": ["type": "string", "description": "推荐依据"],
                        ],
                        "required": ["title", "focusTag", "exerciseIDsCSV", "intensityMultiplier", "restSeconds", "rationale"],
                    ],
                ],
            ],
        ]
    }

    private static func executeOpenAITool(
        name: String,
        argumentsJSON: String,
        context: AgentExecutionContext
    ) async -> String {
        let data = argumentsJSON.data(using: .utf8) ?? Data()
        let args: [String: Any]
        do {
            args = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            logger.error("Tool argument JSON decode failed for \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            args = [:]
        }
        switch name {
        case "query_physiology_and_training":
            return AgentToolLogic.physiologyAndTrainingReport(context: context)
        case "search_exercise_catalog":
            return AgentToolLogic.searchExercises(muscleFilter: args["query"] as? String ?? "")
        case "save_athlete_memory":
            return await AgentToolLogic.saveMemory(
                categoryRaw: args["category"] as? String ?? "preference",
                content: args["content"] as? String ?? "",
                context: context
            )
        case "propose_adapted_workout":
            return await AgentToolLogic.proposeWorkout(
                title: args["title"] as? String ?? "适配训练",
                focusTag: args["focusTag"] as? String ?? "维持",
                exerciseIDsCSV: args["exerciseIDsCSV"] as? String ?? "barbell-bench-press,lat-pulldown",
                intensityMultiplier: (args["intensityMultiplier"] as? Double) ?? 0.85,
                restSeconds: (args["restSeconds"] as? Int) ?? 90,
                rationale: args["rationale"] as? String ?? "结合今日生理状态定制",
                context: context
            )
        default:
            return "未知工具"
        }
    }
    #endif

    // MARK: - On-Device Engine via Apple FoundationModels + Tool Protocol

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private static func runFoundationModelsAgent(
        model: SystemLanguageModel,
        question: String,
        context: AgentExecutionContext
    ) async throws -> CoachMessage {
        let instructions = buildSystemPrompt(context: context)
        let tools: [any Tool] = [
            FMPhysiologyTool(context: context),
            FMSaveMemoryTool(context: context),
            FMProposeWorkoutTool(context: context),
        ]
        let session = LanguageModelSession(
            model: model,
            tools: tools,
            instructions: instructions
        )
        let response = try await session.respond(to: question)
        let proposal = await context.effects.workoutProposal
        let savedMems = await context.effects.savedMemories
        let memNote = savedMems.last.map { "已更新长期记忆[\($0.category.title)]：\($0.content)" }

        return CoachMessage(
            role: .assistant,
            text: response.content.trimmingCharacters(in: .whitespacesAndNewlines),
            engineLabel: "Apple 端侧模型",
            evidenceMetric: inferredMetric(from: question),
            workoutProposal: proposal,
            memorySavedNote: memNote
        )
    }
    #endif

    // MARK: - Deterministic UI-Test Preview Fixture

    private static func previewAgentReply(
        question: String,
        context: AgentExecutionContext
    ) async -> CoachMessage {
        let report = AgentToolLogic.physiologyAndTrainingReport(context: context)
        let wantsWorkout = question.contains("减量") || question.contains("练") || question.contains("课表") || question.contains("调")
        let wantsMemory = question.contains("记住") || question.contains("膝盖") || question.contains("腰")

        var memNote: String?
        if wantsMemory {
            memNote = await AgentToolLogic.saveMemory(
                categoryRaw: AthleteMemoryCategory.injury.rawValue,
                content: question,
                context: context
            )
        }

        if wantsWorkout {
            _ = await AgentToolLogic.proposeWorkout(
                title: "适配减量上肢控制训练",
                focusTag: "AI 处方",
                exerciseIDsCSV: "barbell-bench-press,lat-pulldown,face-pull",
                intensityMultiplier: 0.75,
                restSeconds: 105,
                rationale: "结合今天恢复 \(context.snapshot.today.recovery.formattedScore) 分与昨日上肢推力负荷，建议下调容量至 75% 并延长组间休息。",
                context: context
            )
        }

        let proposal = await context.effects.workoutProposal
        return CoachMessage(
            role: .assistant,
            text: "已检索今日客观生理与 ACWR 状态：\n\(report.split(separator: "\n").prefix(2).joined(separator: "\n"))",
            engineLabel: "预览演示 · 工具引擎",
            evidenceMetric: inferredMetric(from: question),
            workoutProposal: proposal,
            memorySavedNote: memNote
        )
    }

    private static func buildSystemPrompt(context: AgentExecutionContext) -> String {
        """
        你是 BodySeek 的专业生理恢复与力量训练智能体。你拥有查询实时生理/训练工具、保存用户长期记忆工具和生成可确认健身课表的工具。
        规则：
        1. 用简洁、克制、专业的中文回答，绝不编造缺失的健康数据（无数据即为待同步）。
        2. 当用户提到伤病、作息、偏好时，主动调用 save_athlete_memory 记住。
        3. 当用户要求安排、生成或微调今日训练时，先用 search_exercise_catalog 查动作 ID，再调用 propose_adapted_workout 生成结构化处方卡片（需要用户在 App 中点确认，不要宣称已经自动改写）。
        4. 先通过 query_physiology_and_training 确认准确数值。
        背景概要：\(context.snapshot.today.factualSummary)
        """
    }

    private static func inferredMetric(from question: String) -> MetricKind {
        let lower = question.lowercased()
        if lower.contains("睡") || lower.contains("sleep") { return .sleep }
        if lower.contains("负荷") || lower.contains("练") || lower.contains("acwr") { return .strain }
        if lower.contains("压") || lower.contains("stress") { return .stress }
        if lower.contains("能") || lower.contains("电") || lower.contains("energy") { return .energy }
        return .recovery
    }
}

public extension DependencyValues {
    var coachAIClient: CoachAIClient {
        get { self[CoachAIClient.self] }
        set { self[CoachAIClient.self] = newValue }
    }
}
