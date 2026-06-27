import Foundation

/// Encodes 16 kHz mono Float32 samples to a 16-bit PCM WAV `Data` blob for
/// upload to cloud transcription APIs (OpenAI, Groq, …).
public enum WAVEncoder {
    public static func encode(samples: [Float], sampleRate: Int = 16_000) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let blockAlign = numChannels * bitsPerSample / 8
        let byteRate = UInt32(sampleRate) * UInt32(blockAlign)

        // Float → Int16 LE (native little-endian on Apple Silicon).
        var pcm = [Int16](repeating: 0, count: samples.count)
        for i in samples.indices {
            let clamped = max(-1, min(1, samples[i]))
            pcm[i] = Int16(clamped * 32_767)
        }

        // WAV size fields are 32-bit. Clamp so the Int→UInt32 conversion can't
        // trap on a pathological multi-hour recording (a >4 GB payload can't be
        // represented by a WAV header regardless).
        let byteCount = pcm.count * MemoryLayout<Int16>.size
        let dataSize = UInt32(min(byteCount, Int(UInt32.max) - 44))

        var data = Data(capacity: 44 + byteCount)
        data.append(ascii: "RIFF")
        data.append(le: 36 + dataSize)
        data.append(ascii: "WAVE")
        data.append(ascii: "fmt ")
        data.append(le: UInt32(16))            // PCM fmt chunk size
        data.append(le: UInt16(1))             // PCM format
        data.append(le: numChannels)
        data.append(le: UInt32(sampleRate))
        data.append(le: byteRate)
        data.append(le: blockAlign)
        data.append(le: bitsPerSample)
        data.append(ascii: "data")
        data.append(le: dataSize)
        // Append PCM bytes directly into `data` — no intermediate Data copy.
        pcm.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
}

private extension Data {
    mutating func append(ascii string: String) {
        append(contentsOf: string.utf8)
    }
    mutating func append(le value: UInt16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
    mutating func append(le value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}
