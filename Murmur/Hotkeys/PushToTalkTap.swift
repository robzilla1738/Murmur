import AppKit
import MurmurKit

/// Detects hold/release of a single modifier key (Fn, Right ⌘, …) for
/// push-to-talk, using a `CGEventTap` on `flagsChanged`.
///
/// Why a tap and not KeyboardShortcuts / Carbon: those fire on a non-modifier
/// key + modifiers and can't represent "hold Fn alone". Only the raw
/// modifier-flag stream gives press *and* release of a modifier-only key.
///
/// Requires Accessibility + Input Monitoring. `tapCreate` returns nil until
/// granted — surfaced via `PushToTalkError.permissionRequired`.
@MainActor
final class PushToTalkTap {
    enum PushToTalkError: Error { case permissionRequired, tapCreationFailed }

    var onBegin: (@MainActor () -> Void)?
    var onEnd: (@MainActor () -> Void)?

    private var key: PushToTalkKey
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isKeyDown = false

    init(key: PushToTalkKey) {
        self.key = key
    }

    var isRunning: Bool { tap != nil }

    func start() throws {
        guard tap == nil else { return }

        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: pushToTalkEventCallback,
            userInfo: userInfo
        ) else {
            throw PushToTalkError.permissionRequired
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        Log.hotkey.info("Push-to-talk tap started for \(self.key.rawValue, privacy: .public)")
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        if isKeyDown { isKeyDown = false; onEnd?() }
    }

    func updateKey(_ newKey: PushToTalkKey) {
        guard newKey != key else { return }
        let wasRunning = isRunning
        stop()
        key = newKey
        if wasRunning { try? start() }
    }

    /// Re-enable after the system disables the tap (slow callback / user input).
    fileprivate func reenable() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.hotkey.warning("Push-to-talk tap re-enabled after system disable")
    }

    fileprivate func handle(flags: CGEventFlags, keyCode: Int64) {
        let down: Bool
        switch key {
        case .fn:
            down = flags.contains(.maskSecondaryFn)
        case .rightOption:
            guard keyCode == 61 else { return }
            down = flags.contains(.maskAlternate)
        case .rightCommand:
            guard keyCode == 54 else { return }
            down = flags.contains(.maskCommand)
        case .rightControl:
            guard keyCode == 62 else { return }
            down = flags.contains(.maskControl)
        case .leftControl:
            guard keyCode == 59 else { return }
            down = flags.contains(.maskControl)
        }

        guard down != isKeyDown else { return }
        isKeyDown = down
        if down { onBegin?() } else { onEnd?() }
    }
}

/// C callback for the event tap. Runs on the main run loop; bounces into the
/// actor-isolated handler. Always returns the event unmodified (listen-only).
private func pushToTalkEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<PushToTalkTap>.fromOpaque(userInfo).takeUnretainedValue()

    switch type {
    case .flagsChanged:
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        MainActor.assumeIsolated { tap.handle(flags: flags, keyCode: keyCode) }
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        MainActor.assumeIsolated { tap.reenable() }
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}
