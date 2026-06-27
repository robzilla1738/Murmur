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
        TranscriptionModel(id: "gpt-4o-transcribe", displayName: "GPT-4o Transcribe (best)"),
        TranscriptionModel(id: "gpt-4o-mini-transcribe", displayName: "GPT-4o mini Transcribe (cheap)"),
        TranscriptionModel(id: "whisper-1", displayName: "Whisper v1 (legacy)"),
    ]

    public static let groqTranscription: [TranscriptionModel] = [
        TranscriptionModel(id: "whisper-large-v3-turbo", displayName: "Whisper Large v3 Turbo (fast)"),
        TranscriptionModel(id: "whisper-large-v3", displayName: "Whisper Large v3 (accurate)"),
    ]

    public static let deepgramTranscription: [TranscriptionModel] = [
        TranscriptionModel(id: "nova-3", displayName: "Nova-3 (best)"),
        TranscriptionModel(id: "nova-2", displayName: "Nova-2 (legacy)"),
    ]

    // AssemblyAI's current API takes a `speech_models` array; these are the
    // current flagship values (the legacy single `speech_model` strings like
    // "best"/"nano" are deprecated). Universal-3 Pro is the recommended default.
    public static let assemblyAITranscription: [TranscriptionModel] = [
        TranscriptionModel(id: "universal-3-pro", displayName: "Universal-3 Pro (best)"),
        TranscriptionModel(id: "universal-2", displayName: "Universal-2 (90+ languages)"),
        TranscriptionModel(id: "universal-3-5-pro", displayName: "Universal-3.5 Pro (preview)"),
    ]

    public static let elevenLabsTranscription: [TranscriptionModel] = [
        TranscriptionModel(id: "scribe_v2", displayName: "Scribe v2 (best)"),
    ]

    public static func transcriptionModels(for id: TranscriptionEngineID) -> [TranscriptionModel] {
        switch id {
        case .parakeet: parakeet
        case .whisperKit: whisperKit
        case .openAI: openAITranscription
        case .groq: groqTranscription
        case .deepgram: deepgramTranscription
        case .assemblyAI: assemblyAITranscription
        case .elevenLabs: elevenLabsTranscription
        }
    }

    public static func defaultTranscriptionModel(for id: TranscriptionEngineID) -> TranscriptionModel {
        transcriptionModels(for: id).first
            ?? TranscriptionModel(id: "default", displayName: "Default")
    }

    // MARK: Chat (Polish / Command Mode)

    // First entry is the default. For text cleanup we favor the fast/cheap tier.
    public static let openAIChat: [LLMModel] = [
        LLMModel(id: "gpt-5.4-mini", displayName: "GPT-5.4 mini (fast, default)"),
        LLMModel(id: "gpt-5.4-nano", displayName: "GPT-5.4 nano (cheapest)"),
        LLMModel(id: "gpt-5.5", displayName: "GPT-5.5 (flagship)"),
    ]

    // The classic Llama IDs on Groq are deprecated (hard shutdown Aug 2026);
    // GPT-OSS is the current durable, production lineup.
    public static let groqChat: [LLMModel] = [
        LLMModel(id: "openai/gpt-oss-20b", displayName: "GPT-OSS 20B (fast, default)"),
        LLMModel(id: "openai/gpt-oss-120b", displayName: "GPT-OSS 120B (quality)"),
        LLMModel(id: "qwen/qwen3.6-27b", displayName: "Qwen 3.6 27B (preview)"),
    ]

    public static let anthropicChat: [LLMModel] = [
        LLMModel(id: "claude-haiku-4-5", displayName: "Claude Haiku 4.5 (fast, default)"),
        LLMModel(id: "claude-sonnet-4-6", displayName: "Claude Sonnet 4.6 (balanced)"),
        LLMModel(id: "claude-opus-4-8", displayName: "Claude Opus 4.8 (flagship)"),
        LLMModel(id: "claude-fable-5", displayName: "Claude Fable 5 (most capable)"),
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
