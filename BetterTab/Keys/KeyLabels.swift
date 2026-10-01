import Carbon.HIToolbox
import Foundation

/// The physical keys that pick tiles in the ⌘§ switcher, and what the current keyboard layout
/// prints on them.
enum KeyLabels {
    /// A S D F G H J K L by position (`kVK_ANSI_A` … `kVK_ANSI_L`). Positions, not characters: on
    /// AZERTY the first of these still has key code 0, but it prints Q.
    static let keyCodes: [UInt16] = [
        UInt16(kVK_ANSI_A), UInt16(kVK_ANSI_S), UInt16(kVK_ANSI_D),
        UInt16(kVK_ANSI_F), UInt16(kVK_ANSI_G), UInt16(kVK_ANSI_H),
        UInt16(kVK_ANSI_J), UInt16(kVK_ANSI_K), UInt16(kVK_ANSI_L),
    ]

    static let qwerty = ["A", "S", "D", "F", "G", "H", "J", "K", "L"]

    /// One label per entry in `keyCodes`, uppercased, for the layout in use right now. Cheap, so
    /// it's read each time the switcher opens rather than kept up to date with an observer.
    static func current() -> [String] {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return qwerty }
        let layout = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data

        return layout.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return qwerty }
            let keyboard = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            return zip(keyCodes, qwerty).map { keyCode, fallback in
                label(for: keyCode, in: keyboard) ?? fallback
            }
        }
    }

    private static func label(for keyCode: UInt16, in layout: UnsafePointer<UCKeyboardLayout>) -> String? {
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = UCKeyTranslate(
            layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState,
            characters.count, &length, &characters)
        guard status == noErr, length > 0 else { return nil }

        let text = String(utf16CodeUnits: characters, count: length)
        let unprintable = CharacterSet.controlCharacters.union(.whitespacesAndNewlines).union(.illegalCharacters)
        guard !text.unicodeScalars.contains(where: unprintable.contains) else { return nil }
        return text.uppercased()
    }
}
