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

    /// Arm the push-to-talk event tap, retrying until it succeeds. `tapCreate`
    /// returns nil until Accessibility/Input Monitoring is granted, and a
    /// menu-bar agent often never "reactivates" after the user flips the toggle
    /// in System Settings — so we poll for a short while instead of relying only
    /// on `didBecomeActive`.
    private func armPushToTalk() {
        guard let ptt = pushToTalk else { return }
        if !ptt.isRunning {
            do {
                try ptt.start()
            } catch {
                Log.hotkey.error("Push-to-talk tap could NOT arm: \(error, privacy: .public) — grant Accessibility + Input Monitoring to the modifier key. (⌃⌥D works without these.)")
            }
        }
        if ptt.isRunning {
            rearmTimer?.invalidate()
            rearmTimer = nil
            return
        }
        guard rearmTimer == nil else { return }
        rearmTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let ptt = self.pushToTalk else { return }
                if !ptt.isRunning { try? ptt.start() }
                if ptt.isRunning {
                    self.rearmTimer?.invalidate()
                    self.rearmTimer = nil
                    Log.hotkey.info("Push-to-talk armed after permission grant")
                }
            }
        }
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
