import Foundation
import Testing
@testable import MurmurKit

@Test func versionIsSet() {
    #expect(Murmur.version == "0.1.0")
}

// MARK: - WAV encoding

@Test func wavEncoderProducesValidHeader() {
    let samples = [Float](repeating: 0, count: 16_000) // 1s silence @ 16kHz
    let data = WAVEncoder.encode(samples: samples)

    #expect(data.count == 44 + samples.count * 2) // 16-bit PCM
    #expect(data.prefix(4) == Data("RIFF".utf8))
    #expect(data.subdata(in: 8..<12) == Data("WAVE".utf8))
    #expect(data.subdata(in: 36..<40) == Data("data".utf8))
}

// MARK: - Model catalog

@Test func everyTranscriptionEngineHasModels() {
    for engine in TranscriptionEngineID.allCases {
        #expect(!ModelCatalog.transcriptionModels(for: engine).isEmpty, "no models for \(engine)")
    }
}

@Test func localEnginesAreFlaggedLocal() {
    #expect(TranscriptionEngineID.parakeet.isLocal)
    #expect(TranscriptionEngineID.whisperKit.isLocal)
    #expect(!TranscriptionEngineID.openAI.isLocal)
    #expect(TranscriptionEngineID.openAI.requiresAPIKey)
}

// MARK: - Polish prompt

@Test func polishPromptIncludesRulesAndDictionary() {
    let context = PolishContext(frontmostAppName: "Mail", dictionaryTerms: ["Kubernetes", "Murmur"])
    let prompt = PolishService.systemPrompt(context: context)
    #expect(prompt.contains("filler"))
    #expect(prompt.contains("Mail"))
    #expect(prompt.contains("Kubernetes"))
}

// MARK: - Settings persistence

@MainActor
@Test func settingsRoundTripThroughDefaults() {
    let suite = "murmur.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    let settings = AppSettings(defaults: defaults)
    settings.transcriptionEngineID = .groq
    settings.polishEnabled = false
    settings.pushToTalkKey = .fn
    settings.setSelectedTranscriptionModel("whisper-large-v3", for: .groq)

    let reloaded = AppSettings(defaults: defaults)
    #expect(reloaded.transcriptionEngineID == .groq)
    #expect(reloaded.polishEnabled == false)
    #expect(reloaded.pushToTalkKey == .fn)
    #expect(reloaded.selectedTranscriptionModel(for: .groq).id == "whisper-large-v3")
}

// MARK: - Base URL resolution

@MainActor
@Test func localProviderBaseURLOverrides() {
    let suite = "murmur.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    let settings = AppSettings(defaults: defaults)
    #expect(settings.baseURL(for: .ollama).contains("11434"))
    #expect(settings.baseURL(for: .openAI) == "https://api.openai.com/v1")
}
