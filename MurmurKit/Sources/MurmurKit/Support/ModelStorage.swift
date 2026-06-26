import Foundation

/// Where Murmur stores downloaded on-device models.
///
/// Both local engines must download into `~/Library/Application Support/Murmur/models`
/// rather than their library defaults. WhisperKit (via swift-transformers `HubApi`)
/// otherwise downloads into `~/Documents/huggingface`, which is **TCC-gated** for a
/// hardened-runtime, non-sandboxed Developer ID app: the first write to the user's
/// Documents folder needs an interactive grant that a menu-bar agent can't reliably
/// surface, so the download fails silently. Application Support has no such gate and
/// is the correct location for app data.
public enum ModelStorage {
    /// Root directory for all downloaded models: `~/Library/Application Support/Murmur/models`.
    public static var modelsDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Murmur", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Subdirectory for WhisperKit / Hugging Face downloads (passed as `downloadBase`).
    public static var whisperKitDirectory: URL {
        let dir = modelsDirectory.appendingPathComponent("whisperkit", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Subdirectory for FluidAudio / Parakeet downloads.
    public static var parakeetDirectory: URL {
        let dir = modelsDirectory.appendingPathComponent("parakeet", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
