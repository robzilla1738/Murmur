import SwiftUI
import MurmurKit

/// A secure field bound to a Keychain-stored API key. Loads on appear, persists
/// on change. Keys never touch UserDefaults.
struct APIKeyField: View {
    let title: String
    let account: String
    let keychain: KeychainStore
    var placeholder: String = "Paste API key"

    @State private var value: String = ""
    @State private var revealed = false

    var body: some View {
        HStack {
            Group {
                if revealed {
                    TextField(placeholder, text: $value)
                } else {
                    SecureField(placeholder, text: $value)
                }
            }
            .textFieldStyle(.roundedBorder)
            .labelsHidden()

            Button {
                revealed.toggle()
            } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .help(revealed ? "Hide" : "Show")
            .accessibilityLabel(revealed ? "Hide API key" : "Show API key")
        }
        .onAppear { value = keychain.value(for: account) ?? "" }
        .onChange(of: value) { _, newValue in
            keychain.set(newValue.isEmpty ? nil : newValue, for: account)
        }
    }
}
