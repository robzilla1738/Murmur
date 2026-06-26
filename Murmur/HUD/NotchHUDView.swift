import SwiftUI

/// The notch-anchored recording HUD — a black shell shaped like the camera
/// housing that hangs from the top of the display and holds the dictation
/// status. Used on notch displays (or when the user forces the notch style).
struct NotchHUDView: View {
    var controller: DictationController
    /// Safe-area top inset (the physical notch height) so content clears the camera.
    var topInset: CGFloat

    var body: some View {
        // Compact bar that hangs just below the notch. The top portion sits
        // behind the menu bar / camera housing (black on black, so it merges);
        // the visible content sits below that line.
        let topClearance = max(topInset, 24)
        HUDContent(controller: controller, onDark: true)
            .padding(.horizontal, 16)
            .padding(.top, topClearance + 5)
            .padding(.bottom, 9)
            .background(Color.black)
            .clipShape(NotchShape(topRadius: 0, bottomRadius: 13))
            .fixedSize()
            .padding(.horizontal, 10) // shadow room
            .padding(.bottom, 12)
            .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
    }
}
