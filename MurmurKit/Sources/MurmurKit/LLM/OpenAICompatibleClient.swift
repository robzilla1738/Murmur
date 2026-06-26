import Foundation

/// Shared wire client for OpenAI-compatible `/chat/completions` + `/models`
/// endpoints. Used by LM Studio, Ollama (/v1 shim), OpenAI, and Groq — they
/// differ only in base URL and auth.
public struct OpenAICompatibleClient: Sendable {
    let baseURL: String
    let apiKey: String?
    private let session: URLSession

    public init(baseURL: String, apiKey: String?) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        self.session = URLSession(configuration: config)
    }

    public func listModels() async throws -> [LLMModel] {
        guard let url = URL(string: baseURL.trimmingTrailingSlash + "/models") else {
            throw LLMError.invalidBaseURL(baseURL)
        }
        var request = URLRequest(url: url)
        authorize(&request)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return [] }
        let decoded = try JSONDecoder().decode(ModelList.self, from: data)
        return decoded.data.map { LLMModel(id: $0.id) }
    }

    public func streamChat(messages: [ChatMessage], model: LLMModel, options: ChatOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = URL(string: baseURL.trimmingTrailingSlash + "/chat/completions") else {
                        throw LLMError.invalidBaseURL(baseURL)
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    authorize(&request)

                    let body = ChatRequest(
                        model: model.id,
                        messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) },
                        stream: true,
                        temperature: options.temperature,
                        max_tokens: options.maxTokens
                    )
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw LLMError.network("No HTTP response")
                    }
                    guard 200..<300 ~= http.statusCode else {
                        var errorBody = ""
                        for try await line in bytes.lines { errorBody += line }
                        throw LLMError.http(status: http.statusCode, body: errorBody)
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8) else { continue }
                        if let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                           let delta = chunk.choices.first?.delta.content, !delta.isEmpty {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func authorize(_ request: inout URLRequest) {
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
    }

    // MARK: Wire types

    private struct ChatRequest: Encodable {
        struct Message: Encodable { let role: String; let content: String }
        let model: String
        let messages: [Message]
        let stream: Bool
        let temperature: Double?
        let max_tokens: Int?
    }
    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta
        }
        let choices: [Choice]
    }
    private struct ModelList: Decodable {
        struct Entry: Decodable { let id: String }
        let data: [Entry]
    }
}
