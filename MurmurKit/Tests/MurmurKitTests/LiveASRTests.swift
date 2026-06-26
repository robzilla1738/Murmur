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
