import AppKit
import ApplicationServices

/// Inserts text into whatever app currently has keyboard focus, by putting the
/// text on the pasteboard and synthesizing ⌘V, then restoring the previous
/// pasteboard contents.
///
/// This clipboard-paste approach is far more reliable across apps (Electron, web
/// editors) than writing the AX `kAXSelectedText` attribute, which many apps
/// silently ignore. Requires Accessibility permission and no App Sandbox.
@MainActor
final class TextInsertionService {
    private let pasteboard = NSPasteboard.general

    /// How long to wait after pasting before restoring the old clipboard, giving
    /// the target app time to read the pasteboard.
    private let restoreDelay: Duration = .milliseconds(250)

    /// Whether we're allowed to synthesize keystrokes. Without Accessibility the
    /// synthetic ⌘V is a silent no-op, so the caller must check this and fall back.
    var isTrusted: Bool { AXIsProcessTrusted() }

    /// Put text on the clipboard without pasting or restoring — the fallback when
    /// Accessibility isn't granted, so the user can paste it manually with ⌘V.
    func copyToClipboard(_ text: String) {
        guard !text.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func insert(_ text: String) {
        guard !text.isEmpty else { return }

        let snapshot = currentSnapshot()
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        synthesizePaste()

        Task { [restoreDelay] in
            try? await Task.sleep(for: restoreDelay)
            restore(snapshot)
        }
    }

    /// Copy the current selection to the pasteboard (⌘C) and return it, restoring
    /// the previous clipboard afterward. Used by Command Mode / Transforms.
    func readSelectionViaCopy() async -> String? {
        let snapshot = currentSnapshot()
        pasteboard.clearContents()
        let changeCountBefore = pasteboard.changeCount

        synthesizeCopy()
        try? await Task.sleep(for: .milliseconds(120))

        let copied = pasteboard.changeCount != changeCountBefore
            ? pasteboard.string(forType: .string)
            : nil
        restore(snapshot)
        return copied?.isEmpty == false ? copied : nil
    }

    // MARK: - Pasteboard snapshot / restore

    private struct Snapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    private func currentSnapshot() -> Snapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item -> [NSPasteboard.PasteboardType: Data] in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return dict
        }
        return Snapshot(items: items)
    }

    private func restore(_ snapshot: Snapshot) {
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return }
        let items = snapshot.items.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(items)
    }

    // MARK: - Synthetic key events

    private func synthesizePaste() { synthesize(keyCode: 0x09) } // V
    private func synthesizeCopy() { synthesize(keyCode: 0x08) }  // C

    private func synthesize(keyCode: CGKeyCode) {
        // A *private* event source: the synthetic ⌘V reports only the Command flag
        // and ignores any physical modifier still held (e.g. the push-to-talk key
        // or ⌃⌥ from the toggle combo), which would otherwise corrupt the keystroke.
        let source = CGEventSource(stateID: .privateState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        // A brief gap between down and up — some apps drop a zero-duration ⌘V.
        usleep(1500)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
