import Foundation

/// A provider backed by an OpenAI-compatible endpoint (LM Studio, Ollama,
/// OpenAI, Groq). Local providers list models from the live server; cloud
/// providers prefer a live list and fall back to the curated catalog.
public struct OpenAICompatibleProvider: LLMProvider {
    public let id: LLMProviderID
    private let client: OpenAICompatibleClient
    private let staticModels: [LLMModel]

    public init(id: LLMProviderID, baseURL: String, apiKey: String?) {
        self.id = id
        self.client = OpenAICompatibleClient(baseURL: baseURL, apiKey: apiKey)
        self.staticModels = ModelCatalog.chatModels(for: id)
    }

    public func availableModels() async throws -> [LLMModel] {
        if id.isLocal {
            return try await client.listModels()
        }
        if let live = try? await client.listModels(), !live.isEmpty {
            return live
        }
        return staticModels
    }

    public func streamChat(messages: [ChatMessage], model: LLMModel, options: ChatOptions) -> AsyncThrowingStream<String, Error> {
        client.streamChat(messages: messages, model: model, options: options)
    }
}

/// Anthropic Messages API adapter. Different wire shape (top-level `system`,
/// `x-api-key`/`anthropic-version` headers). Streaming is emulated as a single
/// yield from a non-streaming call — adequate for short Polish responses.
public struct AnthropicProvider: LLMProvider {
    public let id: LLMProviderID = .anthropic
    private let baseURL: String
    private let apiKey: String?
    private let session: URLSession

    public init(baseURL: String, apiKey: String?) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        self.session = URLSession(configuration: config)
    }

    public func availableModels() async throws -> [LLMModel] {
        ModelCatalog.anthropicChat
    }

    public func streamChat(messages: [ChatMessage], model: LLMModel, options: ChatOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let text = try await complete(messages: messages, model: model, options: options)
                    continuation.yield(text)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func complete(messages: [ChatMessage], model: LLMModel, options: ChatOptions) async throws -> String {
        guard let apiKey, !apiKey.isEmpty else { throw LLMError.missingAPIKey(.anthropic) }
        guard let url = URL(string: baseURL.trimmingTrailingSlash + "/messages") else {
            throw LLMError.invalidBaseURL(baseURL)
        }

        let system = messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n")
        let turns = messages.filter { $0.role != .system }
            .map { Request.Message(role: $0.role.rawValue, content: $0.content) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(Request(
            // Anthropic requires max_tokens. Default generously so polished /
            // rewritten dictation isn't silently truncated mid-sentence (the
            // old 1024 cap cut off a few minutes of speech). Callers may override.
            model: model.id,
            max_tokens: options.maxTokens ?? 8192,
            system: system.isEmpty ? nil : system,
            temperature: options.temperature,
            messages: turns
        ))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LLMError.network("No HTTP response") }
        guard 200..<300 ~= http.statusCode else {
            throw LLMError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.content.compactMap { $0.text }.joined()
    }

    private struct Request: Encodable {
        struct Message: Encodable { let role: String; let content: String }
        let model: String
        let max_tokens: Int
        let system: String?
        let temperature: Double?
        let messages: [Message]
    }
    private struct Response: Decodable {
        struct Block: Decodable { let type: String; let text: String? }
        let content: [Block]
    }
}
