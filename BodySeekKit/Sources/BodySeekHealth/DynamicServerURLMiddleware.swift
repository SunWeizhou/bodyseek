import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Dynamically directs `SpeziLLMOpenAI` requests to the active user-configured
/// OpenAI-compatible server base URL (e.g. DeepSeek, OpenAI, or proxy).
struct DynamicServerURLMiddleware: ClientMiddleware {
    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let rawConfigured = UserDefaults.standard.string(forKey: CoachAIClient.endpointStorageKey)
            ?? "https://api.deepseek.com/v1"
        let normalized = Self.normalizeBaseURL(rawConfigured) ?? baseURL
        return try await next(request, body, normalized)
    }

    static func normalizeBaseURL(_ raw: String) -> URL? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for suffix in ["/v1/chat/completions", "/chat/completions"] {
            if trimmed.hasSuffix(suffix) {
                if suffix == "/v1/chat/completions" {
                    trimmed = String(trimmed.dropLast("/chat/completions".count))
                } else {
                    trimmed = String(trimmed.dropLast(suffix.count))
                }
                break
            }
        }
        return URL(string: trimmed)
    }
}
