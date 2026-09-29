// The event records below follow `window_manager_make_key_window` in yabai
// (https://github.com/koekeishiya/yabai, src/window_manager.c at 491ed8d), used under its licence:
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
    /// It posts a synthetic left mouse down and up straight to the process, addressed to the
    /// window. The record layout is undocumented, reverse-engineered by yabai:
    /// - 0x04 = 0xf8: the record's length.
    /// - 0x08: the event type, 1 for left mouse down and 2 for left mouse up (as in `CGEventType`).
    /// - 0x20…0x2f = 0xff: the location. All ones is NaN, so the click lands on no point in the
    ///   window: AppKit makes the window key, but no button or text in it is clicked.
    /// - 0x3a = 0x10: a flag yabai always sets; its meaning isn't known.
    /// - 0x3c: the target window id, little-endian.
    ///
    /// Returns false if the function is missing or either post fails.
    static func makeKeyWindow(_ psn: inout ProcessSerialNumber, windowID: CGWindowID) -> Bool {
        guard let post = postEventRecordTo else { return false }
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: windowID.littleEndian) { bytes.replaceSubrange(0x3c..<0x40, with: $0) }
        bytes.replaceSubrange(0x20..<0x30, with: repeatElement(0xff, count: 0x10))

        var ok = true
        for type: UInt8 in [0x01, 0x02] {
            bytes[0x08] = type
            ok = post(&psn, &bytes) == .success && ok
        }
        return ok
    }
}
