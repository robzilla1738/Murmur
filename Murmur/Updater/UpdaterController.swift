import Sparkle

/// Wraps Sparkle's standard updater for Developer ID auto-updates. The appcast
/// feed (`SUFeedURL`) and signing key (`SUPublicEDKey`) are configured in
/// Info.plist — see docs/SPARKLE_SETUP.md.
@MainActor
final class UpdaterController {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
