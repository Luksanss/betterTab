// The event record below follows `window_manager_make_key_window` in yabai
// (https://github.com/koekeishiya/yabai, src/window_manager.c at dd84572), used under its licence:
//
// The MIT License (MIT)
//
// Copyright (c) 2019 Åsmund Vikane
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import ApplicationServices

nonisolated extension FocusSymbols {
    /// Makes `windowID` the app's key window. Bringing the process to the front only orders the
    /// window; without this, keystrokes can still go to the app's previous key window.
    ///
    /// It posts one synthetic left mouse down straight to the process, addressed to the window by
    /// id. The record layout is undocumented, reverse-engineered by yabai:
    /// - 0x04 = 0xf8: the record's length.
    /// - 0x08 = 1: the event type, left mouse down (as in `CGEventType`).
    /// - 0x20…0x2f: the click point relative to the window, as two little-endian doubles.
    /// - 0x3a = 0x10: a byte yabai always sets; its meaning isn't documented.
    /// - 0x3c: the target window id, little-endian.
    ///
    /// Two changes from yabai, both so that no control in the window can ever be clicked:
    /// - **A mouse down only, no mouse up.** Buttons, the traffic lights and links act on the up,
    ///   so a lone down can't complete a click wherever it lands. The down alone is what makes the
    ///   window key; an up alone does nothing (AltTab's measurement on macOS 26, reported in its
    ///   source; to be confirmed on 27 by the self-test).
    /// - **A point far past the window's bottom-right corner**, not yabai's all-ones NaN. Some apps
    ///   turn a NaN point into (0, 0), the top-left corner, where a full-screen window has its
    ///   close button and traffic lights (reported against AltTab as #5381). A point just outside
    ///   the frame is no better: on macOS 27 it lands in the resize area and resizes the window
    ///   (AltTab #5900). 100 000 points is outside any window or display arrangement, and an app
    ///   that clamps the point to its bounds clamps it to the bottom-right, away from the controls.
    ///
    /// Returns false if the function is missing or the post fails.
    static func makeKeyWindow(_ psn: inout ProcessSerialNumber, windowID: CGWindowID) -> Bool {
        guard let post = postEventRecordTo else { return false }
        // The window server reads past the record's 0xf8 bytes, so a buffer of exactly 0xf8 lets
        // it read whatever follows on the heap. yabai allocates 0x100, zeroed.
        var bytes = [UInt8](repeating: 0, count: 0x100)
        bytes[0x04] = 0xf8
        bytes[0x08] = 0x01
        bytes[0x3a] = 0x10
        let offContent = 100_000.0
        withUnsafeBytes(of: offContent.bitPattern.littleEndian) {
            bytes.replaceSubrange(0x20..<0x28, with: $0)
            bytes.replaceSubrange(0x28..<0x30, with: $0)
        }
        withUnsafeBytes(of: windowID.littleEndian) { bytes.replaceSubrange(0x3c..<0x40, with: $0) }
        return post(&psn, &bytes) == .success
    }
}
