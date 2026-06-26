import Foundation

/// Top-level namespace + metadata for the Murmur engine package.
///
/// `MurmurKit` holds the engine-agnostic dictation pipeline: transcription
/// engines (local Whisper / Parakeet + cloud), LLM "Polish" providers, audio
/// capture, settings, and data models. It is UI-framework-free so it can be
/// exercised headlessly with `swift test`.
public enum Murmur {
    /// Marketing version, kept in sync with the app target's `MARKETING_VERSION`.
    public static let version = "0.1.0"
}
