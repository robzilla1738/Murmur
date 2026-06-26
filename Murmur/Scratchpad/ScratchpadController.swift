import AppKit
import SwiftUI

/// Owns the Scratchpad window. Activates the app + focuses the editor so
/// dictation (paste-based insertion) lands in the scratchpad.
@MainActor
final class ScratchpadController {
    private var window: NSWindow?

    func toggle() {
        if let window, window.isVisible {
            window.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 340),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Scratchpad"
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.contentView = NSHostingView(rootView: ScratchpadView())
            window.center()
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("MurmurScratchpad")
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
