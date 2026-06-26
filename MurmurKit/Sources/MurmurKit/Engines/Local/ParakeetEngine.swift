import FluidAudio
import Foundation

/// Local transcription via FluidAudio's Parakeet TDT (CoreML / Apple Neural
/// Engine). Models auto-download from Hugging Face on first `prepare`.
///
/// An actor: it owns the `AsrManager` and a reusable decoder state. Sync
/// protocol metadata (`id`, etc.) is satisfied by `nonisolated` members and the
/// protocol's default implementations.
public actor ParakeetEngine: TranscriptionEngine {
    public nonisolated let id = TranscriptionEngineID.parakeet

    private let version: AsrModelVersion
    private var manager: AsrManager?
    private var decoderState: TdtDecoderState?

    public init(model: TranscriptionModel) {
        switch model.id {
        case "parakeet-tdt-0.6b-v2": self.version = .v2
        default: self.version = .v3
        }
    }

    public func prepare(model: TranscriptionModel, progress: @Sendable @escaping (Double) -> Void) async throws {
        if manager != nil { progress(1); return }

        let models = try await AsrModels.downloadAndLoad(
            version: version,
            progressHandler: { p in progress(p.fractionCompleted) }
        )
        let manager = AsrManager()
        try await manager.loadModels(models)

        self.manager = manager
        self.decoderState = try TdtDecoderState()
        progress(1)
        Log.engine.info("Parakeet \(String(describing: self.version), privacy: .public) ready")
    }

    public func transcribe(samples: [Float], options: TranscriptionOptions) async throws -> TranscriptionResult {
        guard !samples.isEmpty else { throw TranscriptionError.emptyAudio }
        guard let manager else { throw TranscriptionError.modelNotPrepared }

        var state = try decoderState ?? TdtDecoderState()
        let language = options.language.flatMap { Language(rawValue: $0) }
        let result = try await manager.transcribe(samples, decoderState: &state, language: language)
        self.decoderState = state

        return TranscriptionResult(
            text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
            language: options.language,
            confidence: Double(result.confidence),
            duration: result.duration
        )
    }

    public func unload() async {
        if let manager { await manager.cleanup() }
        manager = nil
        decoderState = nil
    }
}
