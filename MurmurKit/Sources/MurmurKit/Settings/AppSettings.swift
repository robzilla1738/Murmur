import Foundation
import Observation

/// Observable, `UserDefaults`-backed user preferences. Scalar/enum settings live
/// here; API keys live in `KeychainStore`. Stored properties persist via `didSet`
/// (which doesn't fire during `init`, so loading defaults doesn't re-write them).
@MainActor
@Observable
public final class AppSettings {
    private let defaults: UserDefaults

    // MARK: Transcription
    public var transcriptionEngineID: TranscriptionEngineID {
        didSet { defaults.set(transcriptionEngineID.rawValue, forKey: Keys.transcriptionEngineID) }
    }

    // MARK: AI cleanup ("Polish")
    public var polishEnabled: Bool {
        didSet { defaults.set(polishEnabled, forKey: Keys.polishEnabled) }
    }
    public var llmProviderID: LLMProviderID {
        didSet { defaults.set(llmProviderID.rawValue, forKey: Keys.llmProviderID) }
    }
    public var lmStudioBaseURL: String {
        didSet { defaults.set(lmStudioBaseURL, forKey: Keys.lmStudioBaseURL) }
    }
    public var ollamaBaseURL: String {
        didSet { defaults.set(ollamaBaseURL, forKey: Keys.ollamaBaseURL) }
    }

    // MARK: Activation / input
    public var activationMode: ActivationMode {
        didSet { defaults.set(activationMode.rawValue, forKey: Keys.activationMode) }
    }
    public var pushToTalkKey: PushToTalkKey {
        didSet { defaults.set(pushToTalkKey.rawValue, forKey: Keys.pushToTalkKey) }
    }
    public var inputDeviceUID: String? {
        didSet { defaults.set(inputDeviceUID, forKey: Keys.inputDeviceUID) }
    }

    // MARK: Language
    /// `nil` = auto-detect.
    public var language: String? {
        didSet { defaults.set(language, forKey: Keys.language) }
    }

    // MARK: HUD
    public var hudStyle: HUDStyle {
        didSet { defaults.set(hudStyle.rawValue, forKey: Keys.hudStyle) }
    }

    // MARK: Transforms (hotkey-bound rewrite actions)
    public var transforms: [TransformSlot] {
        didSet { persistJSON(transforms, forKey: Keys.transforms) }
    }

    // MARK: Per-engine/provider model selection (JSON-encoded maps)
    private var transcriptionModelIDs: [String: String] {
        didSet { persistJSON(transcriptionModelIDs, forKey: Keys.transcriptionModelIDs) }
    }
    private var llmModelIDs: [String: String] {
        didSet { persistJSON(llmModelIDs, forKey: Keys.llmModelIDs) }
    }

    // MARK: Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.transcriptionEngineID = defaults.string(forKey: Keys.transcriptionEngineID)
            .flatMap(TranscriptionEngineID.init(rawValue:)) ?? .openAI
        self.polishEnabled = defaults.object(forKey: Keys.polishEnabled) as? Bool ?? true
        self.llmProviderID = defaults.string(forKey: Keys.llmProviderID)
            .flatMap(LLMProviderID.init(rawValue:)) ?? .openAI
        self.lmStudioBaseURL = defaults.string(forKey: Keys.lmStudioBaseURL) ?? LLMProviderID.lmStudio.defaultBaseURL
        self.ollamaBaseURL = defaults.string(forKey: Keys.ollamaBaseURL) ?? LLMProviderID.ollama.defaultBaseURL
        self.activationMode = defaults.string(forKey: Keys.activationMode)
            .flatMap(ActivationMode.init(rawValue:)) ?? .pushToTalk
        self.pushToTalkKey = defaults.string(forKey: Keys.pushToTalkKey)
            .flatMap(PushToTalkKey.init(rawValue:)) ?? .rightCommand
        self.inputDeviceUID = defaults.string(forKey: Keys.inputDeviceUID)
        self.language = defaults.string(forKey: Keys.language)
        self.hudStyle = defaults.string(forKey: Keys.hudStyle)
            .flatMap(HUDStyle.init(rawValue:)) ?? .auto
        self.transcriptionModelIDs = Self.loadJSON([String: String].self, from: defaults, key: Keys.transcriptionModelIDs) ?? [:]
        self.llmModelIDs = Self.loadJSON([String: String].self, from: defaults, key: Keys.llmModelIDs) ?? [:]
        self.transforms = Self.loadJSON([TransformSlot].self, from: defaults, key: Keys.transforms) ?? TransformSlot.defaults
    }

    // MARK: Model selection accessors

    public func selectedTranscriptionModel(for engine: TranscriptionEngineID) -> TranscriptionModel {
        let models = ModelCatalog.transcriptionModels(for: engine)
        if let id = transcriptionModelIDs[engine.rawValue], let match = models.first(where: { $0.id == id }) {
            return match
        }
        return ModelCatalog.defaultTranscriptionModel(for: engine)
    }

    public func setSelectedTranscriptionModel(_ id: String, for engine: TranscriptionEngineID) {
        transcriptionModelIDs[engine.rawValue] = id
    }

    public func selectedLLMModelID(for provider: LLMProviderID) -> String? {
        if let id = llmModelIDs[provider.rawValue] { return id }
        return ModelCatalog.chatModels(for: provider).first?.id
    }

    public func setSelectedLLMModelID(_ id: String, for provider: LLMProviderID) {
        llmModelIDs[provider.rawValue] = id
    }

    /// Resolved base URL for an LLM provider (local providers honor the editable override).
    public func baseURL(for provider: LLMProviderID) -> String {
        switch provider {
        case .lmStudio: lmStudioBaseURL
        case .ollama: ollamaBaseURL
        default: provider.defaultBaseURL
        }
    }

    // MARK: JSON persistence helpers

    private func persistJSON<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func loadJSON<T: Decodable>(_ type: T.Type, from defaults: UserDefaults, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private enum Keys {
        static let transcriptionEngineID = "transcriptionEngineID"
        static let polishEnabled = "polishEnabled"
        static let llmProviderID = "llmProviderID"
        static let lmStudioBaseURL = "lmStudioBaseURL"
        static let ollamaBaseURL = "ollamaBaseURL"
        static let activationMode = "activationMode"
        static let pushToTalkKey = "pushToTalkKey"
        static let inputDeviceUID = "inputDeviceUID"
        static let language = "language"
        static let hudStyle = "hudStyle"
        static let transcriptionModelIDs = "transcriptionModelIDs"
        static let llmModelIDs = "llmModelIDs"
        static let transforms = "transforms"
    }
}
