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
            detail
        }
        .frame(height: 22)
    }

    @ViewBuilder
    private var icon: some View {
        switch controller.state {
        case .recording:
            Image(systemName: "mic.fill")
                .foregroundStyle(ink)
                .symbolEffect(.pulse, options: .repeating)
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
            Image(systemName: "waveform")
                .foregroundStyle(muted)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch controller.state {
        case .recording:
            WaveformView(levels: controller.levels, tint: ink)
                .frame(width: 130)
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
