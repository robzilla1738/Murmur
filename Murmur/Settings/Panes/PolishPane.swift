import SwiftUI
import MurmurKit

struct PolishPane: View {
    @Environment(AppState.self) private var appState

    @State private var models: [LLMModel] = []
    @State private var loadingModels = false
    @State private var loadError: String?

    var body: some View {
        @Bindable var settings = appState.settings
        let provider = settings.llmProviderID

        Form {
            Section {
                Toggle("Clean up transcripts with AI (Polish)", isOn: $settings.polishEnabled)
                Text("Removes filler words, fixes punctuation, and lightly formats — without changing meaning.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if settings.polishEnabled {
                Section("Provider") {
                    Picker("Provider", selection: $settings.llmProviderID) {
                        ForEach(LLMProviderID.allCases) { Text($0.displayName).tag($0) }
                    }
                    if provider.isLocal {
                        TextField("Server URL", text: baseURLBinding(for: provider))
                            .textFieldStyle(.roundedBorder)
                    } else if provider.requiresAPIKey {
                        APIKeyField(title: provider.displayName, account: provider.keychainAccount, keychain: appState.keychain)
                    }
                }

                Section("Model") {
                    HStack {
                        Picker("Model", selection: modelBinding(for: provider)) {
                            ForEach(models) { Text($0.displayName).tag($0.id) }
                            if models.isEmpty, let selected = settings.selectedLLMModelID(for: provider) {
                                Text(selected).tag(selected)
                            }
                        }
                        Button {
                            loadModels(for: provider)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Refresh model list")
                    }
                    if loadingModels {
                        ProgressView().controlSize(.small)
                    }
                    if let loadError {
                        Text(loadError).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("AI Polish")
        .task(id: provider) { loadModels(for: provider) }
    }

    private func baseURLBinding(for provider: LLMProviderID) -> Binding<String> {
        switch provider {
        case .ollama:
            return Binding(get: { appState.settings.ollamaBaseURL }, set: { appState.settings.ollamaBaseURL = $0 })
        default:
            return Binding(get: { appState.settings.lmStudioBaseURL }, set: { appState.settings.lmStudioBaseURL = $0 })
        }
    }

    private func modelBinding(for provider: LLMProviderID) -> Binding<String> {
        Binding(
            get: { appState.settings.selectedLLMModelID(for: provider) ?? "" },
            set: { appState.settings.setSelectedLLMModelID($0, for: provider) }
        )
    }

    private func loadModels(for provider: LLMProviderID) {
        loadingModels = true
        loadError = nil
        Task {
            do {
                let fetched = try await appState.registry.makeLLMProvider().availableModels()
                models = fetched
                if fetched.isEmpty, provider.isLocal {
                    loadError = "No models found. Is \(provider.displayName) running?"
                }
            } catch {
                models = []
                loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            loadingModels = false
        }
    }
}
