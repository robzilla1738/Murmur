import AppKit
import SwiftUI

/// Presents the first-run onboarding window and remembers completion.
@MainActor
final class OnboardingController {
    private let appState: AppState
    private var window: NSWindow?

    private let completionKey = "didCompleteOnboarding"

    init(appState: AppState) {
        self.appState = appState
    }

    /// Show onboarding on first launch, or whenever required permissions are missing.
    func showIfNeeded() {
        let completed = UserDefaults.standard.bool(forKey: completionKey)
        if !completed || !appState.permissions.allGranted {
            show()
        }
    }

    func show() {
        appState.permissions.refresh()

        if let window {
            AppActivation.beginWindowSession()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let view = OnboardingView(permissions: appState.permissions) { [weak self] in
            self?.finish()
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 540),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: view.environment(appState))
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window

        AppActivation.beginWindowSession()
        window.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: completionKey)
        window?.close()
    }
}
