import Foundation

// MARK: - Deepgram (single request, raw body)

/// Deepgram `/v1/listen` — raw WAV body, `Authorization: Token <key>`.
public final class DeepgramTranscriptionEngine: TranscriptionEngine, @unchecked Sendable {
    public let id = TranscriptionEngineID.deepgram
    private let apiKey: String?
    private let modelID: String
    private let session = URLSession(configuration: .ephemeral)

    public init(apiKey: String?, modelID: String) {
        self.apiKey = apiKey
        self.modelID = modelID
    }

    public func prepare(model: TranscriptionModel, progress: @Sendable @escaping (Double) -> Void) async throws {
        guard !(apiKey ?? "").isEmpty else { throw TranscriptionError.missingAPIKey(id) }
        progress(1)
    }

    public func transcribe(samples: [Float], options: TranscriptionOptions) async throws -> TranscriptionResult {
        guard !samples.isEmpty else { throw TranscriptionError.emptyAudio }
        guard let apiKey, !apiKey.isEmpty else { throw TranscriptionError.missingAPIKey(id) }

        var components = URLComponents(string: "https://api.deepgram.com/v1/listen")!
        var query = [URLQueryItem(name: "model", value: modelID), URLQueryItem(name: "smart_format", value: "true")]
        if let language = options.language { query.append(URLQueryItem(name: "language", value: language)) }
        components.queryItems = query

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = WAVEncoder.encode(samples: samples)

        let (data, response) = try await session.data(for: request)
        try Self.checkStatus(response, data, id)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let text = decoded.results.channels.first?.alternatives.first?.transcript ?? ""
        return TranscriptionResult(text: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private struct Response: Decodable {
        struct Results: Decodable {
            struct Channel: Decodable {
                struct Alternative: Decodable { let transcript: String }
                let alternatives: [Alternative]
            }
            let channels: [Channel]
        }
        let results: Results
    }

    static func checkStatus(_ response: URLResponse, _ data: Data, _ id: TranscriptionEngineID) throws {
        guard let http = response as? HTTPURLResponse else { throw TranscriptionError.network("No HTTP response") }
        guard 200..<300 ~= http.statusCode else {
            throw TranscriptionError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
    }
}

// MARK: - ElevenLabs Scribe (multipart)

/// ElevenLabs `/v1/speech-to-text` — multipart file + `model_id`, `xi-api-key`.
public final class ElevenLabsTranscriptionEngine: TranscriptionEngine, @unchecked Sendable {
    public let id = TranscriptionEngineID.elevenLabs
    private let apiKey: String?
    private let modelID: String
    private let session = URLSession(configuration: .ephemeral)

    public init(apiKey: String?, modelID: String) {
        self.apiKey = apiKey
        self.modelID = modelID
    }

    public func prepare(model: TranscriptionModel, progress: @Sendable @escaping (Double) -> Void) async throws {
        guard !(apiKey ?? "").isEmpty else { throw TranscriptionError.missingAPIKey(id) }
        progress(1)
    }

    public func transcribe(samples: [Float], options: TranscriptionOptions) async throws -> TranscriptionResult {
        guard !samples.isEmpty else { throw TranscriptionError.emptyAudio }
        guard let apiKey, !apiKey.isEmpty else { throw TranscriptionError.missingAPIKey(id) }

        var form = MultipartFormData()
        form.addFile(name: "file", filename: "audio.wav", contentType: "audio/wav", data: WAVEncoder.encode(samples: samples))
        form.addField(name: "model_id", value: modelID)
        if let language = options.language { form.addField(name: "language_code", value: language) }

        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finalized()

        let (data, response) = try await session.data(for: request)
        try DeepgramTranscriptionEngine.checkStatus(response, data, id)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return TranscriptionResult(text: decoded.text.trimmingCharacters(in: .whitespacesAndNewlines), language: decoded.language_code)
    }

    private struct Response: Decodable { let text: String; let language_code: String? }
}

// MARK: - AssemblyAI (upload → create → poll)

/// AssemblyAI — upload bytes, create a transcript, then poll until complete.
public final class AssemblyAITranscriptionEngine: TranscriptionEngine, @unchecked Sendable {
    public let id = TranscriptionEngineID.assemblyAI
    private let apiKey: String?
    private let session = URLSession(configuration: .ephemeral)
    private let base = "https://api.assemblyai.com/v2"

    public init(apiKey: String?, modelID: String) {
        self.apiKey = apiKey
    }

    public func prepare(model: TranscriptionModel, progress: @Sendable @escaping (Double) -> Void) async throws {
        guard !(apiKey ?? "").isEmpty else { throw TranscriptionError.missingAPIKey(id) }
        progress(1)
    }

    public func transcribe(samples: [Float], options: TranscriptionOptions) async throws -> TranscriptionResult {
        guard !samples.isEmpty else { throw TranscriptionError.emptyAudio }
        guard let apiKey, !apiKey.isEmpty else { throw TranscriptionError.missingAPIKey(id) }

        // 1. Upload audio bytes.
        let uploadURL = try await upload(WAVEncoder.encode(samples: samples), apiKey: apiKey)

        // 2. Create transcript.
        let transcriptID = try await create(audioURL: uploadURL, language: options.language, apiKey: apiKey)

        // 3. Poll until completed.
        for _ in 0..<120 { // up to ~60s
            let (status, text) = try await poll(id: transcriptID, apiKey: apiKey)
            switch status {
            case "completed": return TranscriptionResult(text: (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
            case "error": throw TranscriptionError.network("AssemblyAI transcription failed")
            default: try? await Task.sleep(for: .milliseconds(500))
            }
        }
        throw TranscriptionError.network("AssemblyAI timed out")
    }

    private func upload(_ data: Data, apiKey: String) async throws -> String {
        var request = URLRequest(url: URL(string: "\(base)/upload")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let (respData, response) = try await session.data(for: request)
        try DeepgramTranscriptionEngine.checkStatus(response, respData, id)
        return try JSONDecoder().decode(UploadResponse.self, from: respData).upload_url
    }

    private func create(audioURL: String, language: String?, apiKey: String) async throws -> String {
        var request = URLRequest(url: URL(string: "\(base)/transcript")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(CreateRequest(audio_url: audioURL, language_code: language))
        let (respData, response) = try await session.data(for: request)
        try DeepgramTranscriptionEngine.checkStatus(response, respData, id)
        return try JSONDecoder().decode(CreateResponse.self, from: respData).id
    }

    private func poll(id transcriptID: String, apiKey: String) async throws -> (String, String?) {
        var request = URLRequest(url: URL(string: "\(base)/transcript/\(transcriptID)")!)
        request.setValue(apiKey, forHTTPHeaderField: "authorization")
        let (respData, response) = try await session.data(for: request)
        try DeepgramTranscriptionEngine.checkStatus(response, respData, id)
        let decoded = try JSONDecoder().decode(PollResponse.self, from: respData)
        return (decoded.status, decoded.text)
    }

    private struct UploadResponse: Decodable { let upload_url: String }
    private struct CreateRequest: Encodable { let audio_url: String; let language_code: String? }
    private struct CreateResponse: Decodable { let id: String }
    private struct PollResponse: Decodable { let status: String; let text: String? }
}
