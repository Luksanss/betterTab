import CoreGraphics
import Dispatch
import os

/// Synthetic events. Each carries `marker` in `.eventSourceUserData`, and our tap passes marked
/// events through untouched.
nonisolated enum Synthetic {
    static let marker: Int64 = 0x4254_4558  // "BTEX"

    /// Device-dependent left/right ⌘ bits (NX_DEVICELCMDKEYMASK, NX_DEVICERCMDKEYMASK).
    private static let leftCommandBit: UInt64 = 0x08
    private static let rightCommandBit: UInt64 = 0x10
    private static let deviceCommandBits: UInt64 = leftCommandBit | rightCommandBit

    static func isOurs(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == marker
    }

    /// `flags` with ⌘ held the way the Dock believes it is: the ⌘ bit, plus the device bit of the
    /// ⌘ key `keycode` unless a real ⌘ key already set one. Any thread; the tap uses it for Tab.
    static func withCommand(_ flags: CGEventFlags, keycode: Int64) -> CGEventFlags {
        let device = flags.rawValue & deviceCommandBits != 0 ? 0
            : keycode == KeyCode.rightCommand ? rightCommandBit : leftCommandBit
        return flags.union(.maskCommand).union(CGEventFlags(rawValue: device))
    }

    /// The modifiers that are physically down right now, minus ⌘. A real ⌘ release has these.
    private static func physicalFlagsWithoutCommand() -> CGEventFlags {
        let hid = CGEventSource.flagsState(.hidSystemState).rawValue
        let cleared = hid & ~(CGEventFlags.maskCommand.rawValue | deviceCommandBits)
        return CGEventFlags(rawValue: cleared).union(.maskNonCoalesced)
    }

    /// Only `HoldMachine.releaseCommandIfOwed` may call this; that is what makes it idempotent.
    /// `keycode` is the ⌘ key whose release was swallowed (55 left, 54 right).
    static func postCommandRelease(reason: String, keycode: Int64) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(
            keyboardEventSource: source, virtualKey: CGKeyCode(keycode), keyDown: false)
        else {
            Log.post.error("POST ⌘ release FAILED: CGEvent init returned nil (reason: \(reason, privacy: .public))")
            return
        }
        let createdType = event.type.rawValue
        if event.type != .flagsChanged { event.type = .flagsChanged }
        event.flags = physicalFlagsWithoutCommand()
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.post(tap: .cghidEventTap)
        Log.post.notice("""
            POST ⌘ release (reason: \(reason, privacy: .public)): type=\(event.type.rawValue, privacy: .public) \
            (flagsChanged is 12; initializer made \(createdType, privacy: .public)) \
            keycode=\(event.getIntegerValueField(.keyboardEventKeycode), privacy: .public) \
            (\(keycode == KeyCode.rightCommand ? "right" : "left", privacy: .public) ⌘) \
            flags=\(hex(event.flags.rawValue), privacy: .public) posted to the HID tap
            """)

        // Evidence for test 0f: does the system still think ⌘ is down after our release?
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .milliseconds(200)) {
            let session = CGEventSource.flagsState(.combinedSessionState)
            let hid = CGEventSource.flagsState(.hidSystemState)
            Log.post.notice("""
                POST check 200 ms after the ⌘ release: \
                session ⌘ down=\(session.contains(.maskCommand), privacy: .public) (\(hex(session.rawValue), privacy: .public)), \
                HID ⌘ down=\(hid.contains(.maskCommand), privacy: .public) (\(hex(hid.rawValue), privacy: .public))
                """)
        }
    }

    /// Esc down and up with ⌘ set, because the Dock still believes ⌘ is held.
    static func postEscapeWithCommand(reason: String, commandKeycode: Int64) {
        let source = CGEventSource(stateID: .hidSystemState)
        let flags = withCommand(physicalFlagsWithoutCommand(), keycode: commandKeycode)
        for keyDown in [true, false] {
            guard let event = CGEvent(
                keyboardEventSource: source, virtualKey: CGKeyCode(KeyCode.escape), keyDown: keyDown)
            else {
                Log.post.error("POST Esc FAILED: CGEvent init returned nil (reason: \(reason, privacy: .public))")
                return
            }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            event.post(tap: .cghidEventTap)
            Log.post.notice("""
                POST Esc \(keyDown ? "keyDown" : "keyUp", privacy: .public) with ⌘ (reason: \(reason, privacy: .public)): \
                type=\(event.type.rawValue, privacy: .public) flags=\(hex(event.flags.rawValue), privacy: .public) \
                posted to the HID tap
                """)
        }
    }
}
