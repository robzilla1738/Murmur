import KeyboardShortcuts

/// User-customizable global shortcuts (normal key + modifier combos) via the
/// KeyboardShortcuts library. Complements `PushToTalkTap`, which handles
/// modifier-only hold-to-talk that this library can't express.
extension KeyboardShortcuts.Name {
    /// Toggle hands-free dictation on/off.
    static let toggleDictation = Self("toggleDictation")
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
    var onToggle: (@MainActor () -> Void)?
    var onCancel: (@MainActor () -> Void)?
    var onCommandMode: (@MainActor () -> Void)?
    var onScratchpad: (@MainActor () -> Void)?
    var onTransform: (@MainActor (Int) -> Void)?

    func register() {
        KeyboardShortcuts.onKeyDown(for: .toggleDictation) { [weak self] in self?.onToggle?() }
        KeyboardShortcuts.onKeyDown(for: .cancelDictation) { [weak self] in self?.onCancel?() }
        KeyboardShortcuts.onKeyDown(for: .commandMode) { [weak self] in self?.onCommandMode?() }
        KeyboardShortcuts.onKeyDown(for: .openScratchpad) { [weak self] in self?.onScratchpad?() }

        for (index, name) in KeyboardShortcuts.Name.transformSlots.enumerated() {
            KeyboardShortcuts.onKeyDown(for: name) { [weak self] in self?.onTransform?(index) }
        }
    }
}
