import SwiftUI

struct AboutPane: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(.secondary)
            Text("Murmur")
                .font(.largeTitle.weight(.semibold))
            Text("Version \(appState.version)")
                .foregroundStyle(.secondary)
            Text("Local-first AI voice dictation for macOS.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Link("View on GitHub", destination: URL(string: "https://github.com/robzilla1738/whisper-local")!)
                .padding(.top, 4)

            Spacer()

            Text("Open source · MIT License")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("About")
    }
}
