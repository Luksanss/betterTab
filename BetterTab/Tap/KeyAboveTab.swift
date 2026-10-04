import Carbon.HIToolbox

/// The key above Tab, which opens the window switcher with ⌘: § on ISO keyboards, ` on ANSI ones.
/// Each key press counts by the keyboard it came from, so on an ISO keyboard, where ` sits left of
/// Z, ⌘` stays macOS's, even with an ANSI keyboard plugged in too.
nonisolated struct KeyAboveTab: Sendable {
    /// Keyboard types whose physical layout is ANSI. A keyboard type fits in a byte.
    private let ansiTypes: Set<Int64>

    /// `KBGetLayoutType` isn't thread-safe, so every type is looked up here, once, on main. An
    /// unknown type comes back as neither ANSI nor ISO, so ` stays macOS's on it.
    @MainActor init() {
        ansiTypes = Set((0...255).filter {
            KBGetLayoutType(Int16($0)) == PhysicalKeyboardLayoutType(kKeyboardANSI)
        }.map(Int64.init))
    }

    /// Tap thread. `keyboardType` is the event's `keyboardEventKeyboardType`.
    func matches(keycode: Int64, keyboardType: Int64) -> Bool {
        keycode == TapKey.section || (keycode == TapKey.grave && ansiTypes.contains(keyboardType))
    }
}
