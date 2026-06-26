import Foundation

/// A modifier-only key usable for hold-to-talk. These can't be expressed as
/// normal shortcuts (there's no non-modifier key), so they're driven by a
/// `CGEventTap` on `flagsChanged` rather than the KeyboardShortcuts library.
public enum PushToTalkKey: String, Codable, CaseIterable, Sendable, Identifiable {
    case fn
    case rightOption
    case rightCommand
    case rightControl
    case leftControl

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fn: "Fn (Globe)"
        case .rightOption: "Right Option ⌥"
        case .rightCommand: "Right Command ⌘"
        case .rightControl: "Right Control ⌃"
        case .leftControl: "Left Control ⌃"
        }
    }
}

/// Which recording HUD surface to show.
public enum HUDStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case auto   // notch on notch-displays, pill otherwise
    case notch
    case pill

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: "Automatic"
        case .notch: "Notch"
        case .pill: "Floating pill"
        }
    }
}

/// A user-defined rewrite action bound to a hotkey slot (Wispr-style Transform).
public struct TransformSlot: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var prompt: String

    public init(id: UUID = UUID(), name: String, prompt: String) {
        self.id = id
        self.name = name
        self.prompt = prompt
    }

    /// The default starter set (users can edit/add up to `maxSlots`).
    public static let maxSlots = 8
    public static let defaults: [TransformSlot] = [
        TransformSlot(name: "Make concise", prompt: "Make this more concise while keeping the meaning."),
        TransformSlot(name: "Fix grammar", prompt: "Fix grammar, spelling, and punctuation. Keep the wording otherwise."),
        TransformSlot(name: "Professional", prompt: "Rewrite this in a clear, professional tone."),
        TransformSlot(name: "Bullet points", prompt: "Turn this into a clean bulleted list."),
    ]
}

/// How dictation is triggered.
public enum ActivationMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case pushToTalk   // hold to record, release to transcribe
    case handsFree    // tap to start, tap (or silence) to stop

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pushToTalk: "Push to talk"
        case .handsFree: "Hands-free"
        }
    }
}
