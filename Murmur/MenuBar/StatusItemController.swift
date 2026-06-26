import AppKit

/// Manages Murmur's menu-bar presence. The icon reflects dictation state; the
/// menu offers dictation toggle, settings, permission setup, and quit.
@MainActor
final class StatusItemController {
    private let appState: AppState
    private let onShowOnboarding: () -> Void
    private let onCheckForUpdates: () -> Void
    private let onOpenScratchpad: () -> Void
    private let onOpenSettings: () -> Void
    private let showUpdatesItem: Bool
    private let statusItem: NSStatusItem

    init(
        appState: AppState,
        showUpdatesItem: Bool,
        onShowOnboarding: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void,
        onOpenScratchpad: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.appState = appState
        self.showUpdatesItem = showUpdatesItem
        self.onShowOnboarding = onShowOnboarding
        self.onCheckForUpdates = onCheckForUpdates
        self.onOpenScratchpad = onOpenScratchpad
        self.onOpenSettings = onOpenSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton()
        statusItem.menu = makeMenu()
        observeState()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = Self.symbol(for: appState.dictation?.state ?? .idle)
        button.toolTip = "Murmur"
    }

    private func observeState() {
        withObservationTracking {
            _ = appState.dictation?.state
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateIcon()
                self?.observeState()
            }
        }
    }

    private func updateIcon() {
        statusItem.button?.image = Self.symbol(for: appState.dictation?.state ?? .idle)
    }

    private static func symbol(for state: DictationController.State) -> NSImage? {
        let name: String
        switch state {
        case .recording: name = "mic.fill"
        case .transcribing, .polishing, .downloading: name = "waveform.circle"
        case .inserting: name = "checkmark.circle"
        case .error: name = "exclamationmark.triangle"
        case .idle: name = "waveform"
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Murmur")
        image?.isTemplate = true
        return image
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let dictate = NSMenuItem(title: "Start / Stop Dictation", action: #selector(toggleDictation), keyEquivalent: "")
        dictate.target = self
        menu.addItem(dictate)

        let scratchpad = NSMenuItem(title: "Open Scratchpad", action: #selector(openScratchpad), keyEquivalent: "")
        scratchpad.target = self
        menu.addItem(scratchpad)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let permissions = NSMenuItem(title: "Set Up Permissions…", action: #selector(showOnboarding), keyEquivalent: "")
        permissions.target = self
        menu.addItem(permissions)

        if showUpdatesItem {
            let updates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
            updates.target = self
            menu.addItem(updates)
        }

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit Murmur", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func toggleDictation() {
        appState.dictation?.toggle()
    }

    @objc private func openScratchpad() {
        onOpenScratchpad()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func showOnboarding() {
        onShowOnboarding()
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates()
    }
}
