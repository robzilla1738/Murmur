import AppKit
import MurmurKit
import Observation
import SwiftData

/// The dictation pipeline state machine — the brain that orchestrates audio
/// capture, transcription, AI Polish, and text insertion.
///
/// `idle → recording → transcribing → polishing → inserting → idle`
/// (cancel or error → idle). The HUD and status item observe `state`/`levels`.
@MainActor
@Observable
final class DictationController {
    enum State: Equatable {
        case idle
        case recording
        case transcribing
        case polishing
        case inserting
        case downloading(Double)   // local model first-run
        case error(String)

        var isActive: Bool { self != .idle }
    }

    private(set) var state: State = .idle
    /// Recent RMS levels (newest last) for the live waveform.
    private(set) var levels: [Float] = []

    private let settings: AppSettings
    private let registry: EngineRegistry
    private let audio: AudioCaptureEngine
    private let insertion: TextInsertionService
    private let accessibility: AccessibilityReader
    private let polish = PolishService()
    private let rewrite = RewriteService()

    private enum Mode { case dictation, command }
    private var mode: Mode = .dictation

    // Hands-free silence auto-stop
    private var autoStop = false
    private var silenceStart: Date?
    private var hasSpoken = false
    private let silenceThreshold: Float = 0.06
    private let silenceTimeout: TimeInterval = 2.0

    /// SwiftData context for History (set by `AppDelegate`).
    var historyContext: ModelContext?

    /// Cached prepared transcription engine, keyed by engine+model.
    private var prepared: (key: String, engine: any TranscriptionEngine)?
    private var targetApp: AccessibilityReader.FrontmostApp?
    private var commandSelection: String?
    private var recordingStart: Date?
    private var errorResetTask: Task<Void, Never>?

    private let maxLevels = 48
    private let minRecordingDuration: TimeInterval = 0.3

    init(
        settings: AppSettings,
        registry: EngineRegistry,
        audio: AudioCaptureEngine = AudioCaptureEngine(),
        insertion: TextInsertionService,
        accessibility: AccessibilityReader
    ) {
        self.settings = settings
        self.registry = registry
        self.audio = audio
        self.insertion = insertion
        self.accessibility = accessibility
    }

    // MARK: Intents

    /// Hands-free toggle: start if idle, finish if recording. Enables silence
    /// auto-stop when the user's activation mode is hands-free.
    func toggle() {
        switch state {
        case .idle: startRecording(mode: .dictation, autoStop: settings.activationMode == .handsFree)
        case .recording: finish()
        default: break
        }
    }

    /// Command Mode toggle: speak an instruction to edit the current selection.
    func toggleCommand() {
        switch state {
        case .idle: startRecording(mode: .command, autoStop: false)
        case .recording where mode == .command: finish()
        default: break
        }
    }

    /// Push-to-talk start (held key). No silence auto-stop — release ends it.
    func begin() {
        startRecording(mode: .dictation, autoStop: false)
    }

    private func startRecording(mode: Mode, autoStop: Bool) {
        guard state == .idle else { return }
        self.mode = mode
        self.autoStop = autoStop
        silenceStart = nil
        hasSpoken = false
        errorResetTask?.cancel()
        targetApp = accessibility.frontmostApp()
        // Capture the selection now (before our HUD/paste changes focus) for Command Mode.
        commandSelection = mode == .command ? accessibility.selectedText() : nil
        levels = []
        recordingStart = Date()

        do {
            try audio.start(deviceUID: settings.inputDeviceUID) { [weak self] level in
                Task { @MainActor in self?.appendLevel(level) }
            }
            state = .recording
        } catch {
            fail(error)
        }
    }

    func finish() {
        guard state == .recording else { return }
        let samples = audio.stop()
        let duration = recordingStart.map { Date().timeIntervalSince($0) } ?? 0

        guard duration >= minRecordingDuration, !samples.isEmpty else {
            state = .idle
            return
        }
        state = .transcribing
        let currentMode = mode
        Task {
            if currentMode == .command {
                await runCommandPipeline(samples: samples)
            } else {
                await runPipeline(samples: samples, duration: duration)
            }
        }
    }

    /// Run a Transform: apply a saved rewrite instruction to the current selection.
    func runTransform(_ index: Int) {
        guard state == .idle else { return }
        let transforms = settings.transforms
        guard index < transforms.count else { return }
        let instruction = transforms[index].prompt
        Task { await applyRewrite(instruction: instruction, spokenSelection: nil) }
    }

    func cancel() {
        audio.cancel()
        errorResetTask?.cancel()
        levels = []
        state = .idle
    }

    // MARK: Pipeline

    private func runPipeline(samples: [Float], duration: TimeInterval) async {
        do {
            let vocab = loadVocabulary()

            let engine = try await prepareEngine()
            let options = TranscriptionOptions(
                language: settings.language,
                prompt: vocab.terms.isEmpty ? nil : vocab.terms.joined(separator: ", ")
            )
            let result = try await engine.transcribe(samples: samples, options: options)

            let raw = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { state = .idle; return }

            var text = raw
            if settings.polishEnabled {
                state = .polishing
                text = await polished(raw, terms: vocab.terms)
            }

            // Literal dictionary replacements + snippet expansions.
            text = TextProcessing.applyReplacements(text, vocab.replacements + vocab.snippets)

            state = .inserting
            insertion.insert(text)
            recordHistory(raw: raw, final: text, duration: duration)
            state = .idle
        } catch {
            fail(error)
        }
    }

    private struct Vocabulary {
        var terms: [String]                          // spelling/biasing hints
        var replacements: [(from: String, to: String)]
        var snippets: [(from: String, to: String)]
    }

    private func loadVocabulary() -> Vocabulary {
        guard let context = historyContext else { return Vocabulary(terms: [], replacements: [], snippets: []) }
        let entries = (try? context.fetch(FetchDescriptor<DictionaryEntry>())) ?? []
        let snippets = (try? context.fetch(FetchDescriptor<Snippet>())) ?? []
        return Vocabulary(
            terms: entries.map(\.phrase),
            replacements: entries.compactMap { entry in
                guard let replacement = entry.replacement, !replacement.isEmpty else { return nil }
                return (from: entry.phrase, to: replacement)
            },
            snippets: snippets.map { (from: $0.trigger, to: $0.expansion) }
        )
    }

    /// Command Mode: transcribe the spoken instruction, then apply it to the
    /// selection captured when recording started.
    private func runCommandPipeline(samples: [Float]) async {
        do {
            let engine = try await prepareEngine()
            let result = try await engine.transcribe(samples: samples, options: TranscriptionOptions(language: settings.language))
            let instruction = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !instruction.isEmpty else { state = .idle; return }
            await applyRewrite(instruction: instruction, spokenSelection: commandSelection)
        } catch {
            fail(error)
        }
    }

    /// Shared rewrite path for Transforms and Command Mode. Reads the selection
    /// (preferring an already-captured one), rewrites it, and pastes the result.
    private func applyRewrite(instruction: String, spokenSelection: String?) async {
        guard let model = registry.currentLLMModel() else {
            state = .error("Select an AI model in Settings → AI Polish to use this.")
            scheduleErrorReset()
            return
        }
        state = .polishing
        var selection = spokenSelection ?? accessibility.selectedText()
        if selection == nil {
            selection = await insertion.readSelectionViaCopy()
        }
        let provider = registry.makeLLMProvider()
        do {
            let output = try await rewrite.rewrite(instruction: instruction, selection: selection, provider: provider, model: model)
            guard !output.isEmpty else { state = .idle; return }
            state = .inserting
            insertion.insert(output)
            state = .idle
        } catch {
            fail(error)
        }
    }

    private func recordHistory(raw: String, final: String, duration: TimeInterval) {
        guard let context = historyContext else { return }
        let item = HistoryItem(
            rawText: raw,
            polishedText: final,
            engineID: settings.transcriptionEngineID.rawValue,
            appName: targetApp?.name,
            durationMs: Int(duration * 1000)
        )
        context.insert(item)
        try? context.save()
    }

    /// Build + prepare the selected engine, reusing the cached one when possible.
    private func prepareEngine() async throws -> any TranscriptionEngine {
        let model = registry.currentTranscriptionModel()
        let key = "\(settings.transcriptionEngineID.rawValue)-\(model.id)"
        if let prepared, prepared.key == key { return prepared.engine }

        if let old = prepared { await old.engine.unload() }

        let engine = try registry.makeTranscriptionEngine()
        try await engine.prepare(model: model) { [weak self] progress in
            Task { @MainActor in
                guard let self, progress < 1 else { return }
                if engine.isLocal { self.state = .downloading(progress) }
            }
        }
        prepared = (key, engine)
        return engine
    }

    /// Run AI cleanup; on failure, fall back to the raw transcript.
    private func polished(_ raw: String, terms: [String]) async -> String {
        guard let model = registry.currentLLMModel() else { return raw }
        let provider = registry.makeLLMProvider()
        let context = PolishContext(
            frontmostAppName: targetApp?.name,
            frontmostBundleID: targetApp?.bundleID,
            dictionaryTerms: terms
        )
        do {
            return try await polish.polish(raw: raw, context: context, provider: provider, model: model)
        } catch {
            Log.pipeline.error("Polish failed, inserting raw transcript: \(error.localizedDescription)")
            return raw
        }
    }

    // MARK: Helpers

    private func appendLevel(_ level: Float) {
        levels.append(level)
        if levels.count > maxLevels { levels.removeFirst(levels.count - maxLevels) }

        guard autoStop, state == .recording else { return }
        if level > silenceThreshold {
            hasSpoken = true
            silenceStart = nil
        } else if hasSpoken {
            if let start = silenceStart {
                if Date().timeIntervalSince(start) > silenceTimeout { finish() }
            } else {
                silenceStart = Date()
            }
        }
    }

    private func fail(_ error: Error) {
        audio.cancel()
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        Log.pipeline.error("Dictation failed: \(message, privacy: .public)")
        state = .error(message)
        scheduleErrorReset()
    }

    #if DEBUG
    /// Drives the HUD into a fake recording state (no audio) for screenshots /
    /// design iteration. Triggered by the `-hudDemo` launch argument.
    func startDemo() {
        guard state == .idle else { return }
        state = .recording
        Task { @MainActor in
            for i in 0..<120 {
                try? await Task.sleep(for: .milliseconds(80))
                appendLevel(Float(abs(sin(Double(i) * 0.5)) * 0.9 + 0.1))
            }
            state = .idle
        }
    }
    #endif

    private func scheduleErrorReset() {
        errorResetTask?.cancel()
        errorResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            if case .error = self?.state { self?.state = .idle }
        }
    }
}
