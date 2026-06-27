import Foundation

/// What kind of trigger fired a dictation event.
public enum DictationTrigger: Sendable {
    /// A discrete key combo (e.g. ⌃⌥D). Pressed and released as a tap — there's
    /// no meaningful "hold", so it always toggles.
    case combo
    /// A modifier-only key (e.g. Right ⌘) driven by the `flagsChanged` event tap.
    /// Supports hold-to-talk.
    case modifier
}

/// The dictation intent a trigger maps to.
public enum DictationAction: Equatable, Sendable {
    case begin    // start recording (push-to-talk key down)
    case finish   // stop + transcribe (push-to-talk key up)
    case toggle   // start if idle, stop if recording
    case ignore   // do nothing
}

/// Pure mapping from a trigger + the user's activation mode to a dictation
/// action. Kept here (UI-free, unit-tested) so the AppKit hotkey closures hold no
/// untested branching — the source of the "tap does nothing" bug.
///
/// Design: a **combo always toggles** (tap to start, tap to stop) so the
/// permission-free ⌃⌥D shortcut works out of the box, while the **modifier key**
/// is the dedicated hold-to-talk path in push-to-talk mode. Both work at once.
public enum InputRouting {
    /// Action for a trigger's key-down.
    public static func onDown(_ trigger: DictationTrigger, mode: ActivationMode) -> DictationAction {
        switch trigger {
        case .combo:
            return .toggle
        case .modifier:
            return mode == .pushToTalk ? .begin : .toggle
        }
    }

    /// Action for a trigger's key-up.
    public static func onUp(_ trigger: DictationTrigger, mode: ActivationMode) -> DictationAction {
        switch trigger {
        case .combo:
            return .ignore
        case .modifier:
            return mode == .pushToTalk ? .finish : .ignore
        }
    }
}
