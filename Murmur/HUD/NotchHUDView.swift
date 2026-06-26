import SwiftUI

/// The notch-anchored recording HUD — a black shell shaped like the camera
/// housing that hangs from the top of the display and holds the dictation
/// status. Used on notch displays (or when the user forces the notch style).
struct NotchHUDView: View {
    var controller: DictationController
    /// Safe-area top inset (the physical notch height) so content clears the camera.
    var topInset: CGFloat

    var body: some View {
        HUDContent(controller: controller, onDark: true)
            .padding(.horizontal, 20)
            .padding(.top, max(topInset, 10) - 2)
            .padding(.bottom, 12)
            .background(Color.black)
            .clipShape(NotchShape(topRadius: 10, bottomRadius: 22))
            .fixedSize()
            .padding(.horizontal, 16) // room for the top corner flares + shadow
            .padding(.bottom, 14)
            .shadow(color: .black.opacity(0.55), radius: 8, y: 3)
    }
}
