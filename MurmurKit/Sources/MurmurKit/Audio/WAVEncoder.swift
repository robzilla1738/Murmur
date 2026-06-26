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
        let pcmData = pcm.withUnsafeBytes { Data($0) }
        let dataSize = UInt32(pcmData.count)

        var data = Data(capacity: 44 + pcmData.count)
        data.append(ascii: "RIFF")
        data.append(le: UInt32(36) + dataSize)
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
        data.append(pcmData)
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
