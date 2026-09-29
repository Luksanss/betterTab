import AppKit
import ApplicationServices
import os

/// Brings one specific window to the front as the key window.
enum Focuser {
    /// Unhides the app if hidden, restores the window if minimized, then makes it the front,
    /// key window without bringing the app's other windows forward.
    ///
    /// Returns at once. The work runs on a serial queue, because each AX call can wait up to the
    /// AX timeout on a slow app.
    static func focus(pid: pid_t, window: AppWindow) {
        guard let element = window.element else { return }
        let target = Target(pid: pid, window: element, start: now())
        queue.async { run(target) }
    }

    /// Spec constant: AX messaging timeout.
    private nonisolated static let axTimeout: Float = 0.25
    /// The longest a hidden app gets to show its windows again before we carry on regardless.
    private nonisolated static let unhideWait: UInt64 = 100_000_000
    private nonisolated static let queue = DispatchQueue(label: "com.luksanss.BetterTab.focus",
                                                         qos: .userInteractive)
    private nonisolated static let logger = Logger(subsystem: "com.luksanss.BetterTab", category: "focus")

    /// AX elements are safe to use from any thread.
    private nonisolated struct Target: @unchecked Sendable {
        let pid: pid_t
        let window: AXUIElement
        let start: UInt64
    }

    private nonisolated static func run(_ target: Target) {
        let window = target.window
        let started = now()
        AXUIElementSetMessagingTimeout(window, axTimeout)

        let unhid = unhideIfHidden(pid: target.pid)
        let restored = restoreIfMinimized(window)
        let prepared = now()

        guard let windowID = FocusSymbols.windowID(of: window) else {
            return fallback(target, reason: "no window id")
        }
        guard var psn = processSerialNumber(for: target.pid) else {
            return fallback(target, reason: "no process serial number")
        }
        guard let setFront = FocusSymbols.setFrontProcessWithOptions else {
            return fallback(target, reason: "no _SLPSSetFrontProcessWithOptions")
        }
        // Passing the window id brings only that window forward, so the app's most recent
        // window doesn't flash up first.
        let frontError = setFront(&psn, windowID, FocusSymbols.userGenerated)
        guard frontError == .success else {
            return fallback(target, reason: "_SLPSSetFrontProcessWithOptions error \(frontError.rawValue)")
        }
        let fronted = now()

        let keyed = FocusSymbols.makeKeyWindow(&psn, windowID: windowID)
        // The window server has the window in front now; raising makes the app's own window
        // order agree, so the app treats it as its most recent window from here on.
        let raiseError = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        let done = now()

        logger.notice("""
            pid \(target.pid, privacy: .private) window \(windowID, privacy: .private): front in \(ms(target.start, done), format: .fixed(precision: 1)) ms \
            (queue \(ms(target.start, started), format: .fixed(precision: 1)), \
            unhide+restore \(ms(started, prepared), format: .fixed(precision: 1)), \
            front \(ms(prepared, fronted), format: .fixed(precision: 1)), \
            key+raise \(ms(fronted, done), format: .fixed(precision: 1))); \
            unhid \(unhid), restored \(restored), key \(keyed), raise error \(raiseError.rawValue)
            """)
    }

    /// Returns whether the app was hidden.
    private nonisolated static func unhideIfHidden(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid), app.isHidden else { return false }
        guard app.unhide() else {
            logger.error("pid \(pid, privacy: .private): unhide was refused")
            return true
        }
        // `unhide` only sends a request. Wait until the app says it's shown, because windows that
        // reappear after the pick can land on top of the chosen one. AppKit answers AX on its main
        // thread, so once this reads false the app has put its windows back.
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, axTimeout)
        let deadline = now() + unhideWait
        repeat {
            var hidden: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXHiddenAttribute as CFString, &hidden) == .success,
               (hidden as? Bool) == false {
                return true
            }
            usleep(5_000)
        } while now() < deadline
        logger.error("pid \(pid, privacy: .private): still hidden after \(unhideWait / 1_000_000) ms; focusing anyway")
        return true
    }

    /// Returns whether the window was minimized.
    private nonisolated static func restoreIfMinimized(_ window: AXUIElement) -> Bool {
        var minimized: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized) == .success,
              (minimized as? Bool) == true
        else { return false }
        let error = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        if error != .success {
            logger.error("restoring a minimized window failed: AX error \(error.rawValue)")
        }
        return true
    }

    private nonisolated static func processSerialNumber(for pid: pid_t) -> ProcessSerialNumber? {
        guard let getProcessForPID = FocusSymbols.getProcessForPID else { return nil }
        var psn = ProcessSerialNumber()
        let status = getProcessForPID(pid, &psn)
        guard status == 0 else {
            logger.error("pid \(pid, privacy: .private): GetProcessForPID error \(status)")
            return nil
        }
        return psn
    }

    /// Used when a private function is missing or fails. Since macOS 14 `activate` is only a
    /// request and may be refused. Making the window main and raising it first means that if the
    /// activation goes through, it brings this window forward, not the app's most recent one.
    private nonisolated static func fallback(_ target: Target, reason: String) {
        AXUIElementSetAttributeValue(target.window, kAXMainAttribute as CFString, kCFBooleanTrue)
        let raiseError = AXUIElementPerformAction(target.window, kAXRaiseAction as CFString)
        let activated = NSRunningApplication(processIdentifier: target.pid)?.activate(options: []) ?? false
        logger.error("""
            pid \(target.pid, privacy: .private): fell back to activate (\(reason, privacy: .public)) in \
            \(ms(target.start, now()), format: .fixed(precision: 1)) ms; \
            activate \(activated ? "sent" : "refused", privacy: .public), raise error \(raiseError.rawValue)
            """)
    }

    private nonisolated static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    private nonisolated static func ms(_ from: UInt64, _ to: UInt64) -> Double {
        (Double(to) - Double(from)) / 1_000_000
    }
}
