import SwiftUI

/// The floating-pill recording HUD — a Liquid Glass capsule that appears near
/// the screen edge during dictation. Used on non-notch displays or when the
/// user prefers the pill.
struct FlowBarView: View {
    var controller: DictationController

    var body: some View {
        HUDContent(controller: controller)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .glassSurface(in: Capsule())
            .overlay(
                Capsule().strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
            )
            .fixedSize()
            .padding(8) // room for the panel's shadow
    }
}
