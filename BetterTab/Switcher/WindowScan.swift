import ApplicationServices
import CoreFoundation
import Foundation
import os

/// HIServices' private functions for matching AX elements to window-server windows. Looked up at
/// runtime, so a macOS that drops one only costs the titles of windows AX can't see.
nonisolated enum AXPrivate {
    typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    typealias CreateWithRemoteToken = @convention(c) (CFData) -> Unmanaged<AXUIElement>?

    static let getWindow = resolve("_AXUIElementGetWindow", as: GetWindow.self)
    static let createWithRemoteToken = resolve("_AXUIElementCreateWithRemoteToken", as: CreateWithRemoteToken.self)

    /// The window server's id for an AX window, or nil if the app doesn't say.
    static func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let getWindow else { return nil }
        var id: CGWindowID = 0
        return getWindow(element, &id) == .success && id != 0 ? id : nil
    }

    private static func resolve<Function>(_ name: String, as _: Function.Type) -> Function? {
        let path = "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/Versions/A/HIServices"
        guard let handle = dlopen(path, RTLD_LAZY), let address = dlsym(handle, name) else {
            Logger(subsystem: "com.luksanss.BetterTab", category: "windows")
                .error("private symbol \(name, privacy: .public) is missing")
            return nil
        }
        return unsafeBitCast(address, to: Function.self)
    }
}

/// Where an app's element-id scan has got to. Kept for the process lifetime, so each load carries
/// on from the last.
nonisolated struct ScanProgress: Sendable {
    var cursor: UInt64 = 0
    /// The highest id seen belonging to a window, or 0.
    var highestAlive: UInt64 = 0
}

/// Finds the AX elements of windows AX won't list, those on other Spaces, by trying element ids
/// in a remote token one after another. Tokens are the 20 bytes AX uses to name an element in
/// another process: pid (Int32), 0 (Int32), "coco" (0x636f636f), element id (UInt64), all
/// little-endian. About 26 µs an id.
nonisolated enum WindowScan {
    struct Result: Sendable {
        var found: [CGWindowID: AXElement] = [:]
        var firstID: UInt64 = 0
        var scanned = 0
        var milliseconds = 0.0
        /// Stopped by `cancel()` rather than by the budget or the app.
        var cancelled = false
    }

    /// Ids grow over an app's life (TextEdit about 10, a long-running Finder about 31,000), so a
    /// scan resumes from the cursor. Once it has gone this far past the highest window id seen,
    /// the next one starts again from 0.
    static let wrapGap: UInt64 = 4096

    /// Tries ids from `progress.cursor` until every missing window is found, `budget` seconds
    /// pass, or the app stops answering (two timeouts in a row).
    static func run(
        pid: pid_t, missing: Set<CGWindowID>, progress: inout ScanProgress, budget: Double, isWanted: () -> Bool
    ) -> Result {
        var result = Result(firstID: progress.cursor)
        guard let create = AXPrivate.createWithRemoteToken, let getWindow = AXPrivate.getWindow,
              let token = CFDataCreateMutable(kCFAllocatorDefault, 20)
        else { return result }
        CFDataSetLength(token, 20)
        guard let bytes = CFDataGetMutableBytePtr(token) else { return result }
        func put(_ value: UInt64, at offset: Int, count: Int) {
            for index in 0..<count { bytes[offset + index] = UInt8(truncatingIfNeeded: value >> (8 * index)) }
        }
        put(UInt64(UInt32(bitPattern: pid)), at: 0, count: 4)
        put(0, at: 4, count: 4)
        put(0x636f_636f, at: 8, count: 4)

        let start = uptime()
        let deadline = start + budget
        var remaining = missing
        var id = progress.cursor
        var unanswered = 0
        scan: while !remaining.isEmpty, isWanted() {
            let now = uptime()
            guard now < deadline else { break }
            put(id, at: 12, count: 8)
            let current = id
            id &+= 1
            result.scanned += 1
            guard let element = create(token)?.takeRetainedValue() else { continue }
            // A remote element starts with the 6 s default; this keeps one slow answer within
            // the budget.
            AXUIElementSetMessagingTimeout(element, Float(min(max(deadline - now, 0.005), Double(AXCall.messagingTimeout))))
            var windowID: CGWindowID = 0
            switch getWindow(element, &windowID) {
            case .success where windowID != 0:
                unanswered = 0
                progress.highestAlive = max(progress.highestAlive, current)
                // A window's descendants report its id too; only the window itself will do.
                guard remaining.contains(windowID),
                      AXCall.string(element, kAXRoleAttribute).string == kAXWindowRole
                else { continue }
                // The one buffer is rewritten for every id, so the element kept gets a token of
                // its own, in case AX holds on to the data rather than copying it.
                guard let copy = CFDataCreateCopy(kCFAllocatorDefault, token),
                      let kept = create(copy)?.takeRetainedValue()
                else { continue }
                AXUIElementSetMessagingTimeout(kept, AXCall.messagingTimeout)
                result.found[windowID] = AXElement(element: kept)
                remaining.remove(windowID)
            case .cannotComplete:
                unanswered += 1
                if unanswered >= 2 { break scan }
            case .apiDisabled:
                break scan
            default:
                unanswered = 0
            }
        }
        result.cancelled = !remaining.isEmpty && !isWanted()
        progress.cursor = id
        if progress.highestAlive > 0, progress.cursor > progress.highestAlive + wrapGap { progress.cursor = 0 }
        result.milliseconds = (uptime() - start) * 1000
        return result
    }

    private static func uptime() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }
}
