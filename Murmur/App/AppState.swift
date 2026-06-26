import Foundation
import MurmurKit
import Observation
import SwiftData

/// Composition root shared between the AppKit shell and SwiftUI views. Owns the
/// long-lived services (settings, keychain, permissions, engine registry) and a
/// reference to the live `DictationController` for status/Settings UI.
@MainActor
@Observable
final class AppState {
    let version: String
    let settings: AppSettings
    let keychain: KeychainStore
    let permissions: PermissionsManager
    let registry: EngineRegistry
    let serverDetector = LocalServerDetector()
    let modelContainer: ModelContainer

    /// Set by `AppDelegate` once the pipeline is built.
    var dictation: DictationController?

    init() {
        self.version = Bundle.main.shortVersion
        let settings = AppSettings()
        let keychain = KeychainStore()
        self.settings = settings
        self.keychain = keychain
        self.permissions = PermissionsManager()
        self.registry = EngineRegistry(settings: settings, keychain: keychain)
        do {
            self.modelContainer = try ModelContainer(for: HistoryItem.self, DictionaryEntry.self, Snippet.self)
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }
}

extension Bundle {
    /// `CFBundleShortVersionString`, falling back to "0.0.0" in non-bundle contexts.
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }
}
