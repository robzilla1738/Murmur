import Foundation

/// Transcription engine for OpenAI-compatible `/audio/transcriptions` endpoints
/// (OpenAI, Groq). Uploads 16 kHz mono audio as WAV via multipart form.
public final class CloudTranscriptionEngine: TranscriptionEngine, @unchecked Sendable {
    public let id: TranscriptionEngineID
    private let baseURL: String
    private let apiKey: String?
    private let modelID: String
    private let session: URLSession

    public init(id: TranscriptionEngineID, baseURL: String, apiKey: String?, modelID: String) {
        self.id = id
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelID = modelID
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)
    }

    public func prepare(model: TranscriptionModel, progress: @Sendable @escaping (Double) -> Void) async throws {
        if id.requiresAPIKey, (apiKey ?? "").isEmpty {
            throw TranscriptionError.missingAPIKey(id)
        }
        progress(1)
    }

    public func transcribe(samples: [Float], options: TranscriptionOptions) async throws -> TranscriptionResult {
        guard !samples.isEmpty else { throw TranscriptionError.emptyAudio }
        guard let apiKey, !apiKey.isEmpty else { throw TranscriptionError.missingAPIKey(id) }
        guard let url = URL(string: baseURL.trimmingTrailingSlash + "/audio/transcriptions") else {
            throw TranscriptionError.network("Invalid base URL")
        }

        let wav = WAVEncoder.encode(samples: samples)

        var form = MultipartFormData()
        form.addFile(name: "file", filename: "audio.wav", contentType: "audio/wav", data: wav)
        form.addField(name: "model", value: modelID)
        form.addField(name: "response_format", value: "json")
        if let language = options.language { form.addField(name: "language", value: language) }
        if let prompt = options.prompt, !prompt.isEmpty { form.addField(name: "prompt", value: prompt) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finalized()

        let started = Date()
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw TranscriptionError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.network("No HTTP response")
        }
        guard 200..<300 ~= http.statusCode else {
            throw TranscriptionError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }

        do {
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            return TranscriptionResult(
                text: decoded.text.trimmingCharacters(in: .whitespacesAndNewlines),
                language: decoded.language,
                duration: Date().timeIntervalSince(started)
            )
        } catch {
            throw TranscriptionError.decoding(error.localizedDescription)
        }
    }

    private struct Response: Decodable {
        let text: String
        let language: String?
    }
}
