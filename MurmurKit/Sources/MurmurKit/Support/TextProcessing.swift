import Foundation

/// Post-transcription text fixups: literal dictionary replacements and snippet
/// expansions. Both are case-insensitive whole-phrase replacements.
public enum TextProcessing {
    public static func applyReplacements(_ text: String, _ pairs: [(from: String, to: String)]) -> String {
        var result = text
        for pair in pairs where !pair.from.isEmpty {
            result = result.replacingOccurrences(
                of: pair.from,
                with: pair.to,
                options: [.caseInsensitive]
            )
        }
        return result
    }
}
