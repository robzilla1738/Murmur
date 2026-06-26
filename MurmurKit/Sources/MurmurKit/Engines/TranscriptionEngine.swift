import Foundation

// MARK: - Identity

/// Every transcription backend Murmur can use, local or cloud.
public enum TranscriptionEngineID: String, Codable, CaseIterable, Sendable, Identifiable {
    case parakeet      // FluidAudio (NVIDIA Parakeet, CoreML/ANE) — local
    case whisperKit    // Argmax WhisperKit (Whisper, CoreML/ANE)  — local
    case openAI        // gpt-4o-transcribe / whisper-1            — cloud
    case groq          // whisper-large-v3-turbo                   — cloud
    case deepgram      // Nova-3                                   — cloud
    case assemblyAI    // Universal                                — cloud
    case elevenLabs    // Scribe                                   — cloud

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .parakeet: "Parakeet (local)"
        case .whisperKit: "Whisper (local)"
        case .openAI: "OpenAI"
        case .groq: "Groq"
        case .deepgram: "Deepgram"
        case .assemblyAI: "AssemblyAI"
        case .elevenLabs: "ElevenLabs"
        }
    }

    /// Local engines run fully on-device; cloud engines upload audio to an API.
    public var isLocal: Bool {
        switch self {
        case .parakeet, .whisperKit: true
        default: false
        }
    }

    public var requiresAPIKey: Bool { !isLocal }

    /// Keychain account under which this engine's API key is stored.
    public var keychainAccount: String { "transcription.\(rawValue)" }
}

// MARK: - Model + options

/// A selectable model within an engine (a Whisper variant, a Parakeet version,
/// or a cloud model id).
public struct TranscriptionModel: Identifiable, Codable, Sendable, Hashable {
    public let id: String              // engine-specific identifier
    public let displayName: String
    public let approxSizeMB: Int?      // nil for cloud models
    public let isMultilingual: Bool

    public init(id: String, displayName: String, approxSizeMB: Int? = nil, isMultilingual: Bool = true) {
        self.id = id
        self.displayName = displayName
        self.approxSizeMB = approxSizeMB
        self.isMultilingual = isMultilingual
    }
}

public struct TranscriptionOptions: Sendable {
    /// BCP-47 / ISO language code, or `nil` to auto-detect.
    public var language: String?
    /// Optional priming text to bias vocabulary (names, jargon).
    public var prompt: String?

    public init(language: String? = nil, prompt: String? = nil) {
        self.language = language
        self.prompt = prompt
    }
}

public struct TranscriptionResult: Sendable {
    public var text: String
    public var language: String?
    public var confidence: Double?
    public var duration: TimeInterval?

    public init(text: String, language: String? = nil, confidence: Double? = nil, duration: TimeInterval? = nil) {
        self.text = text
        self.language = language
        self.confidence = confidence
        self.duration = duration
    }
}

// MARK: - Errors

public enum TranscriptionError: LocalizedError {
    case missingAPIKey(TranscriptionEngineID)
    case modelNotPrepared
    case emptyAudio
    case http(status: Int, body: String)
    case network(String)
    case decoding(String)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let id): "No API key set for \(id.displayName). Add one in Settings."
        case .modelNotPrepared: "The transcription model isn't loaded yet."
        case .emptyAudio: "No audio was captured."
        case .http(let status, let body): "Transcription request failed (HTTP \(status)). \(body)"
        case .network(let message): "Network error: \(message)"
        case .decoding(let message): "Couldn't read the transcription response: \(message)"
        case .unsupported(let message): message
        }
    }
}

// MARK: - Protocol

/// A speech-to-text backend. Local engines manage a CoreML model lifecycle;
/// cloud engines validate a key in `prepare` and upload audio in `transcribe`.
///
/// Audio is always 16 kHz mono Float32 (see `AudioCaptureEngine`).
public protocol TranscriptionEngine: Sendable {
    var id: TranscriptionEngineID { get }
    var displayName: String { get }
    var isLocal: Bool { get }
    var availableModels: [TranscriptionModel] { get }

    /// Local: download (if needed) + load the model into memory. Cloud: validate
    /// configuration. `progress` reports 0…1 during local downloads.
    func prepare(model: TranscriptionModel, progress: @Sendable @escaping (Double) -> Void) async throws

    /// Transcribe 16 kHz mono Float32 samples.
    func transcribe(samples: [Float], options: TranscriptionOptions) async throws -> TranscriptionResult

    /// Release any loaded model / resources.
    func unload() async
}

public extension TranscriptionEngine {
    var displayName: String { id.displayName }
    var isLocal: Bool { id.isLocal }
    var availableModels: [TranscriptionModel] { ModelCatalog.transcriptionModels(for: id) }
    func unload() async {}

    func prepare(model: TranscriptionModel) async throws {
        try await prepare(model: model, progress: { _ in })
    }
}
