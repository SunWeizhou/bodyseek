import Foundation
import os

// MARK: - Endpoint Normalization & Privacy Snapshot

public enum EndpointURLNormalizer {
    public static func normalizeBaseURL(_ raw: String) -> URL? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard !trimmed.isEmpty else { return nil }
        for suffix in ["/v1/chat/completions", "/chat/completions"] {
            if trimmed.hasSuffix(suffix) {
                trimmed = String(trimmed.dropLast("/chat/completions".count))
                break
            }
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return URL(string: trimmed)
    }
}

public struct AgentOutboundPayloadSnapshot: Equatable, Hashable, Sendable, Codable {
    public let sentAt: Date
    public let endpointURL: String
    public let modelName: String
    public let messageCount: Int
    public let toolNames: [String]
    public let redactedRequestJSON: String

    public init(
        sentAt: Date = Date(),
        endpointURL: String,
        modelName: String,
        messageCount: Int,
        toolNames: [String],
        redactedRequestJSON: String
    ) {
        self.sentAt = sentAt
        self.endpointURL = endpointURL
        self.modelName = modelName
        self.messageCount = messageCount
        self.toolNames = toolNames
        self.redactedRequestJSON = redactedRequestJSON
    }
}

public actor AgentPayloadRecorder {
    public static let shared = AgentPayloadRecorder()
    private var latestSnapshot: AgentOutboundPayloadSnapshot?

    public init() {}

    public func record(_ snapshot: AgentOutboundPayloadSnapshot) {
        latestSnapshot = snapshot
    }

    public func latest() -> AgentOutboundPayloadSnapshot? {
        latestSnapshot
    }

    public func clear() {
        latestSnapshot = nil
    }
}

// MARK: - Explicit Agent Routing Table (Zero Implicit Fallback)

public enum AgentRoutingIntent: String, Hashable, Sendable {
    case chat
    case briefing
    case workoutParse
}

public enum AgentRoute: Equatable, Hashable, Sendable {
    case previewFixture
    case cloudOpenAICompatible(endpoint: String, model: String)
    case onDeviceFoundationModels
    case unconfigured(reason: String)
}

public enum AgentRoutingPolicy {
    private static let logger = Logger(subsystem: "com.sunweizhou.Vela4", category: "AgentRouting")

    public static func resolve(
        isPreview: Bool,
        apiKey: String,
        endpoint: String,
        modelName: String,
        foundationModelsAvailable: Bool,
        intent: AgentRoutingIntent
    ) -> AgentRoute {
        if isPreview {
            logger.info("Agent route [\(intent.rawValue, privacy: .public)] -> previewFixture")
            return .previewFixture
        }

        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)

        switch intent {
        case .chat, .briefing:
            if !cleanKey.isEmpty {
                let targetModel = cleanModel.isEmpty ? "deepseek-chat" : cleanModel
                let targetEndpoint = cleanEndpoint.isEmpty ? "https://api.deepseek.com/v1" : cleanEndpoint
                logger.info("Agent route [\(intent.rawValue, privacy: .public)] -> cloudOpenAICompatible (\(targetModel, privacy: .public))")
                return .cloudOpenAICompatible(endpoint: targetEndpoint, model: targetModel)
            }
            if foundationModelsAvailable {
                logger.info("Agent route [\(intent.rawValue, privacy: .public)] -> onDeviceFoundationModels")
                return .onDeviceFoundationModels
            }
            logger.info("Agent route [\(intent.rawValue, privacy: .public)] -> unconfigured")
            return .unconfigured(reason: "未配置云端 API Key 且当前设备未启用 Apple 智能端侧模型")

        case .workoutParse:
            if foundationModelsAvailable {
                logger.info("Agent route [workoutParse] -> onDeviceFoundationModels")
                return .onDeviceFoundationModels
            }
            logger.info("Agent route [workoutParse] -> chineseLexiconFallback (on-device unavailable)")
            return .unconfigured(reason: "端侧 Apple 智能不可用，由中文运动词典解析")
        }
    }
}

// MARK: - Markup Scrubber for DeepSeek / Qwen Tool Call Leaks

public enum ToolMarkupScrubber {
    private static let logger = Logger(subsystem: "com.sunweizhou.Vela4", category: "ToolMarkupScrubber")

    private static let regexPatterns: [String] = [
        "<tool_call>[\\s\\S]*?</tool_call>",
        "<tool_call>[\\s\\S]*$",
        "<[｜|]DSML[｜|]function_calls>[\\s\\S]*?</[｜|]DSML[｜|]function_calls>",
        "<[｜|]DSML[｜|]invoke\\b[\\s\\S]*?</[｜|]DSML[｜|]invoke>",
        "<[｜|]DSML[｜|][^>]*>[\\s\\S]*?</[｜|]DSML[｜|][^>]*>",
        "</?[｜|]DSML[｜|][^>]*>",
        "<[｜|]DSML[｜|][\\s\\S]*$",
        "<function_calls>[\\s\\S]*?</function_calls>",
        "<invoke\\b[\\s\\S]*?</invoke>",
        "<think>[\\s\\S]*?</think>",
    ]

    public static func scrub(_ raw: String) -> (cleaned: String, leakedMarkupDetected: Bool) {
        var working = raw
        var leaked = false

        for pattern in regexPatterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [])
                let nsRange = NSRange(working.startIndex..., in: working)
                if regex.firstMatch(in: working, options: [], range: nsRange) != nil {
                    leaked = true
                    working = regex.stringByReplacingMatches(in: working, options: [], range: nsRange, withTemplate: "")
                }
            } catch {
                logger.error("Invalid scrub regex \(pattern, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        if leaked {
            logger.warning("Scrubbed leaked tool-call XML/DSML markup from assistant response.")
        }
        return (working.trimmingCharacters(in: .whitespacesAndNewlines), leaked)
    }

    /// Normalizes markdown code-fenced JSON arguments occasionally emitted by DeepSeek / OpenAI-compatible endpoints.
    public static func cleanJSONArguments(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            let stripped = lines.dropFirst().reversed().drop(while: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "```" }).reversed()
            trimmed = stripped.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed.isEmpty ? "{}" : trimmed
    }
}

// MARK: - Pure Codable OpenAI-Compatible Wire Models

public enum JSONValue: Equatable, Hashable, Sendable, Codable {
    case string(String)
    case number(Double)
    case integer(Int)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    private static func decodeOptional<T: Decodable>(
        _ type: T.Type,
        from container: SingleValueDecodingContainer
    ) -> T? {
        do {
            return try container.decode(type)
        } catch {
            return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = Self.decodeOptional(Bool.self, from: container) {
            self = .bool(b)
        } else if let i = Self.decodeOptional(Int.self, from: container) {
            self = .integer(i)
        } else if let d = Self.decodeOptional(Double.self, from: container) {
            self = .number(d)
        } else if let s = Self.decodeOptional(String.self, from: container) {
            self = .string(s)
        } else if let arr = Self.decodeOptional([JSONValue].self, from: container) {
            self = .array(arr)
        } else if let obj = Self.decodeOptional([String: JSONValue].self, from: container) {
            self = .object(obj)
        } else {
            throw DecodingError.typeMismatch(JSONValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSONValue"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(s): try container.encode(s)
        case let .number(d): try container.encode(d)
        case let .integer(i): try container.encode(i)
        case let .bool(b): try container.encode(b)
        case let .object(obj): try container.encode(obj)
        case let .array(arr): try container.encode(arr)
        case .null: try container.encodeNil()
        }
    }
}

// Re-encode JSONValue decoder without optional-try to uphold strict zero-swallowed-error policy.
public enum StrictJSONDecoderError: Error, LocalizedError {
    case unsupportedValue

    public var errorDescription: String? { "Unsupported JSON value" }
}

public extension JSONValue {
    static func parseData(_ data: Data) throws -> JSONValue {
        let rawObject = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try fromAny(rawObject)
    }

    static func fromAny(_ any: Any) throws -> JSONValue {
        if any is NSNull {
            return .null
        }
        if let num = any as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return .bool(num.boolValue)
            }
            let doubleVal = num.doubleValue
            if doubleVal.rounded() == doubleVal, let exactInt = Int(exactly: num) {
                return .integer(exactInt)
            }
            return .number(doubleVal)
        }
        if let str = any as? String {
            return .string(str)
        }
        if let arr = any as? [Any] {
            return .array(try arr.map(fromAny))
        }
        if let dict = any as? [String: Any] {
            var out: [String: JSONValue] = [:]
            for (k, v) in dict {
                out[k] = try fromAny(v)
            }
            return .object(out)
        }
        throw StrictJSONDecoderError.unsupportedValue
    }
}

public struct OpenAIToolFunctionCall: Equatable, Hashable, Sendable, Codable {
    public var name: String
    public var arguments: String

    public init(name: String, arguments: String) {
        self.name = name
        self.arguments = arguments
    }
}

public struct OpenAIToolCall: Equatable, Hashable, Sendable, Codable {
    public var id: String
    public var type: String
    public var function: OpenAIToolFunctionCall

    public init(id: String, type: String = "function", function: OpenAIToolFunctionCall) {
        self.id = id
        self.type = type
        self.function = function
    }
}

public struct OpenAIChatMessage: Equatable, Hashable, Sendable, Codable {
    public let role: String
    public let content: String?
    public let toolCalls: [OpenAIToolCall]?
    public let toolCallID: String?
    public let name: String?
    let imageDataURL: String?

    private enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
        case name
    }

    private struct ContentPart: Codable {
        struct ImageURL: Codable { let url: String }
        let type: String
        let text: String?
        let image_url: ImageURL?
    }

    public init(
        role: String,
        content: String?,
        toolCalls: [OpenAIToolCall]? = nil,
        toolCallID: String? = nil,
        name: String? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.name = name
        self.imageDataURL = nil
    }

    init(mealText: String, jpeg: Data) {
        role = "user"
        content = mealText
        toolCalls = nil
        toolCallID = nil
        name = nil
        imageDataURL = "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
        toolCalls = try container.decodeIfPresent([OpenAIToolCall].self, forKey: .toolCalls)
        toolCallID = try container.decodeIfPresent(String.self, forKey: .toolCallID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        do {
            content = try container.decodeIfPresent(String.self, forKey: .content)
            imageDataURL = nil
        } catch DecodingError.typeMismatch {
            let parts = try container.decode([ContentPart].self, forKey: .content)
            content = parts.first { $0.type == "text" }?.text
            imageDataURL = parts.first { $0.type == "image_url" }?.image_url?.url
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try container.encodeIfPresent(toolCallID, forKey: .toolCallID)
        try container.encodeIfPresent(name, forKey: .name)
        if let imageDataURL {
            try container.encode([
                ContentPart(type: "text", text: content ?? "", image_url: nil),
                ContentPart(type: "image_url", text: nil, image_url: .init(url: imageDataURL)),
            ], forKey: .content)
        } else {
            try container.encodeIfPresent(content, forKey: .content)
        }
    }
}

public struct OpenAIToolParameterSchema: Equatable, Hashable, Sendable, Codable {
    public let type: String
    public let description: String?
    public let enumValues: [String]?

    private enum CodingKeys: String, CodingKey {
        case type
        case description
        case enumValues = "enum"
    }

    public init(type: String, description: String? = nil, enumValues: [String]? = nil) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
    }
}

public struct OpenAIToolParametersObject: Equatable, Hashable, Sendable, Codable {
    public let type: String
    public let properties: [String: OpenAIToolParameterSchema]
    public let required: [String]

    public init(
        type: String = "object",
        properties: [String: OpenAIToolParameterSchema] = [:],
        required: [String] = []
    ) {
        self.type = type
        self.properties = properties
        self.required = required
    }
}

public struct OpenAIFunctionDefinition: Equatable, Hashable, Sendable, Codable {
    public let name: String
    public let description: String
    public let parameters: OpenAIToolParametersObject

    public init(name: String, description: String, parameters: OpenAIToolParametersObject) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public struct OpenAIToolDefinition: Equatable, Hashable, Sendable, Codable {
    public let type: String
    public let function: OpenAIFunctionDefinition

    public init(type: String = "function", function: OpenAIFunctionDefinition) {
        self.type = type
        self.function = function
    }
}

public struct OpenAIChatRequest: Equatable, Sendable, Codable {
    public let model: String
    public let messages: [OpenAIChatMessage]
    public let tools: [OpenAIToolDefinition]?
    public let toolChoice: String?
    public let temperature: Double?
    public let maxTokens: Int?
    public let stream: Bool

    private enum CodingKeys: String, CodingKey {
        case model
        case messages
        case tools
        case toolChoice = "tool_choice"
        case temperature
        case maxTokens = "max_tokens"
        case stream
    }

    public init(
        model: String,
        messages: [OpenAIChatMessage],
        tools: [OpenAIToolDefinition]? = nil,
        toolChoice: String? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        stream: Bool = false
    ) {
        self.model = model
        self.messages = messages
        self.tools = tools
        self.toolChoice = toolChoice
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.stream = stream
    }
}

public struct OpenAIChatCompletionResponse: Equatable, Sendable, Codable {
    public struct Choice: Equatable, Sendable, Codable {
        public struct ResponseMessage: Equatable, Sendable, Codable {
            public let role: String?
            public let content: String?
            public let reasoningContent: String?
            public let toolCalls: [OpenAIToolCall]?

            private enum CodingKeys: String, CodingKey {
                case role
                case content
                case reasoningContent = "reasoning_content"
                case toolCalls = "tool_calls"
            }
        }

        public let index: Int?
        public let message: ResponseMessage
        public let finishReason: String?

        private enum CodingKeys: String, CodingKey {
            case index
            case message
            case finishReason = "finish_reason"
        }
    }

    public let id: String?
    public let choices: [Choice]
}

public struct OpenAIStreamChunk: Equatable, Sendable, Codable {
    public struct StreamChoice: Equatable, Sendable, Codable {
        public struct Delta: Equatable, Sendable, Codable {
            public struct ToolCallDelta: Equatable, Sendable, Codable {
                public struct FunctionDelta: Equatable, Sendable, Codable {
                    public let name: String?
                    public let arguments: String?
                }

                public let index: Int?
                public let id: String?
                public let type: String?
                public let function: FunctionDelta?
            }

            public let role: String?
            public let content: String?
            public let reasoningContent: String?
            public let toolCalls: [ToolCallDelta]?

            private enum CodingKeys: String, CodingKey {
                case role
                case content
                case reasoningContent = "reasoning_content"
                case toolCalls = "tool_calls"
            }
        }

        public let index: Int?
        public let delta: Delta
        public let finishReason: String?

        private enum CodingKeys: String, CodingKey {
            case index
            case delta
            case finishReason = "finish_reason"
        }
    }

    public let id: String?
    public let choices: [StreamChoice]
}

// MARK: - Transport Abstraction & Error Types

public enum OpenAICompatibleClientError: LocalizedError, Equatable, Sendable {
    case invalidEndpoint(String)
    case missingAPIKey
    case invalidHTTPResponse
    case httpStatus(Int, String)
    case transportFailure(String)
    case decodingFailure(String)
    case maxToolRoundsExceeded(Int)

    public var errorDescription: String? {
        switch self {
        case let .invalidEndpoint(raw): "Endpoint 无效：\(raw)"
        case .missingAPIKey: "未提供 API Key"
        case .invalidHTTPResponse: "未收到有效 HTTP 响应"
        case let .httpStatus(code, body): "HTTP \(code)：\(body)"
        case let .transportFailure(msg): "网络请求失败：\(msg)"
        case let .decodingFailure(msg): "模型响应解析失败：\(msg)"
        case let .maxToolRoundsExceeded(rounds): "工具调用轮次超过上限（\(rounds) 轮）"
        }
    }
}

public protocol AgentHTTPTransport: Sendable {
    func performData(_ request: URLRequest) async throws -> (statusCode: Int, data: Data)
    func performStreamLines(_ request: URLRequest) async throws -> (statusCode: Int, lines: [String], errorBody: Data)
}

public struct URLSessionAgentTransport: AgentHTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func performData(_ request: URLRequest) async throws -> (statusCode: Int, data: Data) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAICompatibleClientError.invalidHTTPResponse
        }
        return (http.statusCode, data)
    }

    public func performStreamLines(_ request: URLRequest) async throws -> (statusCode: Int, lines: [String], errorBody: Data) {
        let (asyncBytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAICompatibleClientError.invalidHTTPResponse
        }
        if !(200..<300).contains(http.statusCode) {
            var data = Data()
            for try await byte in asyncBytes {
                data.append(byte)
                if data.count >= 1024 { break }
            }
            return (http.statusCode, [], data)
        }
        var collected: [String] = []
        for try await line in asyncBytes.lines {
            collected.append(line)
        }
        return (http.statusCode, collected, Data())
    }
}

// MARK: - OpenAI-Compatible Client (Streaming + Multi-Turn Tool Calls + Retry + Scrub)

public struct OpenAICompatibleCompletionResult: Equatable, Sendable {
    public let content: String
    public let toolsInvoked: [String]
    public let leakedMarkupDetected: Bool
    public let roundsUsed: Int

    public init(
        content: String,
        toolsInvoked: [String],
        leakedMarkupDetected: Bool,
        roundsUsed: Int
    ) {
        self.content = content
        self.toolsInvoked = toolsInvoked
        self.leakedMarkupDetected = leakedMarkupDetected
        self.roundsUsed = roundsUsed
    }
}

public struct OpenAICompatibleClient: Sendable {
    private static let logger = Logger(subsystem: "com.sunweizhou.Vela4", category: "OpenAICompatibleClient")

    public let transport: any AgentHTTPTransport
    public let payloadRecorder: AgentPayloadRecorder
    public let timeoutSeconds: TimeInterval
    public let maxRetries: Int
    public let retryBaseDelayNanoseconds: UInt64
    public let maxToolRounds: Int

    public init(
        transport: any AgentHTTPTransport = URLSessionAgentTransport(),
        payloadRecorder: AgentPayloadRecorder = .shared,
        timeoutSeconds: TimeInterval = 30,
        maxRetries: Int = 2,
        retryBaseDelayNanoseconds: UInt64 = 250_000_000,
        maxToolRounds: Int = 6
    ) {
        self.transport = transport
        self.payloadRecorder = payloadRecorder
        self.timeoutSeconds = timeoutSeconds
        self.maxRetries = maxRetries
        self.retryBaseDelayNanoseconds = retryBaseDelayNanoseconds
        self.maxToolRounds = maxToolRounds
    }

    public func testConnection(endpointURL: String, apiKey: String, modelName: String) async -> String? {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return "请先填写 API Key" }
        guard let baseURL = EndpointURLNormalizer.normalizeBaseURL(endpointURL) else {
            return "API Endpoint 格式无效：\(endpointURL)"
        }
        let chatURL = baseURL.appendingPathComponent("chat/completions")
        let reqDTO = OpenAIChatRequest(
            model: modelName.trimmingCharacters(in: .whitespacesAndNewlines),
            messages: [OpenAIChatMessage(role: "user", content: "ping")],
            maxTokens: 5,
            stream: false
        )
        do {
            let request = try buildURLRequest(url: chatURL, apiKey: trimmedKey, payload: reqDTO)
            let (status, data) = try await transport.performData(request)
            if (200..<300).contains(status) {
                return nil
            }
            let msg = String(data: data.prefix(240), encoding: .utf8) ?? ""
            return "HTTP \(status)：\(msg)"
        } catch {
            Self.logger.error("Connection test failed: \(error.localizedDescription, privacy: .public)")
            return "网络请求失败：\(error.localizedDescription)"
        }
    }

    func analyzeMeal(endpointURL: String, apiKey: String, modelName: String,
                     input: String, jpeg: Data?) async throws -> [MealDraftCandidate] {
        guard let url = EndpointURLNormalizer.normalizeBaseURL(endpointURL),
              url.scheme?.lowercased() == "https", url.host != nil,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw MealDraftAnalysisError.unconfigured }

        if let jpeg, jpeg.isEmpty || jpeg.count > 2_000_000 { throw MealDraftAnalysisError.imageTooLarge }
        let text = input.isEmpty ? "请识别我选中的这一餐。" : input
        let user = jpeg.map { OpenAIChatMessage(mealText: text, jpeg: $0) }
            ?? OpenAIChatMessage(role: "user", content: text)
        let chatURL = url.appendingPathComponent("chat/completions")
        // Keep the disclosure record useful without storing the meal text or image bytes.
        await payloadRecorder.record(.init(
            sentAt: Date(), endpointURL: chatURL.absoluteString, modelName: modelName, messageCount: 2,
            toolNames: [], redactedRequestJSON: jpeg == nil ? #"{"mealInput":"[文字已省略]"}"# : #"{"mealInput":"[图片和文字已省略]"}"#
        ))
        do {
            for attempt in 0...1 {
                let instructions = attempt == 0 ? MealDraftAnalysis.instructions
                    : MealDraftAnalysis.instructions + "\n上次回复无法读取。仅输出紧凑的 JSON 对象，根字段为 items。食物名优先，无法填的字段用 null。先完整闭合 JSON。"
                let payload = OpenAIChatRequest(
                    model: modelName, messages: [.init(role: "system", content: instructions), user],
                    maxTokens: attempt == 0 ? 2_800 : 6_144, stream: false
                )
                let request = try buildURLRequest(url: chatURL, apiKey: apiKey, payload: payload)
                do {
                    let result = try await executeDataWithRetry(request: request)
                    try Task.checkCancellation()
                    return try MealDraftAnalysis.decode(result.text)
                } catch MealDraftAnalysisError.invalidReply where attempt == 0 {
                    try Task.checkCancellation()
                } catch OpenAICompatibleClientError.decodingFailure(_) where attempt == 0 {
                    try Task.checkCancellation()
                }
            }
            throw MealDraftAnalysisError.invalidReply
        } catch let error as MealDraftAnalysisError {
            throw error
        } catch let error as OpenAICompatibleClientError {
            try Task.checkCancellation()
            switch error {
            case .httpStatus(401, _), .httpStatus(403, _):
                throw MealDraftAnalysisError.unconfigured
            case .httpStatus(400, _) where jpeg != nil, .httpStatus(422, _) where jpeg != nil:
                throw MealDraftAnalysisError.incompatibleModel
            case .decodingFailure:
                throw MealDraftAnalysisError.invalidReply
            default:
                throw MealDraftAnalysisError.serviceUnavailable
            }
        } catch {
            try Task.checkCancellation()
            throw MealDraftAnalysisError.invalidReply
        }
    }

    public func runChatCompletionLoop(
        endpointURL: String,
        apiKey: String,
        modelName: String,
        messages initialMessages: [OpenAIChatMessage],
        tools: [OpenAIToolDefinition],
        temperature: Double = 0.35,
        preferStreaming: Bool = true,
        toolExecutor: @escaping @Sendable (_ name: String, _ argumentsJSON: String) async -> String
    ) async throws -> OpenAICompatibleCompletionResult {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw OpenAICompatibleClientError.missingAPIKey
        }
        guard let baseURL = EndpointURLNormalizer.normalizeBaseURL(endpointURL) else {
            throw OpenAICompatibleClientError.invalidEndpoint(endpointURL)
        }
        let chatURL = baseURL.appendingPathComponent("chat/completions")

        var conversation = initialMessages
        var invokedTools: [String] = []
        var anyLeakedMarkup = false
        var rounds = 0

        for round in 1...max(1, maxToolRounds) {
            rounds = round
            let payload = OpenAIChatRequest(
                model: modelName.trimmingCharacters(in: .whitespacesAndNewlines),
                messages: conversation,
                tools: tools.isEmpty ? nil : tools,
                toolChoice: tools.isEmpty ? nil : "auto",
                temperature: temperature,
                stream: preferStreaming
            )
            let request = try buildURLRequest(url: chatURL, apiKey: trimmedKey, payload: payload)
            await recordSanitizedPayload(request: request, url: chatURL, modelName: payload.model, messageCount: conversation.count, tools: tools)

            let parsedTurn: (text: String, toolCalls: [OpenAIToolCall])
            if preferStreaming {
                parsedTurn = try await executeStreamWithRetry(request: request)
            } else {
                parsedTurn = try await executeDataWithRetry(request: request)
            }

            let cleanToolCalls = parsedTurn.toolCalls.filter { !$0.function.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if !cleanToolCalls.isEmpty {
                conversation.append(
                    OpenAIChatMessage(
                        role: "assistant",
                        content: parsedTurn.text.isEmpty ? nil : parsedTurn.text,
                        toolCalls: cleanToolCalls
                    )
                )
                for call in cleanToolCalls {
                    let cleanArgs = ToolMarkupScrubber.cleanJSONArguments(call.function.arguments)
                    let result = await toolExecutor(call.function.name, cleanArgs)
                    invokedTools.append(call.function.name)
                    conversation.append(
                        OpenAIChatMessage(
                            role: "tool",
                            content: result,
                            toolCallID: call.id,
                            name: call.function.name
                        )
                    )
                }
                continue
            }

            let scrubbed = ToolMarkupScrubber.scrub(parsedTurn.text)
            if scrubbed.leakedMarkupDetected {
                anyLeakedMarkup = true
            }
            return OpenAICompatibleCompletionResult(
                content: scrubbed.cleaned,
                toolsInvoked: invokedTools,
                leakedMarkupDetected: anyLeakedMarkup,
                roundsUsed: rounds
            )
        }

        throw OpenAICompatibleClientError.maxToolRoundsExceeded(maxToolRounds)
    }

    private func buildURLRequest(url: URL, apiKey: String, payload: OpenAIChatRequest) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(payload)
        return request
    }

    private func recordSanitizedPayload(
        request: URLRequest,
        url: URL,
        modelName: String,
        messageCount: Int,
        tools: [OpenAIToolDefinition]
    ) async {
        let redactedJSON: String
        if let body = request.httpBody, let utf8 = String(data: body, encoding: .utf8) {
            redactedJSON = utf8
        } else {
            redactedJSON = "{}"
        }
        await payloadRecorder.record(
            AgentOutboundPayloadSnapshot(
                sentAt: Date(),
                endpointURL: url.absoluteString,
                modelName: modelName,
                messageCount: messageCount,
                toolNames: tools.map(\.function.name),
                redactedRequestJSON: redactedJSON
            )
        )
    }

    private func executeDataWithRetry(request: URLRequest) async throws -> (text: String, toolCalls: [OpenAIToolCall]) {
        var attempt = 0
        while true {
            do {
                let (status, data) = try await transport.performData(request)
                if (200..<300).contains(status) {
                    return try parseCompletionResponse(data)
                }
                let errBody = String(data: data.prefix(240), encoding: .utf8) ?? ""
                let httpErr = OpenAICompatibleClientError.httpStatus(status, errBody)
                if isTransientHTTPStatus(status), attempt < maxRetries {
                    attempt += 1
                    Self.logger.warning("Transient HTTP \(status, privacy: .public), retrying attempt \(attempt, privacy: .public)")
                    try await sleepBackoff(attempt: attempt)
                    continue
                }
                throw httpErr
            } catch let error as OpenAICompatibleClientError {
                throw error
            } catch {
                if isTransientTransportError(error), attempt < maxRetries {
                    attempt += 1
                    Self.logger.warning("Transient transport failure (\(error.localizedDescription, privacy: .public)), retrying attempt \(attempt, privacy: .public)")
                    try await sleepBackoff(attempt: attempt)
                    continue
                }
                throw OpenAICompatibleClientError.transportFailure(error.localizedDescription)
            }
        }
    }

    private func executeStreamWithRetry(request: URLRequest) async throws -> (text: String, toolCalls: [OpenAIToolCall]) {
        var attempt = 0
        while true {
            do {
                let (status, lines, errorBody) = try await transport.performStreamLines(request)
                if (200..<300).contains(status) {
                    return try parseSSELines(lines)
                }
                let errMsg = String(data: errorBody.prefix(240), encoding: .utf8) ?? ""
                let httpErr = OpenAICompatibleClientError.httpStatus(status, errMsg)
                if isTransientHTTPStatus(status), attempt < maxRetries {
                    attempt += 1
                    Self.logger.warning("Transient SSE HTTP \(status, privacy: .public), retrying attempt \(attempt, privacy: .public)")
                    try await sleepBackoff(attempt: attempt)
                    continue
                }
                throw httpErr
            } catch let error as OpenAICompatibleClientError {
                throw error
            } catch {
                if isTransientTransportError(error), attempt < maxRetries {
                    attempt += 1
                    Self.logger.warning("Transient SSE transport failure (\(error.localizedDescription, privacy: .public)), retrying attempt \(attempt, privacy: .public)")
                    try await sleepBackoff(attempt: attempt)
                    continue
                }
                throw OpenAICompatibleClientError.transportFailure(error.localizedDescription)
            }
        }
    }

    private func parseCompletionResponse(_ data: Data) throws -> (text: String, toolCalls: [OpenAIToolCall]) {
        let decoder = JSONDecoder()
        do {
            let resp = try decoder.decode(OpenAIChatCompletionResponse.self, from: data)
            guard let choice = resp.choices.first else {
                throw OpenAICompatibleClientError.decodingFailure("choices 为空")
            }
            return (
                choice.message.content ?? "",
                choice.message.toolCalls ?? []
            )
        } catch let err as OpenAICompatibleClientError {
            throw err
        } catch {
            throw OpenAICompatibleClientError.decodingFailure(error.localizedDescription)
        }
    }

    private func parseSSELines(_ lines: [String]) throws -> (text: String, toolCalls: [OpenAIToolCall]) {
        // Fallback if server ignored stream=true and returned a single JSON object
        let joinedTrimmed = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if joinedTrimmed.hasPrefix("{"), let rawData = joinedTrimmed.data(using: .utf8) {
            return try parseCompletionResponse(rawData)
        }

        let decoder = JSONDecoder()
        var contentBuffer = ""
        var callsByIndex: [Int: OpenAIToolCall] = [:]

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("data:") else { continue }
            let payloadText = String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !payloadText.isEmpty, payloadText != "[DONE]" else { continue }
            guard let chunkData = payloadText.data(using: .utf8) else { continue }
            let chunk: OpenAIStreamChunk
            do {
                chunk = try decoder.decode(OpenAIStreamChunk.self, from: chunkData)
            } catch {
                throw OpenAICompatibleClientError.decodingFailure("SSE chunk 解码失败：\(error.localizedDescription)")
            }
            guard let delta = chunk.choices.first?.delta else { continue }
            if let textPart = delta.content {
                contentBuffer.append(textPart)
            }
            if let deltas = delta.toolCalls {
                for tcDelta in deltas {
                    let idx = tcDelta.index ?? 0
                    var current = callsByIndex[idx] ?? OpenAIToolCall(
                        id: tcDelta.id ?? "call_\(idx)",
                        type: tcDelta.type ?? "function",
                        function: OpenAIToolFunctionCall(name: "", arguments: "")
                    )
                    if let id = tcDelta.id, !id.isEmpty {
                        current.id = id
                    }
                    if let namePart = tcDelta.function?.name {
                        current.function.name.append(namePart)
                    }
                    if let argsPart = tcDelta.function?.arguments {
                        current.function.arguments.append(argsPart)
                    }
                    callsByIndex[idx] = current
                }
            }
        }

        let orderedCalls = callsByIndex.keys.sorted().compactMap { callsByIndex[$0] }
        return (contentBuffer, orderedCalls)
    }

    private func isTransientHTTPStatus(_ code: Int) -> Bool {
        code == 429 || (500...599).contains(code)
    }

    private func isTransientTransportError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return [
                NSURLErrorTimedOut,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorDNSLookupFailed,
                NSURLErrorNotConnectedToInternet,
            ].contains(nsError.code)
        }
        return false
    }

    private func sleepBackoff(attempt: Int) async throws {
        guard retryBaseDelayNanoseconds > 0 else { return }
        let multiplier = UInt64(1 << max(0, attempt - 1))
        try await Task.sleep(nanoseconds: retryBaseDelayNanoseconds * multiplier)
    }
}
