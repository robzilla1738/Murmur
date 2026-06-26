import Foundation

/// Context that shapes the cleanup pass — the focused app (for tone) and
/// custom vocabulary (for correct spelling of names/jargon).
public struct PolishContext: Sendable {
    public var frontmostAppName: String?
    public var frontmostBundleID: String?
    public var dictionaryTerms: [String]

    public init(frontmostAppName: String? = nil, frontmostBundleID: String? = nil, dictionaryTerms: [String] = []) {
        self.frontmostAppName = frontmostAppName
        self.frontmostBundleID = frontmostBundleID
        self.dictionaryTerms = dictionaryTerms
    }
}

/// Turns a raw transcript into clean, ready-to-insert text via an LLM: strips
/// filler words, fixes punctuation/casing, and lightly formats — without
/// changing meaning or adding commentary.
public struct PolishService: Sendable {
    public init() {}

    public func polish(raw: String, context: PolishContext, provider: any LLMProvider, model: LLMModel) async throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let messages: [ChatMessage] = [
            .system(Self.systemPrompt(context: context)),
            .user(trimmed),
        ]
        let result = try await provider.chat(
            messages: messages,
            model: model,
            options: ChatOptions(temperature: 0.2)
        )
        let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? trimmed : cleaned
    }

    static func systemPrompt(context: PolishContext) -> String {
        var prompt = """
        You are a dictation cleanup engine. The user spoke text aloud and it was \
        transcribed. Rewrite the transcript into clean, polished written text.

        Rules:
        - Remove filler words (um, uh, like, you know) and false starts.
        - Fix punctuation, capitalization, and obvious transcription errors.
        - Honor spoken self-corrections (e.g. "send it Tuesday, no, Wednesday" → "send it Wednesday").
        - Format spoken lists as lists when clearly intended.
        - Preserve the speaker's meaning, wording, and language. Do not translate.
        - Do not add greetings, sign-offs, explanations, or commentary.
        - Output ONLY the cleaned text, nothing else.
        """

        if let app = context.frontmostAppName {
            prompt += "\n\nThe text is being written in \(app); match an appropriate tone."
        }
        if let hint = appToneHint(bundleID: context.frontmostBundleID) {
            prompt += " \(hint)"
        }
        if !context.dictionaryTerms.isEmpty {
            let terms = context.dictionaryTerms.joined(separator: ", ")
            prompt += "\n\nSpell these terms correctly when they occur: \(terms)."
        }
        return prompt
    }

    /// Light, app-aware tone guidance keyed off the focused app's bundle id.
    private static func appToneHint(bundleID: String?) -> String? {
        guard let bundleID else { return nil }
        let id = bundleID.lowercased()
        if id.contains("terminal") || id.contains("iterm") || id.contains("ghostty") || id.contains("warp") {
            return "This is a terminal — keep it terse and preserve any commands or code verbatim."
        }
        if id.contains("xcode") || id.contains("vscode") || id.contains("code") || id.contains("cursor") || id.contains("sublime") || id.contains("jetbrains") {
            return "This is a code editor — preserve identifiers, code, and formatting; don't prose-ify code."
        }
        if id.contains("mail") || id.contains("outlook") || id.contains("spark") {
            return "This is email — use clear, professional prose."
        }
        if id.contains("slack") || id.contains("discord") || id.contains("messages") || id.contains("whatsapp") || id.contains("telegram") {
            return "This is a chat app — keep it casual and concise."
        }
        return nil
    }
}
