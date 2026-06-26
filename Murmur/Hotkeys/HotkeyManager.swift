import KeyboardShortcuts

/// User-customizable global shortcuts (normal key + modifier combos) via the
/// KeyboardShortcuts library. Complements `PushToTalkTap`, which handles
/// modifier-only hold-to-talk that this library can't express.
extension KeyboardShortcuts.Name {
    /// Toggle / hold dictation. Ships with a safe default (⌃⌥D) so there's a
    /// working, discoverable shortcut out of the box in addition to the
    /// modifier-only push-to-talk key. `default:` only seeds if the user hasn't
    /// already chosen one.
    static let toggleDictation = Self("toggleDictation", default: .init(.d, modifiers: [.control, .option]))
    /// Cancel an in-progress dictation.
    static let cancelDictation = Self("cancelDictation")
    /// Toggle Command Mode (voice editing of the current selection).
    static let commandMode = Self("commandMode")
    /// Open the Scratchpad notes window.
    static let openScratchpad = Self("openScratchpad")

    /// Eight Transform slots.
    static let transformSlots: [Self] = (1...8).map { Self("transform\($0)") }
}

@MainActor
final class HotkeyManager {
    /// Dictation shortcut pressed (hold-to-talk: begin; hands-free: toggle).
    var onDictationDown: (@MainActor () -> Void)?
    /// Dictation shortcut released (hold-to-talk: finish; hands-free: ignored).
    var onDictationUp: (@MainActor () -> Void)?
    var onCancel: (@MainActor () -> Void)?
    var onCommandMode: (@MainActor () -> Void)?
    var onScratchpad: (@MainActor () -> Void)?
    var onTransform: (@MainActor (Int) -> Void)?

    func register() {
        KeyboardShortcuts.onKeyDown(for: .toggleDictation) { [weak self] in self?.onDictationDown?() }
        KeyboardShortcuts.onKeyUp(for: .toggleDictation) { [weak self] in self?.onDictationUp?() }
        KeyboardShortcuts.onKeyDown(for: .cancelDictation) { [weak self] in self?.onCancel?() }
        KeyboardShortcuts.onKeyDown(for: .commandMode) { [weak self] in self?.onCommandMode?() }
        KeyboardShortcuts.onKeyDown(for: .openScratchpad) { [weak self] in self?.onScratchpad?() }

        for (index, name) in KeyboardShortcuts.Name.transformSlots.enumerated() {
            KeyboardShortcuts.onKeyDown(for: name) { [weak self] in self?.onTransform?(index) }
        }
    }
}
