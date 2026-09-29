import CoreGraphics
import os

/// Synthetic events. Each carries `marker` in `.eventSourceUserData`, and our tap passes marked
/// events through untouched. Ported from the test 0 harness (Experiment/Synthetic.swift).
nonisolated enum SyntheticKeys {
    static let marker: Int64 = 0x4254_4142  // "BTAB"

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
            : keycode == TapKey.rightCommand ? rightCommandBit : leftCommandBit
        return flags.union(.maskCommand).union(CGEventFlags(rawValue: device))
    }

    /// The modifiers that are physically down right now, minus ⌘. A real ⌘ release has these.
    private static func physicalFlagsWithoutCommand() -> CGEventFlags {
        let hid = CGEventSource.flagsState(.hidSystemState).rawValue
        let cleared = hid & ~(CGEventFlags.maskCommand.rawValue | deviceCommandBits)
        return CGEventFlags(rawValue: cleared).union(.maskNonCoalesced)
    }

    /// Only `TapMachine` may call this, for a plan that found the release still owed; that is what
    /// makes each exit post exactly one. `keycode` is the ⌘ key whose release was swallowed.
    static func postCommandRelease(keycode: Int64) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keycode), keyDown: false) else {
            TapLog.logger.error("Posting the ⌘ release failed: CGEvent returned nil")
            return
        }
        if event.type != .flagsChanged { event.type = .flagsChanged }
        event.flags = physicalFlagsWithoutCommand()
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.post(tap: .cghidEventTap)
    }

    /// Esc down and up with ⌘ set, because the Dock still believes ⌘ is held.
    static func postEscapeWithCommand(commandKeycode: Int64) {
        let source = CGEventSource(stateID: .hidSystemState)
        let flags = withCommand(physicalFlagsWithoutCommand(), keycode: commandKeycode)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(TapKey.escape), keyDown: keyDown) else {
                TapLog.logger.error("Posting Esc failed: CGEvent returned nil")
                return
            }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            event.post(tap: .cghidEventTap)
        }
    }
}
