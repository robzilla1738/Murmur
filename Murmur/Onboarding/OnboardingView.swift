import SwiftUI
import MurmurKit

/// First-run permission walkthrough. Monochrome, immersive. Each row deep-links
/// to the right System Settings pane; statuses refresh when the app reactivates.
struct OnboardingView: View {
    var permissions: PermissionsManager
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 12) {
                PermissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Record your voice to transcribe it.",
                    status: permissions.microphone,
                    action: { Task { await permissions.requestMicrophone() } },
                    openSettings: { permissions.openSettings(.microphone) }
                )
                PermissionRow(
                    icon: "accessibility",
                    title: "Accessibility",
                    description: "Insert text into the app you're using.",
                    status: permissions.accessibility,
                    action: { permissions.requestAccessibility() },
                    openSettings: { permissions.openSettings(.accessibility) }
                )
                PermissionRow(
                    icon: "keyboard",
                    title: "Input Monitoring",
                    description: "Detect your hold-to-talk key (Right ⌘) globally.",
                    status: permissions.inputMonitoring,
                    action: { permissions.requestInputMonitoring() },
                    openSettings: { permissions.openSettings(.inputMonitoring) }
                )

                Text("Then hold **Right ⌘** (or press **⌃⌥D**) in any text field and speak. If the key isn't detected after granting, toggle Murmur off and back on in that System Settings list — macOS sometimes keeps a stale entry after an update.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .padding(24)

            Spacer(minLength: 0)

            Button(action: onFinish) {
                Text(permissions.allGranted ? "Start dictating" : "Continue")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(.primary)
            .padding(24)
        }
        .frame(width: 460, height: 600)
        .background(.background)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(.primary)
                .padding(.top, 40)
            Text("Welcome to Murmur")
                .font(.title.weight(.semibold))
            Text("Grant three permissions and you're ready to dictate anywhere.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let status: PermissionStatus
    let action: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .frame(width: 34, height: 34)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            switch status {
            case .granted:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            case .notDetermined:
                Button("Grant", action: action)
            case .denied:
                Button("Open Settings", action: openSettings)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
