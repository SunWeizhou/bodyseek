import Foundation

enum PrivateAIURLSession {
    static let shared: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration)
    }()
}

struct LLMRequest: Hashable, Sendable {
    var systemPrompt: String
    var userPrompt: String
    var contextJSON: String
    var tools: [[String: Value]]? = nil
}

struct LLMResponse: Hashable, Sendable {
    var content: String
    var toolCalls: [ToolCall]? = nil
    var reasoningContent: String? = nil
}

struct ToolCall: Hashable, Sendable, Codable {
    var id: String
    var name: String
    var arguments: String
}

struct ChatMessage: Hashable, Sendable {
    var role: Role
    var content: String
    var toolCalls: [ToolCall]? = nil
    var toolCallId: String? = nil
    var reasoningContent: String? = nil

    enum Role: String, Hashable, Sendable {
        case system
        case user
        case assistant
        case tool
    }
}

// JSON-compatible value type for tool parameter schemas
enum Value: Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([Value])
    case object([String: Value])
    case null
}

extension Value: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode(Double.self) { self = .number(v) }
        else if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode([Value].self) { self = .array(v) }
        else if let v = try? container.decode([String: Value].self) { self = .object(v) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}

protocol LLMProvider: Sendable {
    func complete(request: LLMRequest) async throws -> LLMResponse
}

extension LLMProvider {
    func completeChat(messages: [ChatMessage], tools: [[String: Value]]? = nil) async throws -> LLMResponse {
        let systemPrompt = messages.first { $0.role == .system }?.content ?? ""
        let userMessages = messages.filter { $0.role != .system }
        let contextParts = Array(messages.filter { $0.role == .system }.dropFirst().map { $0.content })
        let contextJSON = contextParts.isEmpty ? "{}" : contextParts.joined(separator: "\n\n")
        return try await complete(
            request: LLMRequest(
                systemPrompt: systemPrompt,
                userPrompt: userMessages.map { msg in
                    if let tcs = msg.toolCalls, !tcs.isEmpty {
                        return "[\(msg.role.rawValue) tool_calls: \(tcs.map { "\($0.name)(\($0.arguments))" }.joined(separator: ", "))]"
                    }
                    if msg.role == .tool {
                        return "[tool_result id=\(msg.toolCallId ?? ""): \(msg.content)]"
                    }
                    return msg.content
                }.joined(separator: "\n\n"),
                contextJSON: contextJSON,
                tools: tools
            )
        )
    }

    func streamChat(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await completeChat(messages: messages)
                    continuation.yield(response.content)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

enum LLMProviderError: LocalizedError, Hashable, Sendable {
    case missingAPIKey
    case authenticationFailed
    case networkUnavailable
    case timedOut
    case invalidResponse
    case responseTruncated
    case requestFailed(statusCode: Int, message: String)

    static func classify(_ error: Error) -> LLMProviderError {
        if let providerError = error as? LLMProviderError {
            return providerError
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
                return .networkUnavailable
            case .timedOut:
                return .timedOut
            default:
                return .requestFailed(statusCode: 0, message: urlError.localizedDescription)
            }
        }
        return .requestFailed(statusCode: 0, message: error.localizedDescription)
    }

    static func httpFailure(statusCode: Int, body: String) -> LLMProviderError {
        if statusCode == 401 || statusCode == 403 {
            return .authenticationFailed
        }
        return .requestFailed(statusCode: statusCode, message: "DeepSeek request failed with status \(statusCode): \(body.prefix(200))")
    }

    var isRetryable: Bool {
        switch self {
        case .networkUnavailable, .timedOut:
            return true
        case .requestFailed(let statusCode, _):
            // 按状态码判定（此前靠错误消息子串匹配，文案变化即失效）。
            return [408, 429, 500, 502, 503, 504].contains(statusCode)
        case .missingAPIKey, .authenticationFailed, .invalidResponse, .responseTruncated:
            return false
        }
    }

    func recoveryAction(isChinese: Bool) -> LLMErrorRecoveryAction {
        switch self {
        case .missingAPIKey, .authenticationFailed:
            return LLMErrorRecoveryAction(
                title: isChinese ? "打开设置" : "Open Settings",
                systemImage: "key.fill",
                destination: .settings
            )
        case .networkUnavailable, .timedOut, .requestFailed:
            return LLMErrorRecoveryAction(
                title: isChinese ? "重试 Coach" : "Retry Coach",
                systemImage: "arrow.clockwise",
                destination: .retry
            )
        case .invalidResponse, .responseTruncated:
            return LLMErrorRecoveryAction(
                title: isChinese ? "稍后重试" : "Retry Later",
                systemImage: "exclamationmark.triangle.fill",
                destination: .retry
            )
        }
    }

    func userFacingMessage(isChinese: Bool) -> String {
        switch self {
        case .missingAPIKey:
            return isChinese ? "请先在设置中添加 DeepSeek API Key。" : "Add your DeepSeek API key in Settings."
        case .authenticationFailed:
            return isChinese ? "DeepSeek API Key 无效，请前往设置更新后重试。" : "Your DeepSeek API key is invalid. Update it in Settings and retry."
        case .networkUnavailable:
            return isChinese ? "当前网络不可用。本地健康、训练和日志功能仍可使用，联网后可重试 Coach。" : "The network is unavailable. Local health, training, and journal features still work; retry Coach when online."
        case .timedOut:
            return isChinese ? "Coach 请求超时，未写入空回复。请检查网络后重试。" : "The Coach request timed out and no empty reply was saved. Check the network and retry."
        case .invalidResponse:
            return isChinese ? "AI 服务返回了无法解析的内容，请稍后重试。" : "The AI provider returned an unreadable response. Please retry."
        case .responseTruncated:
            return isChinese ? "回复因长度上限被截断，以上内容不完整。" : "The reply was cut off at the length limit and is incomplete."
        case .requestFailed(let statusCode, _):
            // 深度专项批次 2：按状态码区分真实原因，不再一律「服务暂时不可用」。
            if statusCode == 400 {
                return isChinese
                    ? "请求内容过长或格式有误（400）。换个说法，或稍后重试。"
                    : "The request was too long or malformed (400). Rephrase and retry."
            }
            if statusCode == 429 {
                return isChinese
                    ? "AI 服务当前繁忙（429），请稍后重试。"
                    : "The AI service is busy right now (429). Retry in a moment."
            }
            if statusCode >= 500 {
                return isChinese
                    ? "AI 服务端出现故障（\(statusCode)），本地功能不受影响，请稍后重试。"
                    : "The AI provider hit a server error (\(statusCode)). Local features are unaffected; retry later."
            }
            return isChinese
                ? "AI 服务暂时不可用（\(statusCode)），本地功能不受影响。请稍后重试。"
                : "The AI provider is temporarily unavailable (\(statusCode)). Local features are unaffected; please retry."
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "DeepSeek API key is missing."
        case .authenticationFailed:
            return "DeepSeek API authentication failed."
        case .networkUnavailable:
            return "The network is unavailable."
        case .timedOut:
            return "The provider request timed out."
        case .invalidResponse:
            return "The provider returned an invalid response."
        case .responseTruncated:
            return "The provider stopped the reply because it reached the length limit."
        case .requestFailed(_, let message):
            return message
        }
    }
}

struct LLMErrorRecoveryAction: Hashable, Sendable, Codable {
    enum Destination: String, Hashable, Sendable, Codable {
        case settings
        case retry
    }

    var title: String
    var systemImage: String
    var destination: Destination
}

/// LLMProvider 层的指数退避重试（供 ReportGenerator 与后台 Agent 使用；
/// Coach 对话路径使用 RetryingAgentChatProvider，策略保持一致）。
/// 此前 MorningBrief/EveningWiki 直连 provider，瞬时网络错误整次运行静默失败。
struct RetryingLLMProvider: LLMProvider {
    let base: any LLMProvider
    let maxAttempts: Int
    let initialDelayNanoseconds: UInt64

    init(
        base: any LLMProvider,
        maxAttempts: Int = 3,
        initialDelayNanoseconds: UInt64 = 350_000_000
    ) {
        self.base = base
        self.maxAttempts = max(1, maxAttempts)
        self.initialDelayNanoseconds = initialDelayNanoseconds
    }

    func complete(request: LLMRequest) async throws -> LLMResponse {
        var attempt = 1
        while true {
            do {
                return try await base.complete(request: request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let providerError = LLMProviderError.classify(error)
                guard attempt < maxAttempts, providerError.isRetryable else {
                    throw providerError
                }
                let shift = min(max(attempt - 1, 0), 4)
                let multiplier = UInt64(1) << UInt64(shift)
                let (product, overflow) = initialDelayNanoseconds.multipliedReportingOverflow(by: multiplier)
                var delay = overflow ? UInt64.max : product
                if delay > 0 && delay < UInt64.max {
                    let jitter = UInt64.random(in: 0...max(1, delay / 5))
                    delay = delay - delay / 10 + jitter
                }
                if delay > 0 {
                    try await Task.sleep(nanoseconds: delay)
                }
                attempt += 1
            }
        }
    }
}

/// 深度专项批次 2：非对话 LLM 调用（晨报/晚间同步/训练规划）的总 deadline 竞速——
/// BGTask 预算 ~30s，此前无 deadline 的最坏挂起可击穿预算并静默丢失结果。
enum LLMProviderDeadline {
    static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw LLMProviderError.timedOut
            }
            guard let result = try await group.next() else {
                throw LLMProviderError.timedOut
            }
            group.cancelAll()
            return result
        }
    }
}
