// The real-window test in `SkyLightWindows.isRealWindow` follows `space_window_list_for_connection`
// in yabai (https://github.com/koekeishiya/yabai, src/space.c at dd84572), used under its licence:
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

import CoreGraphics
import Foundation
import Synchronization
import os

/// One of an app's real windows as the window server sees it, on any Space.
nonisolated struct SkyLightWindow: Sendable, Equatable {
    let windowID: CGWindowID
    /// The Space it's on (the display's current one if it's on several), or 0 if it has none.
    let spaceID: UInt64
    let isMinimized: Bool
    let isFullScreen: Bool
    /// In the window server's global coordinates (points, top-left origin), on whichever Space it's
    /// on. `.null` when SkyLight can't say, or when the snapshot wasn't asked for this app's.
    let frame: CGRect
}

/// Every app's real windows at one moment.
nonisolated struct SkyLightSnapshot: Sendable {
    /// SkyLight's global order: the current Space front to back, then the other Spaces, most
    /// recently visited first. Apps with no real window have no entry.
    let windowsByPid: [pid_t: [SkyLightWindow]]
    /// Each display's current Space.
    let currentSpaceIDs: [UInt64]
}

/// Lists every app's real windows on every Space, full-screen ones included, straight from the
/// window server. It needs no permission (measured on macOS 27); the one thing it can't give is
/// titles, which come from AX. Any thread; calls are serialized. About 1 ms once warm.
nonisolated enum SkyLightWindows {
    /// nil if SkyLight lacks one of the functions or the window server gave no answer. Frames
    /// cost a round trip per window, so they're read only for the apps in `framesOf`.
    static func snapshot(framesOf: Set<pid_t> = []) -> SkyLightSnapshot? {
        guard let functions = SkyLightFunctions.shared else { return nil }
        return lock.withLock { _ in read(functions, framesOf: framesOf) }
    }

    /// The window server's first answer about Spaces takes 10–15 ms; this pays for it at launch,
    /// off the main thread.
    static func warmUp() {
        DispatchQueue.global(qos: .utility).async { _ = snapshot() }
    }

    /// yabai's test for a window a user would call a window, less its levels 3 and 8: level 0 is
    /// the normal window level, so panels and floating windows never count. `attributes` bit 0 is
    /// set only when the caller has Screen Recording, so nothing may depend on it.
    static func isRealWindow(parent: UInt32, level: Int32, tags: UInt64, attributes: UInt64) -> Bool {
        guard parent == 0, level == 0 else { return false }
        let isDocumentKind = tags & 0x1 != 0 || (tags & 0x2 != 0 && tags & 0x8000_0000 != 0)
        let isShown = attributes & 0x2 != 0 || tags & 0x0400_0000_0000_0000 != 0
        let isOrderedOut = (attributes == 0 || attributes == 1)
            && (tags & minimizedTag != 0 || tags & 0x0300_0000_0000_0000 != 0)
        return isDocumentKind && (isShown || isOrderedOut)
    }

    private static let lock = Mutex(())

    /// `type` of a full-screen Space in `SLSCopyManagedDisplaySpaces` (0 is a desktop).
    private static let fullScreenSpaceType = 4
    /// `SLSCopyWindowsWithOptionsAndTags` options that include minimized windows.
    private static let includingMinimized: UInt32 = 0x7
    /// Seen in yabai; there was no minimized window to confirm it on. AX's answer wins when known.
    private static let minimizedTag: UInt64 = 1 << 60
    /// Set on full-screen windows (measured); the Space's type is checked first.
    private static let fullScreenTag: UInt64 = 1 << 42

    private static func read(_ sls: SkyLightFunctions, framesOf: Set<pid_t>) -> SkyLightSnapshot? {
        let connection = sls.mainConnectionID()
        guard let displays = sls.copyManagedDisplaySpaces(connection)?.takeRetainedValue() as? [[String: Any]]
        else { return nil }
        var spaces: [UInt64] = []
        var fullScreenSpaces = Set<UInt64>()
        var current: [UInt64] = []
        for display in displays {
            if let id = spaceID(display["Current Space"]) { current.append(id) }
            for space in display["Spaces"] as? [[String: Any]] ?? [] {
                guard let id = spaceID(space) else { continue }
                spaces.append(id)
                if (space["type"] as? NSNumber)?.intValue == fullScreenSpaceType { fullScreenSpaces.insert(id) }
            }
        }
        guard !spaces.isEmpty, let all = windowIDs(sls, connection, on: spaces) else { return nil }
        let count = CFArrayGetCount(all)
        guard count > 0 else { return SkyLightSnapshot(windowsByPid: [:], currentSpaceIDs: current) }

        // One round trip for every row. The owner argument above doesn't filter, so rows are
        // told apart by pid here.
        guard let query = sls.queryWindows(connection, all, Int32(count))?.takeRetainedValue(),
              let iterator = sls.queryResultCopyWindows(query)?.takeRetainedValue()
        else { return nil }
        var rows: [(windowID: CGWindowID, pid: pid_t, tags: UInt64)] = []
        // The iterator may point into the query and the id list without retaining them (yabai
        // releases both only after iterating), so neither may be freed before the loop ends.
        withExtendedLifetime((all, query)) {
            while sls.iteratorAdvance(iterator) {
                let tags = sls.iteratorTags(iterator)
                let pid = sls.iteratorPID(iterator)
                guard pid > 0, isRealWindow(
                    parent: sls.iteratorParentID(iterator), level: sls.iteratorLevel(iterator),
                    tags: tags, attributes: sls.iteratorAttributes(iterator))
                else { continue }
                rows.append((sls.iteratorWindowID(iterator), pid, tags))
            }
        }

        // The iterator's own Space list comes back empty, so ask Space by Space: current ones
        // first, so a window on every Space reports the one on screen.
        let real = Set(rows.map(\.windowID))
        var spaceOf: [CGWindowID: UInt64] = [:]
        for space in current + spaces.filter({ !current.contains($0) }) {
            for case let number as NSNumber in windowIDs(sls, connection, on: [space]) as? [Any] ?? [] {
                let windowID = number.uint32Value
                if real.contains(windowID), spaceOf[windowID] == nil { spaceOf[windowID] = space }
            }
        }

        var windowsByPid: [pid_t: [SkyLightWindow]] = [:]
        for row in rows {
            let space = spaceOf[row.windowID] ?? 0
            windowsByPid[row.pid, default: []].append(SkyLightWindow(
                windowID: row.windowID, spaceID: space,
                isMinimized: row.tags & minimizedTag != 0,
                isFullScreen: fullScreenSpaces.contains(space) || row.tags & fullScreenTag != 0,
                frame: framesOf.contains(row.pid) ? frame(sls, connection, row.windowID) : .null))
        }
        return SkyLightSnapshot(windowsByPid: windowsByPid, currentSpaceIDs: current)
    }

    /// Needs no permission, and answers for windows on other Spaces too (measured on macOS 27).
    private static func frame(_ sls: SkyLightFunctions, _ connection: Int32, _ windowID: CGWindowID) -> CGRect {
        guard let getWindowBounds = sls.getWindowBounds else { return .null }
        var frame = CGRect.null
        return getWindowBounds(connection, windowID, &frame) == .success ? frame : .null
    }

    private static func windowIDs(_ sls: SkyLightFunctions, _ connection: Int32, on spaces: [UInt64]) -> CFArray? {
        var setTags: UInt64 = 0
        var clearTags: UInt64 = 0
        return sls.copyWindowsWithOptionsAndTags(
            connection, 0, spaces.map { NSNumber(value: $0) } as CFArray, includingMinimized, &setTags, &clearTags
        )?.takeRetainedValue()
    }

    private static func spaceID(_ space: Any?) -> UInt64? {
        guard let space = space as? [String: Any],
              let id = (space["id64"] as? NSNumber) ?? (space["ManagedSpaceID"] as? NSNumber)
        else { return nil }
        return id.uint64Value
    }
}

/// SkyLight's private window-list functions, looked up at runtime: a macOS that drops one makes
/// BetterTab fall back to AX's current-Space windows instead of failing to launch.
nonisolated private struct SkyLightFunctions: Sendable {
    typealias MainConnectionID = @convention(c) () -> Int32
    typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    typealias CopyWindowsWithOptionsAndTags = @convention(c) (
        Int32, UInt32, CFArray, UInt32, UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>
    ) -> Unmanaged<CFArray>?
    typealias QueryWindows = @convention(c) (Int32, CFArray, Int32) -> Unmanaged<CFTypeRef>?
    typealias QueryResultCopyWindows = @convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?
    typealias IteratorBool = @convention(c) (CFTypeRef) -> Bool
    typealias IteratorUInt32 = @convention(c) (CFTypeRef) -> UInt32
    typealias IteratorInt32 = @convention(c) (CFTypeRef) -> Int32
    typealias IteratorUInt64 = @convention(c) (CFTypeRef) -> UInt64
    typealias GetWindowBounds = @convention(c) (Int32, UInt32, UnsafeMutablePointer<CGRect>) -> CGError

    let mainConnectionID: MainConnectionID
    let copyManagedDisplaySpaces: CopyManagedDisplaySpaces
    let copyWindowsWithOptionsAndTags: CopyWindowsWithOptionsAndTags
    let queryWindows: QueryWindows
    let queryResultCopyWindows: QueryResultCopyWindows
    let iteratorAdvance: IteratorBool
    let iteratorWindowID: IteratorUInt32
    let iteratorPID: IteratorInt32
    let iteratorParentID: IteratorUInt32
    let iteratorLevel: IteratorInt32
    let iteratorTags: IteratorUInt64
    let iteratorAttributes: IteratorUInt64
    /// Only the ⌘§ switcher's window outlines need it, so a macOS without it keeps everything else.
    let getWindowBounds: GetWindowBounds?

    static let shared: SkyLightFunctions? = load()

    private static func load() -> SkyLightFunctions? {
        let log = Logger(subsystem: "com.luksanss.BetterTab", category: "windows")
        // AppKit has loaded SkyLight already, so this only returns a handle to it.
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_LAZY)
        else {
            log.error("SkyLight didn't load; windows on other Spaces won't be listed")
            return nil
        }
        func resolve<Function>(_ name: String, _: Function.Type) -> Function? {
            guard let address = dlsym(handle, name) else {
                log.error("private symbol \(name, privacy: .public) is missing; windows on other Spaces won't be listed")
                return nil
            }
            return unsafeBitCast(address, to: Function.self)
        }
        guard let mainConnectionID = resolve("SLSMainConnectionID", MainConnectionID.self),
              let copyManagedDisplaySpaces = resolve("SLSCopyManagedDisplaySpaces", CopyManagedDisplaySpaces.self),
              let copyWindows = resolve("SLSCopyWindowsWithOptionsAndTags", CopyWindowsWithOptionsAndTags.self),
              let queryWindows = resolve("SLSWindowQueryWindows", QueryWindows.self),
              let queryResultCopyWindows = resolve("SLSWindowQueryResultCopyWindows", QueryResultCopyWindows.self),
              let advance = resolve("SLSWindowIteratorAdvance", IteratorBool.self),
              let windowID = resolve("SLSWindowIteratorGetWindowID", IteratorUInt32.self),
              let pid = resolve("SLSWindowIteratorGetPID", IteratorInt32.self),
              let parentID = resolve("SLSWindowIteratorGetParentID", IteratorUInt32.self),
              let level = resolve("SLSWindowIteratorGetLevel", IteratorInt32.self),
              let tags = resolve("SLSWindowIteratorGetTags", IteratorUInt64.self),
              let attributes = resolve("SLSWindowIteratorGetAttributes", IteratorUInt64.self)
        else { return nil }
        let getWindowBounds = dlsym(handle, "SLSGetWindowBounds").map { unsafeBitCast($0, to: GetWindowBounds.self) }
        if getWindowBounds == nil {
            log.error("private symbol SLSGetWindowBounds is missing; the ⌘§ switcher shows no window outlines")
        }
        return SkyLightFunctions(
            mainConnectionID: mainConnectionID, copyManagedDisplaySpaces: copyManagedDisplaySpaces,
            copyWindowsWithOptionsAndTags: copyWindows, queryWindows: queryWindows,
            queryResultCopyWindows: queryResultCopyWindows, iteratorAdvance: advance, iteratorWindowID: windowID,
            iteratorPID: pid, iteratorParentID: parentID, iteratorLevel: level, iteratorTags: tags,
            iteratorAttributes: attributes, getWindowBounds: getWindowBounds)
    }
}
