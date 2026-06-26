import SwiftUI

/// The silhouette of a MacBook notch: flat top flush with the display edge,
/// small outward curves at the top corners, and larger rounded bottom corners,
/// so the HUD reads as "attached to the hardware". Radii are animatable so the
/// shape can grow on record.
struct NotchShape: Shape {
    var topRadius: CGFloat = 8
    var bottomRadius: CGFloat = 16

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tr = min(topRadius, rect.width / 2)
        let br = min(bottomRadius, rect.width / 2)

        // Top-left outward flare into the menu bar.
        path.move(to: CGPoint(x: rect.minX - tr, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + tr),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        // Left edge down to bottom-left rounded corner.
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - br))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + br, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        // Bottom edge to bottom-right rounded corner.
        path.addLine(to: CGPoint(x: rect.maxX - br, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - br),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        // Right edge up to top-right outward flare.
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + tr))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX + tr, y: rect.minY),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
