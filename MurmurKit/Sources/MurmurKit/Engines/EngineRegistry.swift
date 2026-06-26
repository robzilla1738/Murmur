import Foundation

/// Builds the currently-selected transcription engine and LLM provider from
/// `AppSettings` + `KeychainStore`. Centralizes wiring so the dictation pipeline
/// doesn't know about concrete engine types.
@MainActor
public final class EngineRegistry {
    private let settings: AppSettings
    private let keychain: KeychainStore

    /// One prepared transcription engine shared by Settings ("Download & load")
    /// and the dictation pipeline, so warming the model once benefits both.
    private var prepared: (key: String, engine: any TranscriptionEngine)?
    /// In-flight prepare, so concurrent callers await the same work.
    private var preparing: (key: String, task: Task<any TranscriptionEngine, Error>)?

    public init(settings: AppSettings, keychain: KeychainStore) {
        self.settings = settings
        self.keychain = keychain
    }

    public func currentTranscriptionModel() -> TranscriptionModel {
        settings.selectedTranscriptionModel(for: settings.transcriptionEngineID)
    }

    /// Identity of the currently-selected engine+model.
    private func currentKey() -> String {
        "\(settings.transcriptionEngineID.rawValue)-\(currentTranscriptionModel().id)"
    }

    /// Whether the currently-selected engine+model is already prepared in memory.
    public var isCurrentEnginePrepared: Bool {
        prepared?.key == currentKey()
    }

    /// Return a prepared engine for the current settings, reusing the cached one
    /// when the engine+model is unchanged. Cloud engines "prepare" instantly;
    /// local engines download (first run) + load CoreML. Concurrent calls for the
    /// same key share one prepare task.
    public func preparedTranscriptionEngine(
        progress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws -> any TranscriptionEngine {
        let key = currentKey()

        if let prepared, prepared.key == key { progress(1); return prepared.engine }
        if let preparing, preparing.key == key { return try await preparing.task.value }

        // Switching engine/model — drop the old one.
        if let old = prepared { await old.engine.unload(); self.prepared = nil }

        let engine = try makeTranscriptionEngine()
        let model = currentTranscriptionModel()
        let task = Task<any TranscriptionEngine, Error> {
            try await engine.prepare(model: model, progress: progress)
            return engine
        }
        preparing = (key, task)
        defer { if preparing?.key == key { preparing = nil } }

        do {
            let ready = try await task.value
            prepared = (key, ready)
            return ready
        } catch {
            // Leave nothing cached so the next attempt retries cleanly.
            if prepared?.key == key { prepared = nil }
            throw error
        }
    }

    /// Drop any prepared/in-flight engine (e.g. when the user changes engine/model).
    public func resetPreparedEngine() {
        let old = prepared
        prepared = nil
        preparing?.task.cancel()
        preparing = nil
        if let old { Task { await old.engine.unload() } }
    }

    /// Construct the transcription engine for the current settings.
    public func makeTranscriptionEngine() throws -> any TranscriptionEngine {
        let id = settings.transcriptionEngineID
        let model = settings.selectedTranscriptionModel(for: id)

        switch id {
        case .openAI, .groq:
            let key = keychain.value(for: id.keychainAccount)
            return CloudTranscriptionEngine(
                id: id,
                baseURL: Self.transcriptionBaseURL(for: id),
                apiKey: key,
                modelID: model.id
            )
        case .parakeet:
            return ParakeetEngine(model: model)
        case .whisperKit:
            return WhisperKitEngine(model: model)
        case .deepgram:
            return DeepgramTranscriptionEngine(apiKey: keychain.value(for: id.keychainAccount), modelID: model.id)
        case .assemblyAI:
            return AssemblyAITranscriptionEngine(apiKey: keychain.value(for: id.keychainAccount), modelID: model.id)
        case .elevenLabs:
            return ElevenLabsTranscriptionEngine(apiKey: keychain.value(for: id.keychainAccount), modelID: model.id)
        }
    }

    /// Construct the LLM provider used for Polish / Command Mode.
    public func makeLLMProvider() -> any LLMProvider {
        let id = settings.llmProviderID
        let baseURL = settings.baseURL(for: id)
        let key = keychain.value(for: id.keychainAccount)

        switch id {
        case .anthropic:
            return AnthropicProvider(baseURL: baseURL, apiKey: key)
        case .lmStudio, .ollama, .openAI, .groq:
            return OpenAICompatibleProvider(id: id, baseURL: baseURL, apiKey: key)
        }
    }

    public func currentLLMModel() -> LLMModel? {
        let id = settings.llmProviderID
        guard let modelID = settings.selectedLLMModelID(for: id) else { return nil }
        let known = ModelCatalog.chatModels(for: id).first { $0.id == modelID }
        return known ?? LLMModel(id: modelID)
    }

    static func transcriptionBaseURL(for id: TranscriptionEngineID) -> String {
        switch id {
        case .openAI: "https://api.openai.com/v1"
        case .groq: "https://api.groq.com/openai/v1"
        case .deepgram: "https://api.deepgram.com/v1"
        case .assemblyAI: "https://api.assemblyai.com/v2"
        case .elevenLabs: "https://api.elevenlabs.io/v1"
        case .parakeet, .whisperKit: ""
        }
    }
}
