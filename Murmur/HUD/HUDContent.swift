import SwiftUI

/// The inner content of the recording HUD, shared by the pill and notch
/// surfaces. Reflects the current `DictationController.State`.
struct HUDContent: View {
    var controller: DictationController
    /// Notch sits on a black shell, so prefer light ink; pill uses primary.
    var onDark: Bool = false

    private var ink: Color { onDark ? .white : Theme.ink }
    private var muted: Color { onDark ? .white.opacity(0.6) : Theme.inkMuted }

    var body: some View {
        HStack(spacing: 10) {
            icon
                .font(.system(size: 13, weight: .semibold))
            detail
        }
        .frame(height: 22)
        // A generous, consistent width so the recording HUD reads as substantial
        // (not a thin sliver) and the surface doesn't jump in size between states.
        .frame(minWidth: 188)
    }

    @ViewBuilder
    private var icon: some View {
        switch controller.state {
        case .recording:
            // Steady — no pulse / color change.
            Image(systemName: "mic.fill")
                .foregroundStyle(ink)
        case .transcribing, .polishing, .downloading:
            ProgressView()
                .controlSize(.small)
                .tint(ink)
        case .inserting:
            Image(systemName: "checkmark")
                .foregroundStyle(ink)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ink)
        case .idle:
            Image(systemName: "mic")
                .foregroundStyle(muted)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch controller.state {
        case .recording:
            WaveformView(levels: controller.levels, barCount: 28, tint: ink)
                .frame(width: 168)
        case .transcribing:
            label("Transcribing…")
        case .polishing:
            label("Polishing…")
        case .downloading(let progress):
            label("Downloading model \(Int(progress * 100))%")
        case .inserting:
            label("Inserted")
        case .error(let message):
            label(message)
                .lineLimit(1)
                .frame(maxWidth: 240)
        case .idle:
            EmptyView()
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(muted)
            .fixedSize(horizontal: true, vertical: false)
    }
}
