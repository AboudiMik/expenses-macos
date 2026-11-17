import Foundation

nonisolated struct ClaudeMessage: Codable {
    var role: String
    var content: [ContentBlock]

    static func user(_ blocks: [ContentBlock]) -> ClaudeMessage { .init(role: "user", content: blocks) }
    static func user(text: String) -> ClaudeMessage { .user([.text(text)]) }
}

nonisolated struct ClaudeTool: Encodable {
    var name: String
    var description: String
    var inputSchema: JSONValue
    var strict: Bool = true

    private enum Keys: String, CodingKey { case name, description, inputSchema = "input_schema", strict }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(name, forKey: .name)
        try c.encode(description, forKey: .description)
        try c.encode(inputSchema, forKey: .inputSchema)
        try c.encode(strict, forKey: .strict)
    }
}

/// Note: `any` and `tool` are rejected (HTTP 400) by Claude Sonnet 5.5 and Opus 5.5.
/// Use `.auto` plus an instruction in the prompt on those models.
nonisolated enum ToolChoice: Encodable {
    case auto(disableParallel: Bool = false)
    case any
    case tool(name: String)
    case none

    private enum Keys: String, CodingKey { case type, name, disableParallel = "disable_parallel_tool_use" }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .auto(let disableParallel):
            try c.encode("auto", forKey: .type)
            if disableParallel { try c.encode(true, forKey: .disableParallel) }
        case .any: try c.encode("any", forKey: .type)
        case .tool(let name):
            try c.encode("tool", forKey: .type)
            try c.encode(name, forKey: .name)
        case .none: try c.encode("none", forKey: .type)
        }
    }
}

nonisolated enum ClaudeError: LocalizedError {
    case missingAPIKey
    case invalidAPIKey
    case rateLimited(retryAfterSeconds: Int?)
    case overloaded
    case http(status: Int, message: String)
    case refused(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "No Claude API key. Add one in Settings (⌘,)."
        case .invalidAPIKey: return "The Claude API key was rejected. Check it in Settings."
        case .rateLimited(let secs):
            return "Rate limited by the Claude API." + (secs.map { " Retry in \($0) s." } ?? " Retry shortly.")
        case .overloaded: return "The Claude API is overloaded. Try again in a moment."
        case .http(let status, let message): return "Claude API error \(status): \(message)"
        case .refused(let why): return "Claude declined the request: \(why)"
        case .invalidResponse: return "The Claude API returned an unexpected response."
        }
    }
}

nonisolated struct ClaudeResponse {
    var content: [ContentBlock]
    var inputTokens: Int
    var outputTokens: Int
    var seconds: Double
}

struct ClaudeClient {
    var session: URLSession = .shared

    private struct Request: Encodable {
        var model: String, maxTokens: Int, system: String?
        var messages: [ClaudeMessage], tools: [ClaudeTool]?, toolChoice: ToolChoice?
        enum CodingKeys: String, CodingKey {
            case model, system, messages, tools
            case maxTokens = "max_tokens", toolChoice = "tool_choice"
        }
    }
    private struct Response: Decodable {
        struct StopDetails: Decodable { var explanation: String? }
        struct Usage: Decodable {
            var inputTokens: Int?, outputTokens: Int?
            enum CodingKeys: String, CodingKey { case inputTokens = "input_tokens", outputTokens = "output_tokens" }
        }
        var content: [ContentBlock]
        var stopReason: String?
        var stopDetails: StopDetails?
        var usage: Usage?
        enum CodingKeys: String, CodingKey {
            case content, usage, stopReason = "stop_reason", stopDetails = "stop_details"
        }
    }
    private struct ErrorBody: Decodable {
        struct Inner: Decodable { var type: String; var message: String }
        var error: Inner
    }

    /// Sends one Messages API request and returns the decoded content blocks with usage and timing.
    func send(messages: [ClaudeMessage], system: String? = nil, tools: [ClaudeTool]? = nil,
              toolChoice: ToolChoice? = nil, maxTokens: Int = Config.maxTokens,
              model: String = Config.agentModel) async throws -> ClaudeResponse {
        let started = Date()
        guard let apiKey = KeychainStore.loadAPIKey(), !apiKey.isEmpty else { throw ClaudeError.missingAPIKey }

        var request = URLRequest(url: Config.apiURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Config.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 180
        request.httpBody = try JSONEncoder().encode(Request(
            model: model, maxTokens: maxTokens, system: system,
            messages: messages, tools: tools, toolChoice: toolChoice))

        let (data, urlResponse) = try await session.data(for: request)
        guard let http = urlResponse as? HTTPURLResponse else { throw ClaudeError.invalidResponse }

        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error.message
                ?? String(decoding: data, as: UTF8.self)
            switch http.statusCode {
            case 401: throw ClaudeError.invalidAPIKey
            case 429:
                let retry = http.value(forHTTPHeaderField: "retry-after").flatMap { Int($0) }
                throw ClaudeError.rateLimited(retryAfterSeconds: retry)
            case 529: throw ClaudeError.overloaded
            default: throw ClaudeError.http(status: http.statusCode, message: message)
            }
        }

        let response = try JSONDecoder().decode(Response.self, from: data)
        #if DEBUG
        print("[claude] stop_reason=\(response.stopReason ?? "nil") blocks=\(response.content.count)")
        #endif
        if response.stopReason == "refusal" {
            throw ClaudeError.refused(response.stopDetails?.explanation ?? "no reason given")
        }
        let input = response.usage?.inputTokens ?? 0, output = response.usage?.outputTokens ?? 0
        UsageTracker.shared.record(input: input, output: output)
        return ClaudeResponse(content: response.content, inputTokens: input, outputTokens: output,
                              seconds: Date().timeIntervalSince(started))
    }
}
