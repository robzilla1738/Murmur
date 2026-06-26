import AppKit
import MurmurKit
import SwiftUI

/// Owns the AppKit-level lifecycle: builds the dictation pipeline, the global
/// hotkeys, the floating HUD, and the menu-bar status item.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    private var dictation: DictationController?
    private var pushToTalk: PushToTalkTap?
    private var hotkeys: HotkeyManager?
    private var hud: HUDController?
    private var statusItemController: StatusItemController?
    private var onboarding: OnboardingController?
    private var updater: UpdaterController?
    private let scratchpad = ScratchpadController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar agent: no Dock icon, no window at launch.
        NSApp.setActivationPolicy(.accessory)

        let controller = DictationController(
            settings: appState.settings,
            registry: appState.registry,
            insertion: TextInsertionService(),
            accessibility: AccessibilityReader()
        )
        controller.historyContext = appState.modelContainer.mainContext
        dictation = controller
        appState.dictation = controller

        MurmurIntentBridge.dictation = controller
        MurmurIntentBridge.scratchpad = scratchpad

        hud = HUDController(controller: controller, settings: appState.settings)

        let ptt = PushToTalkTap(key: appState.settings.pushToTalkKey)
        ptt.onBegin = { [weak controller] in controller?.begin() }
        ptt.onEnd = { [weak controller] in controller?.finish() }
        pushToTalk = ptt
        try? ptt.start() // no-op until Accessibility/Input Monitoring are granted

        let hotkeys = HotkeyManager()
        hotkeys.onToggle = { [weak controller] in controller?.toggle() }
        hotkeys.onCancel = { [weak controller] in controller?.cancel() }
        hotkeys.onCommandMode = { [weak controller] in controller?.toggleCommand() }
        hotkeys.onTransform = { [weak controller] index in controller?.runTransform(index) }
        hotkeys.onScratchpad = { [weak self] in self?.scratchpad.toggle() }
        hotkeys.register()
        self.hotkeys = hotkeys

        let onboarding = OnboardingController(appState: appState)
        self.onboarding = onboarding

        let updater = UpdaterController()
        self.updater = updater

        statusItemController = StatusItemController(
            appState: appState,
            onShowOnboarding: { [weak onboarding] in onboarding?.show() },
            onCheckForUpdates: { [weak updater] in updater?.checkForUpdates() },
            onOpenScratchpad: { [weak self] in self?.scratchpad.toggle() }
        )

        observePushToTalkKey()
        observeReactivation()

        onboarding.showIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: Observation

    /// Keep the event tap's key in sync with Settings.
    private func observePushToTalkKey() {
        withObservationTracking {
            _ = appState.settings.pushToTalkKey
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.pushToTalk?.updateKey(self.appState.settings.pushToTalkKey)
                self.observePushToTalkKey()
            }
        }
    }

    /// Re-check permissions and (re)start the tap when the app reactivates —
    /// TCC grants can't be observed live and often need the tap re-created.
    private func observeReactivation() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.appState.permissions.refresh()
                if let ptt = self.pushToTalk, !ptt.isRunning {
                    try? ptt.start()
                }
            }
        }
    }
}
