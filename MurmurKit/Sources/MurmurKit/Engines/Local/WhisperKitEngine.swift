import Foundation
import WhisperKit

/// Local transcription via Argmax WhisperKit (Whisper on CoreML / Apple Neural
/// Engine). Models auto-download from Hugging Face on first `prepare`.
///
/// A `final class @unchecked Sendable` rather than an actor: `WhisperKit` is a
/// non-Sendable `open class`, so invoking it from an actor trips the Swift 6
/// "sending" check. The dictation pipeline serializes prepare → transcribe, so
/// access to `whisperKit` is single-threaded in practice.
///
/// Note: WhisperKit also defines a `TranscriptionResult`, so our type is
/// qualified as `MurmurKit.TranscriptionResult` here to disambiguate.
public final class WhisperKitEngine: TranscriptionEngine, @unchecked Sendable {
    public let id = TranscriptionEngineID.whisperKit

    private let modelName: String
    private var whisperKit: WhisperKit?

    public init(model: TranscriptionModel) {
        self.modelName = model.id
    }

    public func prepare(model: TranscriptionModel, progress: @Sendable @escaping (Double) -> Void) async throws {
        if whisperKit != nil { progress(1); return }

        // Download in a SEPARATE step so we get granular progress. Initializing
        // `WhisperKit(config)` with `download: true` reports nothing, so a slow
        // ~600MB download looks frozen. `downloadBase` is explicit because
        // WhisperKit's HubApi otherwise writes to ~/Documents/huggingface, which
        // is TCC-gated for our hardened-runtime menu-bar agent and fails the
        // download silently. See `ModelStorage`.
        progress(0.01)
        let modelFolder = try await WhisperKit.download(
            variant: model.id,
            downloadBase: ModelStorage.whisperKitDirectory,
            progressCallback: { p in
                // Reserve the top slice for the CoreML compile/load step below.
                progress(max(0.01, p.fractionCompleted * 0.9))
            }
        )

        // Compiling + loading the CoreML models has no progress; sit near the top.
        progress(0.95)
        let config = WhisperKitConfig(
            model: model.id,
            downloadBase: ModelStorage.whisperKitDirectory, // tokenizer fetch → App Support, not ~/Documents
            modelFolder: modelFolder.path,
            download: false
        )
        whisperKit = try await WhisperKit(config)
        progress(1)
        Log.engine.info("WhisperKit \(model.id, privacy: .public) ready")
    }

    public func transcribe(samples: [Float], options: TranscriptionOptions) async throws -> MurmurKit.TranscriptionResult {
        guard !samples.isEmpty else { throw TranscriptionError.emptyAudio }
        guard let whisperKit else { throw TranscriptionError.modelNotPrepared }

        let decodeOptions = DecodingOptions(language: options.language)
        let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: decodeOptions)
        let text = results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return MurmurKit.TranscriptionResult(text: text, language: results.first?.language)
    }

    public func unload() async {
        whisperKit = nil
    }
}
