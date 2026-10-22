import Foundation

enum DeepSeekTextModel: String, CaseIterable, Sendable {
    static let storageKey = "vela_coach_text_model"

    case flash = "DeepSeek V4 Flash"
    case pro = "DeepSeek V4 Pro"

    init(displayName: String) {
        self = Self(rawValue: displayName) ?? .pro
    }

    static var stored: DeepSeekTextModel {
        DeepSeekTextModel(
            displayName: UserDefaults.standard.string(forKey: storageKey) ?? DeepSeekTextModel.pro.rawValue
        )
    }

    var apiIdentifier: String {
        switch self {
        case .flash: return "deepseek-flash"
        case .pro: return "deepseek-v4-pro"
        }
    }
}

enum CoachReasoningMode: String, CaseIterable, Sendable {
    static let storageKey = "vela_coach_reasoning_mode"
    case fast
    case thinking
    case adaptive

    static var stored: CoachReasoningMode {
        CoachReasoningMode(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "adaptive") ?? .adaptive
    }

    var displayName: String {
        switch self {
        case .fast: "快速"
        case .thinking: "深度思考"
        case .adaptive: "自适应"
        }
    }

    var detail: String {
        switch self {
        case .fast: "优先低延迟，使用 Flash 模型。"
        case .thinking: "始终使用 Pro 模型处理复杂分析。"
        case .adaptive: "简短问题使用 Flash，完整报告与复杂分析使用 Pro。"
        }
    }

    func model(for policy: ResponseLengthPolicy) -> DeepSeekTextModel {
        switch self {
        case .fast: .flash
        case .thinking: .pro
        case .adaptive:
            switch policy {
            case .full: .pro
            case .casual, .focused: .flash
            }
        }
    }
}

enum DeepSeekStreamSignals {
    /// The wire field is `finish_reason`. A synthesized `finishReason` key never matches it.
    static func finishReason(inJSON json: Data) -> String? {
        guard let chunk = try? JSONDecoder().decode(DeepSeekStreamChunk.self, from: json) else { return nil }
        return chunk.choices.first?.finishReason
    }
}

enum DeepSeekStreamCompletion: Equatable {
    case complete
    case truncated
    case incomplete

    /// `length` is a real finish, not a missing `[DONE]`. Other finishes still
    /// need the SSE terminator or an explicit `stop`.
    static func resolve(didReceiveDone: Bool, finishReason: String?) -> DeepSeekStreamCompletion {
        if finishReason == "length" { return .truncated }
        if didReceiveDone || finishReason == "stop" { return .complete }
        return .incomplete
    }
}

struct DeepSeekProvider: LLMProvider {
    /// Cap generation length so a long-running/summarizing request can't
    /// produce an unbounded response (cost + latency + provider context limits).
    static let defaultMaxTokens = 2048

    var apiKey: String
    var model: String
    var endpoint: URL

    init(
        apiKey: String,
        model: String = DeepSeekTextModel.stored.apiIdentifier,
        endpoint: URL = URL(string: "https://api.deepseek.com/chat/completions")!
    ) {
        self.apiKey = apiKey
        self.model = model
        self.endpoint = endpoint
    }

    func complete(request: LLMRequest) async throws -> LLMResponse {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMProviderError.missingAPIKey
        }

        let messages: [ChatMessage] = [
            ChatMessage(role: .system, content: request.systemPrompt),
            ChatMessage(role: .user, content: "\(request.userPrompt)\n\nContext:\n\(request.contextJSON)")
        ]
        return try await chat(messages: messages, tools: request.tools)
    }

    /// Non-streaming chat with optional tools. Returns content and/or tool_calls.
    func chat(messages: [ChatMessage], tools: [[String: Value]]? = nil) async throws -> LLMResponse {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMProviderError.missingAPIKey
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.timeoutInterval = 120

        let sampling = Self.requestSampling()
        let body = DeepSeekChatRequest(
            model: model,
            messages: messages.map { msg in
                DeepSeekChatRequest.Message(
                    role: msg.role.apiValue,
                    content: msg.content.isEmpty ? nil : msg.content,
                    toolCalls: msg.toolCalls?.map { tc in
                        DeepSeekChatRequest.ToolCall(id: tc.id, type: "function", function: .init(name: tc.name, arguments: tc.arguments))
                    },
                    toolCallId: msg.toolCallId,
                    reasoningContent: msg.reasoningContent
                )
            },
            temperature: sampling.temperature,
            stream: false,
            tools: tools?.map { ToolDef(from: $0) },
            toolChoice: tools != nil ? "auto" : nil,
            maxTokens: sampling.maxTokens,
            thinking: sampling.thinking
        )
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await PrivateAIURLSession.shared.data(for: urlRequest)
        } catch {
            throw LLMProviderError.classify(error)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMProviderError.httpFailure(statusCode: httpResponse.statusCode, body: body)
        }

        let decoded = try JSONDecoder().decode(DeepSeekChatResponse.self, from: data)
        let choice = decoded.choices.first
        let content = choice?.message.content ?? ""
        let reasoningContent = choice?.message.reasoningContent

        var toolCalls: [ToolCall]? = nil
        if let rawCalls = choice?.message.toolCalls, !rawCalls.isEmpty {
            toolCalls = rawCalls.map { tc in
                ToolCall(id: tc.id, name: tc.function.name, arguments: tc.function.arguments)
            }
        }

        return LLMResponse(content: content, toolCalls: toolCalls, reasoningContent: reasoningContent)
    }

    func streamChat(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw LLMProviderError.missingAPIKey
                    }

                    var urlRequest = URLRequest(url: endpoint)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    urlRequest.timeoutInterval = 180
                    let sampling = Self.requestSampling()
                    urlRequest.httpBody = try JSONEncoder().encode(
                        DeepSeekChatRequest(
                            model: model,
                            messages: messages.map { msg in
                                DeepSeekChatRequest.Message(
                                    role: msg.role.apiValue,
                                    content: msg.content.isEmpty ? nil : msg.content,
                                    toolCalls: msg.toolCalls?.map { tc in
                                        DeepSeekChatRequest.ToolCall(id: tc.id, type: "function", function: .init(name: tc.name, arguments: tc.arguments))
                                    },
                                    toolCallId: msg.toolCallId,
                                    reasoningContent: msg.reasoningContent
                                )
                            },
                            temperature: sampling.temperature,
                            stream: true,
                            tools: nil,
                            toolChoice: nil,
                            maxTokens: sampling.maxTokens,
                            thinking: sampling.thinking
                        )
                    )

                    let (bytes, response) = try await PrivateAIURLSession.shared.bytes(for: urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw LLMProviderError.invalidResponse
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line + "\n"
                        }
                        throw LLMProviderError.httpFailure(statusCode: httpResponse.statusCode, body: errorBody)
                    }

                    var didReceiveDone = false
                    var finishReason: String?
                    for try await line in bytes.lines {
                        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmedLine == "data: [DONE]" || trimmedLine == "data:[DONE]" {
                            didReceiveDone = true
                            break
                        }
                        guard line.hasPrefix("data: ") else { continue }
                        let json = String(line.dropFirst(6))
                        guard let data = json.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(DeepSeekStreamChunk.self, from: data) else { continue }
                        if let reason = chunk.choices.first?.finishReason {
                            finishReason = reason
                        }
                        guard let delta = chunk.choices.first?.delta.content,
                              !delta.isEmpty else { continue }
                        continuation.yield(delta)
                    }
                    switch DeepSeekStreamCompletion.resolve(
                        didReceiveDone: didReceiveDone,
                        finishReason: finishReason
                    ) {
                    case .complete:
                        continuation.finish()
                    case .truncated:
                        throw LLMProviderError.responseTruncated
                    case .incomplete:
                        throw LLMProviderError.invalidResponse
                    }
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: LLMProviderError.classify(error))
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Thinking mode ignores temperature. Non-thinking calls keep a low temperature
    /// and a shorter cap; thinking calls get room for the reasoning trace.
    private static func requestSampling() -> (temperature: Double?, maxTokens: Int, thinking: DeepSeekChatRequest.Thinking?) {
        if CoachReasoningMode.stored == .thinking {
            return (nil, 8192, .init(type: "enabled"))
        }
        return (0.4, defaultMaxTokens, nil)
    }
}

// MARK: - Request/Response Codable Types

private struct DeepSeekChatRequest: Encodable {
    var model: String
    var messages: [Message]
    var temperature: Double?
    var stream: Bool
    var tools: [ToolDef]?
    var toolChoice: String?
    var maxTokens: Int?
    var thinking: Thinking?

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream, tools, thinking
        case toolChoice = "tool_choice"
        case maxTokens = "max_tokens"
    }

    struct Thinking: Encodable {
        var type: String
    }

    struct Message: Encodable {
        var role: String
        var content: String?
        var toolCalls: [ToolCall]?
        var toolCallId: String?
        var reasoningContent: String?

        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCalls = "tool_calls"
            case toolCallId = "tool_call_id"
            case reasoningContent = "reasoning_content"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(role, forKey: .role)
            try container.encodeIfPresent(content, forKey: .content)
            try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
            try container.encodeIfPresent(toolCallId, forKey: .toolCallId)
            try container.encodeIfPresent(reasoningContent, forKey: .reasoningContent)
        }
    }

    struct ToolCall: Encodable {
        var id: String
        var type: String
        var function: FunctionDef

        struct FunctionDef: Encodable {
            var name: String
            var arguments: String
        }
    }
}

private struct ToolDef: Encodable {
    var type: String = "function"
    var function: FunctionSchema

    struct FunctionSchema: Encodable {
        var name: String
        var description: String
        var parameters: [String: Value]
    }

    init(from dict: [String: Value]) {
        let fnDict: [String: Value] = {
            if case .object(let v) = dict["function"] { return v }
            return [:]
        }()
        let nameStr: String = {
            if case .string(let v) = fnDict["name"] { return v }
            return ""
        }()
        let descStr: String = {
            if case .string(let v) = fnDict["description"] { return v }
            return ""
        }()
        let params: [String: Value] = {
            if case .object(let v) = fnDict["parameters"] { return v }
            return [:]
        }()
        self.function = FunctionSchema(
            name: nameStr,
            description: descStr,
            parameters: params
        )
    }
}

private struct DeepSeekChatResponse: Decodable {
    var choices: [Choice]

    struct Choice: Decodable {
        var message: ResponseMessage
        var finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    struct ResponseMessage: Decodable {
        var content: String?
        var toolCalls: [ResponseToolCall]?
        var reasoningContent: String?

        enum CodingKeys: String, CodingKey {
            case content
            case toolCalls = "tool_calls"
            case reasoningContent = "reasoning_content"
        }
    }

    struct ResponseToolCall: Decodable {
        var id: String
        var type: String
        var function: FunctionCall
    }

    struct FunctionCall: Decodable {
        var name: String
        var arguments: String
    }
}

private struct DeepSeekStreamChunk: Decodable {
    var choices: [Choice]

    struct Choice: Decodable {
        var delta: Delta
        var finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Decodable {
        var content: String?
    }
}

private extension ChatMessage.Role {
    var apiValue: String {
        switch self {
        case .system: return "system"
        case .user: return "user"
        case .assistant: return "assistant"
        case .tool: return "tool"
        }
    }
}
