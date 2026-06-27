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
    private var settingsWindow: SettingsWindowController?
    private var rearmTimer: Timer?
    private var rearmAttempts = 0
    private let maxRearmAttempts = 15   // ~30s of 2s polls, then wait for reactivation
    /// True only when the tap was created WHILE Input Monitoring was granted, i.e.
    /// it actually delivers events globally (not just while Murmur is frontmost).
    private var armedWithMonitoring = false
    private var didPromptForInputMonitoring = false

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
        // The modifier key is the hold-to-talk path (push-to-talk) or a toggle in
        // hands-free mode — see InputRouting.
        ptt.onBegin = { [weak controller, weak self] in
            guard let self, let controller else { return }
            Log.hotkey.info("Modifier key DOWN (\(self.appState.settings.pushToTalkKey.rawValue, privacy: .public))")
            self.apply(InputRouting.onDown(.modifier, mode: self.appState.settings.activationMode), to: controller)
        }
        ptt.onEnd = { [weak controller, weak self] in
            guard let self, let controller else { return }
            Log.hotkey.info("Modifier key UP")
            self.apply(InputRouting.onUp(.modifier, mode: self.appState.settings.activationMode), to: controller)
        }
        pushToTalk = ptt
        armPushToTalk() // keeps retrying until Accessibility/Input Monitoring are granted

        let hotkeys = HotkeyManager()
        // The ⌃⌥D combo is a discrete tap — it always toggles (tap to start, tap to
        // stop), independent of activation mode, so it works without Input Monitoring.
        hotkeys.onDictationDown = { [weak controller, weak self] in
            guard let self, let controller else { return }
            self.apply(InputRouting.onDown(.combo, mode: self.appState.settings.activationMode), to: controller)
        }
        hotkeys.onDictationUp = { [weak controller, weak self] in
            guard let self, let controller else { return }
            self.apply(InputRouting.onUp(.combo, mode: self.appState.settings.activationMode), to: controller)
        }
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

        settingsWindow = SettingsWindowController(appState: appState)

        statusItemController = StatusItemController(
            appState: appState,
            showUpdatesItem: updater.isConfigured,
            onShowOnboarding: { [weak onboarding] in onboarding?.show() },
            onCheckForUpdates: { [weak updater] in updater?.checkForUpdates() },
            onOpenScratchpad: { [weak self] in self?.scratchpad.toggle() },
            onOpenSettings: { [weak self] in self?.presentSettings() }
        )

        observePushToTalkKey()
        observeReactivation()
        observeWindowClose()

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-hudDemo") {
            controller.startDemo()
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-openSettings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.presentSettings() }
            return
        }
        #endif

        onboarding.showIfNeeded()
    }

    /// Open the self-managed Settings window (the SwiftUI Settings scene +
    /// showSettingsWindow: don't open for a menu-bar agent).
    func presentSettings() {
        settingsWindow?.show()
    }

    /// Apply a routed dictation action to the controller.
    private func apply(_ action: DictationAction, to controller: DictationController) {
        switch action {
        case .begin: Log.hotkey.info("→ begin"); controller.begin()
        case .finish: Log.hotkey.info("→ finish"); controller.finish()
        case .toggle: Log.hotkey.info("→ toggle"); controller.toggle()
        case .ignore: break
        }
    }

    /// Arm the Right ⌘ (modifier) push-to-talk tap.
    ///
    /// Critical macOS subtlety: `CGEvent.tapCreate` SUCCEEDS even without Input
    /// Monitoring — but the resulting tap then only sees events while Murmur is
    /// frontmost (it never fires for the global hold-to-talk use case). So we gate
    /// "armed" on the Input Monitoring permission itself, and because TCC is
    /// evaluated at tap-creation time, we RECREATE the tap once the permission is
    /// granted. The ⌃⌥D combo (a Carbon hotkey) needs none of this and works
    /// regardless.
    private func armPushToTalk() {
        guard let ptt = pushToTalk else { return }
        appState.permissions.refresh()
        let perms = appState.permissions
        Log.hotkey.info("Permissions — Accessibility=\(perms.accessibility.isGranted), InputMonitoring=\(perms.inputMonitoring.isGranted)")

        if perms.inputMonitoring.isGranted {
            if !armedWithMonitoring {
                // Recreate so the tap is made WITH the permission → global delivery.
                ptt.stop()
                do {
                    try ptt.start()
                    armedWithMonitoring = true
                    Log.hotkey.info("Push-to-talk armed (Input Monitoring granted, global)")
                } catch {
                    Log.hotkey.error("Push-to-talk tap could NOT arm: \(error, privacy: .public)")
                }
            }
        } else {
            // Without Input Monitoring the tap would only fire while Murmur is
            // frontmost — tear it down and guide the user to enable it.
            ptt.stop()
            armedWithMonitoring = false
            promptForInputMonitoringIfNeeded()
        }

        if armedWithMonitoring {
            rearmTimer?.invalidate()
            rearmTimer = nil
        } else {
            startRearmPolling()
        }
    }

    /// Poll briefly for the Input Monitoring grant (covers the user enabling it
    /// while Murmur is backgrounded, when `didBecomeActive` may not fire), then
    /// give up until the next reactivation so we don't poll forever.
    private func startRearmPolling() {
        guard rearmTimer == nil else { return }
        rearmAttempts = 0
        rearmTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.rearmAttempts += 1
                self.armPushToTalk()   // re-checks permission; arms + invalidates when granted
                if !self.armedWithMonitoring, self.rearmAttempts >= self.maxRearmAttempts {
                    self.rearmTimer?.invalidate()
                    self.rearmTimer = nil
                    Log.hotkey.info("Stopped polling for Input Monitoring; will retry on reactivation")
                }
            }
        }
    }

    /// Show the Input Monitoring prompt once so the user can enable the Right ⌘
    /// hold key (the system only surfaces it while the status is undetermined).
    private func promptForInputMonitoringIfNeeded() {
        guard !didPromptForInputMonitoring else { return }
        didPromptForInputMonitoring = true
        appState.permissions.requestInputMonitoring()
        Log.hotkey.info("Requested Input Monitoring for the Right ⌘ hold key")
    }

    /// Revert to a Dock-less agent once the last ordinary window closes.
    private func observeWindowClose() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { AppActivation.endWindowSessionSoon() }
        }
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
                self.armPushToTalk()
            }
        }
    }
}
