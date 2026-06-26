import SwiftUI
import KeyboardShortcuts
import MurmurKit

struct ShortcutsPane: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings
        Form {
            Section("Push to talk") {
                Picker("Hold key", selection: $settings.pushToTalkKey) {
                    ForEach(PushToTalkKey.allCases) { Text($0.displayName).tag($0) }
                }
                Text("Hold this key to record, release to transcribe and insert. Modifier-only keys need Accessibility + Input Monitoring access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Hands-free") {
                LabeledContent("Toggle dictation") {
                    KeyboardShortcuts.Recorder(for: .toggleDictation)
                }
                LabeledContent("Cancel dictation") {
                    KeyboardShortcuts.Recorder(for: .cancelDictation)
                }
            }

            Section("Command Mode") {
                LabeledContent("Edit selection by voice") {
                    KeyboardShortcuts.Recorder(for: .commandMode)
                }
                Text("Select text, press this, speak an instruction (e.g. \"make this formal\"), and press again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Scratchpad") {
                LabeledContent("Open scratchpad") {
                    KeyboardShortcuts.Recorder(for: .openScratchpad)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Shortcuts")
    }
}
