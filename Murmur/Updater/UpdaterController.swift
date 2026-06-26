import Sparkle

/// Wraps Sparkle's updater for Developer ID auto-updates. The updater is only
/// created/started once Sparkle is actually configured (a non-empty
/// `SUPublicEDKey` in Info.plist) — otherwise starting it throws a "failed to
/// start" alert on every launch. See docs/SPARKLE_SETUP.md.
@MainActor
final class UpdaterController {
    private var controller: SPUStandardUpdaterController?

    /// True once a signing key is present, i.e. Sparkle is set up for release.
    var isConfigured: Bool {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        return !(key ?? "").isEmpty
    }

    func checkForUpdates() {
        guard isConfigured else { return }
        if controller == nil {
            controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        }
        controller?.checkForUpdates(nil)
    }
}
