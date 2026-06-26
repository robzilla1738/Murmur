import AVFoundation
import Foundation
import Testing
@testable import MurmurKit

/// End-to-end local-transcription check. Gated behind `MURMUR_LIVE_ASR=1` because
/// it downloads a ~600MB CoreML model on first run and needs a real audio file.
///
/// Generate the sample first:
///   say -o /tmp/murmur_test.aiff "Testing Murmur local transcription, one two three."
///   afconvert -f WAVE -d LEI16@16000 -c 1 /tmp/murmur_test.aiff /tmp/murmur_test.wav
///   MURMUR_LIVE_ASR=1 swift test --filter parakeetTranscribesRealAudio
@Test(.enabled(if: ProcessInfo.processInfo.environment["MURMUR_LIVE_ASR"] == "1"))
func parakeetTranscribesRealAudio() async throws {
    let path = ProcessInfo.processInfo.environment["MURMUR_LIVE_WAV"] ?? "/tmp/murmur_test.wav"
    let samples = try loadMonoFloat16k(URL(fileURLWithPath: path))
    #expect(samples.count > 16_000, "expected >1s of audio, got \(samples.count) samples")

    let model = ModelCatalog.defaultTranscriptionModel(for: .parakeet)
    let engine = ParakeetEngine(model: model)
    try await engine.prepare(model: model) { p in
        if p == 1 { print("Parakeet model ready (downloaded to \(ModelStorage.modelsDirectory.path))") }
    }

    // Run twice to prove the fresh-decoder-state fix: the 2nd dictation must be
    // just as good as the 1st (no state bleed).
    let first = try await engine.transcribe(samples: samples, options: TranscriptionOptions(language: "en"))
    let second = try await engine.transcribe(samples: samples, options: TranscriptionOptions(language: "en"))
    print("ASR #1: \(first.text)")
    print("ASR #2: \(second.text)")

    #expect(!first.text.isEmpty, "first transcription was empty")
    #expect(!second.text.isEmpty, "second transcription was empty (decoder-state bleed?)")
    let normalized = first.text.lowercased()
    #expect(normalized.contains("murmur") || normalized.contains("transcription") || normalized.contains("test"),
            "transcript didn't contain expected words: \(first.text)")
    #expect(second.text == first.text, "same audio gave different results across runs: '\(first.text)' vs '\(second.text)'")
}

/// End-to-end WhisperKit check: granular download progress, load from the
/// Application-Support folder (not ~/Documents), and transcribe. Uses the small
/// `openai_whisper-base` model by default for speed.
@Test(.enabled(if: ProcessInfo.processInfo.environment["MURMUR_LIVE_ASR"] == "1"))
func whisperKitTranscribesRealAudio() async throws {
    let path = ProcessInfo.processInfo.environment["MURMUR_LIVE_WAV"] ?? "/tmp/murmur_test.wav"
    let samples = try loadMonoFloat16k(URL(fileURLWithPath: path))

    let modelID = ProcessInfo.processInfo.environment["MURMUR_WK_MODEL"] ?? "openai_whisper-base"
    let model = TranscriptionModel(id: modelID, displayName: modelID)
    let engine = WhisperKitEngine(model: model)

    let maxProgress = MaxProgress()
    try await engine.prepare(model: model) { p in
        if maxProgress.bump(p) { print("WhisperKit progress: \(Int(p * 100))%") }
    }
    // Progress must actually move past the old fixed 0.05 plateau.
    #expect(maxProgress.value > 0.05, "download progress never advanced past 5% (the stuck-at-5% bug)")

    let result = try await engine.transcribe(samples: samples, options: TranscriptionOptions(language: "en"))
    print("WhisperKit ASR: \(result.text)")
    #expect(!result.text.isEmpty, "WhisperKit transcription was empty")
    let n = result.text.lowercased()
    #expect(n.contains("murmur") || n.contains("transcription") || n.contains("test") || n.contains("fox"),
            "transcript didn't contain expected words: \(result.text)")
}

/// Thread-safe max-progress tracker for the `@Sendable` progress callback.
private final class MaxProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0.0
    var value: Double { lock.lock(); defer { lock.unlock() }; return _value }
    /// Record `p`; returns true when it advanced by a visible step.
    func bump(_ p: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard p > _value + 0.1 else { return false }
        _value = p
        return true
    }
}

/// Load any audio file as 16 kHz mono Float32 — the format every engine expects.
private func loadMonoFloat16k(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    guard let converter = AVAudioConverter(from: file.processingFormat, to: outFormat) else {
        throw NSError(domain: "LiveASRTests", code: 1)
    }
    let capacity = AVAudioFrameCount(Double(file.length) * 16_000 / file.processingFormat.sampleRate + 4096)
    guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else {
        throw NSError(domain: "LiveASRTests", code: 2)
    }

    var done = false
    var convError: NSError?
    converter.convert(to: out, error: &convError) { _, status in
        if done { status.pointee = .endOfStream; return nil }
        let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        do { try file.read(into: inBuf) } catch { status.pointee = .endOfStream; return nil }
        done = true
        status.pointee = .haveData
        return inBuf
    }
    if let convError { throw convError }

    let n = Int(out.frameLength)
    guard let ch = out.floatChannelData?[0] else { return [] }
    return Array(UnsafeBufferPointer(start: ch, count: n))
}
