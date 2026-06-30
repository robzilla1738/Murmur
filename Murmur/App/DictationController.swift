import AppKit
import ApplicationServices
import AVFoundation
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
    /// Silence cutoff on the *compressed* level scale (`min(1, sqrt(rms)*2.5)`
    /// from AudioCaptureEngine). Typical room ambient compresses to ~0.05–0.11
    /// and speech to ~0.3–1.0; 0.15 sits cleanly between so hands-free actually
    /// auto-stops on real silence (0.06 was below the ambient floor and never fired).
    private let silenceThreshold: Float = 0.15
    private let silenceTimeout: TimeInterval = 2.0

    /// SwiftData context for History (set by `AppDelegate`).
    var historyContext: ModelContext?

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

        // Surface a denied mic instead of silently recording silence. `.notDetermined`
        // still proceeds — AVAudioEngine.start() triggers the first-run system prompt.
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .denied || micStatus == .restricted {
            fail(TranscriptionError.unsupported("Microphone access is off for Murmur. Turn it on in System Settings → Privacy & Security → Microphone."))
            return
        }

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
            Log.pipeline.info("Recording started (mode=\(String(describing: mode), privacy: .public), engine=\(self.settings.transcriptionEngineID.rawValue, privacy: .public), autoStop=\(autoStop))")
        } catch {
            Log.pipeline.error("audio.start failed: \(error, privacy: .public)")
            fail(error)
        }
    }

    func finish() {
        guard state == .recording else { return }
        let samples = audio.stop()
        let duration = recordingStart.map { Date().timeIntervalSince($0) } ?? 0
        Log.pipeline.info("finish: \(samples.count) samples, \(String(format: "%.2f", duration))s")

        guard duration >= minRecordingDuration, !samples.isEmpty else {
            Log.pipeline.info("Discarded: too short or empty (need ≥\(self.minRecordingDuration)s and audio). Check Microphone permission.")
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
            Log.pipeline.info("Transcribed \(raw.count) chars; trusted(paste)=\(self.insertion.isTrusted)")
            guard !raw.isEmpty else { Log.pipeline.info("Empty transcript — nothing to insert"); state = .idle; return }

            var text = raw
            if settings.polishEnabled {
                state = .polishing
                text = await polished(raw, terms: vocab.terms)
            }

            // Literal dictionary replacements + snippet expansions.
            text = TextProcessing.applyReplacements(text, vocab.replacements + vocab.snippets)

            // Always save the transcript first, so it's never lost if paste can't run.
            recordHistory(raw: raw, final: text, duration: duration)
            guard insertion.isTrusted else {
                handleUntrusted(text, noun: "text")
                return
            }
            state = .inserting
            Log.insertion.info("Pasting \(text.count, privacy: .public) chars via ⌘V")
            insertion.insert(text)
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
        guard registry.canPolish, let model = registry.currentLLMModel() else {
            state = .error("Add an AI provider in Settings → AI Polish to use this — set a provider key, or run LM Studio/Ollama.")
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
            guard insertion.isTrusted else {
                handleUntrusted(output, noun: "result")
                return
            }
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
        do {
            try context.save()
        } catch {
            // The transcript is still on the clipboard after paste, so it isn't
            // truly lost, but a persistent save failure shouldn't be silent.
            Log.pipeline.error("Failed to save history item: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Get the prepared engine from the shared registry cache, surfacing local
    /// download progress in the HUD. Settings "Download & load" warms the very
    /// same engine, so a model downloaded there is reused here instantly.
    private func prepareEngine() async throws -> any TranscriptionEngine {
        let isLocal = settings.transcriptionEngineID.isLocal
        if isLocal, !registry.isCurrentEnginePrepared {
            state = .downloading(0)
        }
        let engine = try await registry.preparedTranscriptionEngine { [weak self] progress in
            Task { @MainActor in
                guard let self, isLocal, progress < 1 else { return }
                if case .transcribing = self.state { self.state = .downloading(progress) }
                else if case .downloading = self.state { self.state = .downloading(progress) }
            }
        }
        // A first-run download leaves the state at the last `downloading` value;
        // move back to `transcribing` so the HUD reflects the actual next step.
        if case .downloading = state { state = .transcribing }
        return engine
    }

    /// Run AI cleanup; on failure, fall back to the raw transcript.
    private func polished(_ raw: String, terms: [String]) async -> String {
        // No usable LLM (no key, no local server) → skip the call entirely and
        // insert the raw transcript instead of paying for a guaranteed-failing request.
        guard registry.canPolish, let model = registry.currentLLMModel() else { return raw }
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

    /// Transcription succeeded but we can't paste (no Accessibility). Keep the
    /// text on the clipboard so it's never lost, surface a clear message, and
    /// guide the user to grant the permission (once per launch).
    private func handleUntrusted(_ text: String, noun: String) {
        Log.insertion.error("Not trusted for Accessibility — copied to clipboard instead of pasting")
        insertion.copyToClipboard(text)
        state = .error("Turn on Accessibility for Murmur to paste — your \(noun) is on the clipboard (press ⌘V).")
        scheduleErrorReset()
        promptForAccessibility()
    }

    private var didPromptForAccessibility = false
    /// Show the system Accessibility prompt (with an "Open System Settings"
    /// button) once, so the user can grant the permission that makes pasting work.
    private func promptForAccessibility() {
        guard !didPromptForAccessibility else { return }
        didPromptForAccessibility = true
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
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
            try? await Task.sleep(for: .seconds(6))
            // If this task was superseded (another error scheduled a new reset),
            // don't fire — otherwise the cancelled task clears the NEW error early.
            guard !Task.isCancelled else { return }
            if case .error = self?.state { self?.state = .idle }
        }
    }
}
