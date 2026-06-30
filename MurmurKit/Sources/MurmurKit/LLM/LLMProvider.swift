import Foundation

// MARK: - Identity

/// Every chat/completion backend Murmur can use for "Polish" and Command Mode.
public enum LLMProviderID: String, Codable, CaseIterable, Sendable, Identifiable {
    case lmStudio   // local OpenAI-compatible server (:1234)
    case ollama     // local (:11434, native + /v1 shim)
    case openAI     // cloud
    case groq       // cloud, OpenAI-compatible
    case anthropic  // cloud, Messages API (its own adapter)

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .lmStudio: "LM Studio (local)"
        case .ollama: "Ollama (local)"
        case .openAI: "OpenAI"
        case .groq: "Groq"
        case .anthropic: "Anthropic"
        }
    }

    public var isLocal: Bool { self == .lmStudio || self == .ollama }
    public var requiresAPIKey: Bool { !isLocal }

    /// Keychain account under which this provider's API key is stored.
    public var keychainAccount: String { "llm.\(rawValue)" }

    /// Default endpoint base URL (local providers; overridable in Settings).
    public var defaultBaseURL: String {
        switch self {
        case .lmStudio: "http://localhost:1234/v1"
        case .ollama: "http://localhost:11434/v1"
        case .openAI: "https://api.openai.com/v1"
        case .groq: "https://api.groq.com/openai/v1"
        case .anthropic: "https://api.anthropic.com/v1"
        }
    }
}

// MARK: - Messages + models

public struct LLMModel: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let displayName: String
    public let contextLength: Int?

    public init(id: String, displayName: String? = nil, contextLength: Int? = nil) {
        self.id = id
        self.displayName = displayName ?? id
        self.contextLength = contextLength
    }
}

public struct ChatMessage: Codable, Sendable, Hashable {
    public enum Role: String, Codable, Sendable { case system, user, assistant }
    public var role: Role
    public var content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }

    public static func system(_ content: String) -> ChatMessage { .init(role: .system, content: content) }
    public static func user(_ content: String) -> ChatMessage { .init(role: .user, content: content) }
    public static func assistant(_ content: String) -> ChatMessage { .init(role: .assistant, content: content) }
}

public struct ChatOptions: Sendable {
    public var temperature: Double?
    public var maxTokens: Int?

    public init(temperature: Double? = 0.2, maxTokens: Int? = nil) {
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

// MARK: - Errors

public enum LLMError: LocalizedError {
    case missingAPIKey(LLMProviderID)
    case invalidBaseURL(String)
    case http(status: Int, body: String)
    case network(String)
    case decoding(String)
    case noModelSelected

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let id): "No API key set for \(id.displayName). Add one in Settings."
        case .invalidBaseURL(let s): "Invalid server URL: \(s)"
        case .http(let status, let body): "LLM request failed (HTTP \(status)). \(HTTPBody.summarize(body))"
        case .network(let message): "Network error: \(message)"
        case .decoding(let message): "Couldn't read the LLM response: \(message)"
        case .noModelSelected: "No model selected for the AI cleanup provider."
        }
    }
}

// MARK: - Protocol

/// A chat-completion backend. Most providers speak the OpenAI wire format and
/// share `OpenAICompatibleClient`; Anthropic gets its own adapter.
public protocol LLMProvider: Sendable {
    var id: LLMProviderID { get }
    var isLocal: Bool { get }

    /// Local providers query the running server; cloud providers return a
    /// curated catalog (optionally refreshed live).
    func availableModels() async throws -> [LLMModel]

    /// Stream the assistant's reply as incremental text chunks.
    func streamChat(messages: [ChatMessage], model: LLMModel, options: ChatOptions) -> AsyncThrowingStream<String, Error>
}

public extension LLMProvider {
    var isLocal: Bool { id.isLocal }

    /// Convenience: collect a streamed reply into a single string.
    func chat(messages: [ChatMessage], model: LLMModel, options: ChatOptions = ChatOptions()) async throws -> String {
        var result = ""
        for try await chunk in streamChat(messages: messages, model: model, options: options) {
            result += chunk
        }
        return result
    }
}
