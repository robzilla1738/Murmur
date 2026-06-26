import Foundation

/// Builds the currently-selected transcription engine and LLM provider from
/// `AppSettings` + `KeychainStore`. Centralizes wiring so the dictation pipeline
/// doesn't know about concrete engine types.
@MainActor
public final class EngineRegistry {
    private let settings: AppSettings
    private let keychain: KeychainStore

    public init(settings: AppSettings, keychain: KeychainStore) {
        self.settings = settings
        self.keychain = keychain
    }

    public func currentTranscriptionModel() -> TranscriptionModel {
        settings.selectedTranscriptionModel(for: settings.transcriptionEngineID)
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
