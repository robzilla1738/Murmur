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
        // WhisperKit downloads + loads inside init; no granular callback, so we
        // report start/finish and let the HUD show the downloading state.
        //
        // `downloadBase` is explicit: WhisperKit's HubApi otherwise writes to
        // ~/Documents/huggingface, which is TCC-gated for our hardened-runtime
        // menu-bar agent and fails the download silently. See `ModelStorage`.
        progress(0.05)
        let config = WhisperKitConfig(
            model: model.id,
            downloadBase: ModelStorage.whisperKitDirectory,
            download: true
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
