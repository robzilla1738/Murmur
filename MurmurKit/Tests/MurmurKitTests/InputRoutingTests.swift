import Testing
@testable import MurmurKit

/// Pure routing rules behind the dictation triggers — the logic that was wrong
/// before (a tapped combo got discarded). Fast, no I/O, always runs.
@Suite("Input routing")
struct InputRoutingTests {
    /// A combo (⌃⌥D) is a tap: it must toggle on key-down and do nothing on
    /// key-up, in *every* activation mode. This is what makes tap-to-transcribe work.
    @Test func comboAlwaysTogglesOnDownInEveryMode() {
        for mode in ActivationMode.allCases {
            #expect(InputRouting.onDown(.combo, mode: mode) == .toggle)
            #expect(InputRouting.onUp(.combo, mode: mode) == .ignore)
        }
    }

    /// The modifier key is hold-to-talk in push-to-talk mode: begin on down,
    /// finish on up.
    @Test func modifierIsHoldToTalkInPushToTalk() {
        #expect(InputRouting.onDown(.modifier, mode: .pushToTalk) == .begin)
        #expect(InputRouting.onUp(.modifier, mode: .pushToTalk) == .finish)
    }

    /// In hands-free mode the modifier key toggles instead (down toggles, up ignored).
    @Test func modifierTogglesInHandsFree() {
        #expect(InputRouting.onDown(.modifier, mode: .handsFree) == .toggle)
        #expect(InputRouting.onUp(.modifier, mode: .handsFree) == .ignore)
    }
}
