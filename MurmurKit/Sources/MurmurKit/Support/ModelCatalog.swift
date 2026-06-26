import Foundation

/// Known default models per engine/provider. Local engines auto-download these;
/// cloud entries are suggestions — users can type any model id, and local LLM
/// servers report their own list at runtime (see `LocalServerDetector`).
public enum ModelCatalog {

    // MARK: Transcription

    public static let parakeet: [TranscriptionModel] = [
        TranscriptionModel(id: "parakeet-tdt-0.6b-v3", displayName: "Parakeet TDT v3 (multilingual)", approxSizeMB: 600, isMultilingual: true),
        TranscriptionModel(id: "parakeet-tdt-0.6b-v2", displayName: "Parakeet TDT v2 (English)", approxSizeMB: 600, isMultilingual: false),
    ]

    public static let whisperKit: [TranscriptionModel] = [
        TranscriptionModel(id: "openai_whisper-large-v3-v20240930_turbo_632MB", displayName: "Whisper large-v3 turbo", approxSizeMB: 632, isMultilingual: true),
        TranscriptionModel(id: "openai_whisper-large-v3-v20240930_626MB", displayName: "Whisper large-v3", approxSizeMB: 626, isMultilingual: true),
        TranscriptionModel(id: "openai_whisper-base", displayName: "Whisper base (fast, small)", approxSizeMB: 145, isMultilingual: true),
    ]

    public static let openAITranscription: [TranscriptionModel] = [
        TranscriptionModel(id: "gpt-4o-transcribe", displayName: "gpt-4o-transcribe"),
        TranscriptionModel(id: "gpt-4o-mini-transcribe", displayName: "gpt-4o-mini-transcribe"),
        TranscriptionModel(id: "whisper-1", displayName: "whisper-1"),
    ]

    public static let groqTranscription: [TranscriptionModel] = [
        TranscriptionModel(id: "whisper-large-v3-turbo", displayName: "whisper-large-v3-turbo"),
        TranscriptionModel(id: "whisper-large-v3", displayName: "whisper-large-v3"),
    ]

    public static func transcriptionModels(for id: TranscriptionEngineID) -> [TranscriptionModel] {
        switch id {
        case .parakeet: parakeet
        case .whisperKit: whisperKit
        case .openAI: openAITranscription
        case .groq: groqTranscription
        case .deepgram: [TranscriptionModel(id: "nova-3", displayName: "Nova-3")]
        case .assemblyAI: [TranscriptionModel(id: "universal", displayName: "Universal")]
        case .elevenLabs: [TranscriptionModel(id: "scribe_v1", displayName: "Scribe v1")]
        }
    }

    public static func defaultTranscriptionModel(for id: TranscriptionEngineID) -> TranscriptionModel {
        transcriptionModels(for: id).first
            ?? TranscriptionModel(id: "default", displayName: "Default")
    }

    // MARK: Chat (Polish / Command Mode)

    public static let openAIChat: [LLMModel] = [
        LLMModel(id: "gpt-4o-mini", displayName: "gpt-4o-mini (fast)"),
        LLMModel(id: "gpt-4o", displayName: "gpt-4o"),
    ]

    public static let groqChat: [LLMModel] = [
        LLMModel(id: "llama-3.3-70b-versatile", displayName: "Llama 3.3 70B"),
        LLMModel(id: "llama-3.1-8b-instant", displayName: "Llama 3.1 8B (instant)"),
    ]

    public static let anthropicChat: [LLMModel] = [
        LLMModel(id: "claude-haiku-4-5-20251001", displayName: "Claude Haiku 4.5 (fast)"),
        LLMModel(id: "claude-sonnet-4-6", displayName: "Claude Sonnet 4.6"),
    ]

    public static func chatModels(for id: LLMProviderID) -> [LLMModel] {
        switch id {
        case .openAI: openAIChat
        case .groq: groqChat
        case .anthropic: anthropicChat
        case .lmStudio, .ollama: []   // fetched live from the running server
        }
    }
}
