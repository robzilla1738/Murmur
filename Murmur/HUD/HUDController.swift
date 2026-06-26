import AppKit
import SwiftUI
import MurmurKit

/// A non-activating floating panel that never steals focus from the app being
/// dictated into (so synthesized ⌘V lands there). Hosts SwiftUI HUD content.
final class FloatingHUDPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Shows/positions the recording HUD in response to `DictationController` state,
/// picking the notch or pill surface per settings + display.
@MainActor
final class HUDController {
    private let controller: DictationController
    private let settings: AppSettings
    private let panel = FloatingHUDPanel()
    private var hideTask: Task<Void, Never>?

    init(controller: DictationController, settings: AppSettings) {
        self.controller = controller
        self.settings = settings
        observeState()
    }

    // MARK: Observation

    private func observeState() {
        withObservationTracking {
            _ = controller.state
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.handleStateChange()
                self?.observeState()
            }
        }
    }

    private func handleStateChange() {
        if controller.state.isActive {
            present()
        } else {
            scheduleHide()
        }
    }

    // MARK: Presentation

    private func present() {
        hideTask?.cancel()
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let style = resolvedStyle(for: screen)
        let host = NSHostingView(rootView: rootView(style: style, screen: screen))
        host.sizingOptions = [.preferredContentSize]
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize

        panel.setContentSize(size)
        panel.contentView = host
        position(panel, style: style, on: screen, size: size)
        panel.orderFrontRegardless()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            self?.panel.orderOut(nil)
        }
    }

    @ViewBuilder
    private func rootView(style: HUDStyle, screen: NSScreen) -> some View {
        switch style {
        case .notch:
            NotchHUDView(controller: controller, topInset: screen.safeAreaInsets.top)
        case .pill, .auto:
            FlowBarView(controller: controller)
        }
    }

    private func position(_ panel: NSPanel, style: HUDStyle, on screen: NSScreen, size: NSSize) {
        switch style {
        case .notch:
            // Flush with the top hardware edge, horizontally centered.
            let x = screen.frame.midX - size.width / 2
            let y = screen.frame.maxY - size.height
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        case .pill, .auto:
            // Lower-center, above the Dock.
            let x = screen.visibleFrame.midX - size.width / 2
            let y = screen.visibleFrame.minY + 96
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    private func resolvedStyle(for screen: NSScreen) -> HUDStyle {
        switch settings.hudStyle {
        case .pill: return .pill
        case .notch: return .notch
        case .auto: return screen.safeAreaInsets.top > 0 ? .notch : .pill
        }
    }
}
