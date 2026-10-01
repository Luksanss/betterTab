import AppKit
import ApplicationServices
import os

/// Brings one specific window to the front as the key window, on whichever Space it's on.
enum Focuser {
    /// Unhides the app if hidden, restores the window if minimized, then makes it the front,
    /// key window without bringing the app's other windows forward. A window on another Space,
    /// full-screen or not, brings its Space on screen with the usual slide.
    ///
    /// Only the window id is needed; the AX element, when there is one, restores and raises the
    /// window. Returns at once. The work runs on a serial queue, because each AX call can wait up
    /// to the AX timeout on a slow app, and a Space switch is waited for.
    static func focus(pid: pid_t, window: AppWindow) {
        let target = Target(pid: pid, windowID: window.windowID, element: window.element,
                            isMinimized: window.isMinimized, start: now())
        queue.async { run(target) }
    }

    /// Spec constant: AX messaging timeout.
    private nonisolated static let axTimeout: Float = 0.25
    /// The longest a hidden app gets to show its windows again before we carry on regardless.
    private nonisolated static let unhideWait: UInt64 = 100_000_000
    /// The longest a Space switch gets to start before we fall back to `activate`.
    private nonisolated static let spaceSwitchWait: UInt64 = 300_000_000
    private nonisolated static let queue = DispatchQueue(label: "com.luksanss.BetterTab.focus",
                                                         qos: .userInteractive)
    private nonisolated static let logger = Logger(subsystem: "com.luksanss.BetterTab", category: "focus")

    /// AX elements are safe to use from any thread.
    private nonisolated struct Target: @unchecked Sendable {
        let pid: pid_t
        let windowID: CGWindowID
        let element: AXUIElement?
        let isMinimized: Bool
        let start: UInt64
    }

    /// Where the window is, read before anything moves.
    private nonisolated struct Placement {
        /// The Space the window's display shows now, which a switch would replace.
        let originSpace: UInt64
        /// The window isn't on the Space its display shows, so focusing it has to switch Space.
        let isElsewhere: Bool
        /// The origin Space is the one the user is working in, which holds the front app.
        let originIsActive: Bool
    }

    private nonisolated enum SpaceOutcome: String {
        case here = "already on screen"
        case unknown
        case switched
        case stuck = "didn't switch"
    }

    /// 1. Unhide the app; 2. restore the window if minimized; 3. note where the window is and
    /// which app is in front; 4. bring the process forward with just this window; 5. make the
    /// window key; 6. raise it through AX; then, for a window on another Space, 7. give the Space
    /// the user left its front app back and 8. wait up to `spaceSwitchWait` for the window's Space
    /// to come on screen, or fall back to `activate`.
    private nonisolated static func run(_ target: Target) {
        let started = now()
        if let element = target.element { AXUIElementSetMessagingTimeout(element, axTimeout) }
        guard target.windowID != 0 else { return fallback(target, reason: "no window id") }

        // 1 and 2.
        let unhid = unhideIfHidden(pid: target.pid)
        let restored = restoreIfMinimized(target)
        let prepared = now()

        guard var psn = processSerialNumber(for: target.pid) else {
            return fallback(target, reason: "no process serial number")
        }
        guard let setFront = FocusSymbols.setFrontProcessWithOptions else {
            return fallback(target, reason: "no _SLPSSetFrontProcessWithOptions")
        }

        // 3. Nil when SkyLight can't tell; focusing then skips steps 7 and 8.
        let placement = placement(of: target.windowID)
        let originFront = frontProcess()

        // 4. Passing the window id brings only that window forward, so the app's most recent
        // window doesn't flash up first. On its own this makes the app frontmost but doesn't
        // switch Space (measured on macOS 27); AltTab and yabai rely on the make-key record and
        // the raise for that.
        let frontError = setFront(&psn, target.windowID, FocusSymbols.userGenerated)
        guard frontError == .success else {
            return fallback(target, reason: "_SLPSSetFrontProcessWithOptions error \(frontError.rawValue)")
        }
        let fronted = now()

        // 5 and 6. The window server has the window in front now; raising makes the app's own
        // window order agree, so the app treats it as its most recent window from here on.
        let keyed = FocusSymbols.makeKeyWindow(&psn, windowID: target.windowID)
        let raiseError = raise(target.element)
        let raised = now()

        // 7.
        let originRestored = placement.map {
            restoreOriginFront($0, originFront, target: psn, windowWasMinimized: restored)
        } ?? false

        // 8.
        let outcome: SpaceOutcome
        switch placement {
        case nil: outcome = .unknown
        case let placement? where !placement.isElsewhere: outcome = .here
        default: outcome = waitUntilOnScreen(target.windowID) ? .switched : .stuck
        }
        let done = now()

        logger.notice("""
            pid \(target.pid, privacy: .private) window \(target.windowID, privacy: .private): \
            front in \(ms(target.start, done), format: .fixed(precision: 1)) ms \
            (queue \(ms(target.start, started), format: .fixed(precision: 1)), \
            unhide+restore \(ms(started, prepared), format: .fixed(precision: 1)), \
            front \(ms(prepared, fronted), format: .fixed(precision: 1)), \
            key+raise \(ms(fronted, raised), format: .fixed(precision: 1)), \
            space \(ms(raised, done), format: .fixed(precision: 1))); \
            unhid \(unhid), restored \(restored), key \(keyed), raise \(describe(raiseError), privacy: .public), \
            space \(outcome.rawValue, privacy: .public), origin front restored \(originRestored)
            """)

        if outcome == .stuck {
            // `activate` switches to the Space of the app's front window, which the raise made
            // the target. It does nothing for an app that's already frontmost (measured on macOS
            // 27), which step 7 undid when it could.
            activate(target, reason: "Space didn't switch", raiseError: raiseError)
        }
    }

    // MARK: - Steps

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

    /// Returns whether the window was minimized. The ⌘§ switcher read the flag moments ago, which
    /// saves an AX round trip; setting it on a window that's no longer minimized does nothing.
    private nonisolated static func restoreIfMinimized(_ target: Target) -> Bool {
        guard target.isMinimized else { return false }
        guard let element = target.element else {
            logger.error("window \(target.windowID, privacy: .private) is minimized but has no AX element to restore it")
            return true
        }
        let error = AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        if error != .success {
            logger.error("restoring a minimized window failed: AX error \(error.rawValue)")
        }
        return true
    }

    /// Raises the window within its app and makes it the app's main window, so the app, and any
    /// `activate` after this, treat it as the app's front window. Nil without an element.
    private nonisolated static func raise(_ element: AXUIElement?) -> AXError? {
        guard let element else { return nil }
        let error = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        return error
    }

    private nonisolated static func placement(of windowID: CGWindowID) -> Placement? {
        let spaces = FocusSymbols.spaces(of: windowID)
        guard !spaces.isEmpty, let displays = FocusSymbols.displays(),
              let display = displays.first(where: { $0.spaces.contains(where: spaces.contains) })
        else { return nil }
        let active = FocusSymbols.activeSpace()
        return Placement(originSpace: display.currentSpace,
                         isElsewhere: !spaces.contains(display.currentSpace),
                         originIsActive: active == nil || active == display.currentSpace)
    }

    /// Waits until some display shows a Space the window is on. Both are re-read each time: an
    /// app can move its window while it comes forward.
    private nonisolated static func waitUntilOnScreen(_ windowID: CGWindowID) -> Bool {
        let deadline = now() + spaceSwitchWait
        while true {
            let spaces = FocusSymbols.spaces(of: windowID)
            if let displays = FocusSymbols.displays(),
               displays.contains(where: { spaces.contains($0.currentSpace) }) {
                return true
            }
            if now() >= deadline { return false }
            usleep(10_000)
        }
    }

    /// Step 7. Bringing an app forward also makes it the front app of the Spaces where it has
    /// windows, so returning to the Space the user left would show the target app there instead
    /// of the app they left (reported against AltTab as #4507). This puts that app back.
    ///
    /// Once the make-key record and the raise have switched Space, the origin Space is off screen
    /// and only what it remembers changes. If they haven't, it's still on screen and this brings
    /// the origin app back in front of the target (AltTab #5586). That's what the fallback needs:
    /// `activate` doesn't switch Space for an app that's already frontmost.
    ///
    /// Skipped when the origin Space isn't the one the user was in (another display: its front
    /// app isn't the one recorded), when the target app was already in front (nothing to put
    /// back), and for a just-restored window, which can land on the origin Space itself and would
    /// end up behind the origin app.
    private nonisolated static func restoreOriginFront(
        _ placement: Placement, _ originFront: ProcessSerialNumber?, target: ProcessSerialNumber,
        windowWasMinimized: Bool
    ) -> Bool {
        guard placement.isElsewhere, placement.originIsActive, !windowWasMinimized,
              let originFront, !isSame(originFront, target)
        else { return false }
        return FocusSymbols.setFrontProcess(originFront, ofSpace: placement.originSpace)
    }

    // MARK: - Processes

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

    private nonisolated static func frontProcess() -> ProcessSerialNumber? {
        guard let getFrontProcess = FocusSymbols.getFrontProcess else { return nil }
        var psn = ProcessSerialNumber()
        guard getFrontProcess(&psn) == 0, psn.highLongOfPSN != 0 || psn.lowLongOfPSN != 0 else { return nil }
        return psn
    }

    private nonisolated static func isSame(_ a: ProcessSerialNumber, _ b: ProcessSerialNumber) -> Bool {
        a.highLongOfPSN == b.highLongOfPSN && a.lowLongOfPSN == b.lowLongOfPSN
    }

    // MARK: - Fallback

    /// Used when a private function is missing or fails, before anything has moved. Raising the
    /// window first means that if the activation goes through, it brings this window forward, not
    /// the app's most recent one.
    private nonisolated static func fallback(_ target: Target, reason: String) {
        activate(target, reason: reason, raiseError: raise(target.element))
    }

    /// Since macOS 14 `activate` is only a request and may be refused. It switches to the Space of
    /// the app's front window.
    private nonisolated static func activate(_ target: Target, reason: String, raiseError: AXError?) {
        let activated = NSRunningApplication(processIdentifier: target.pid)?.activate(options: []) ?? false
        logger.error("""
            pid \(target.pid, privacy: .private) window \(target.windowID, privacy: .private): \
            fell back to activate (\(reason, privacy: .public)) in \
            \(ms(target.start, now()), format: .fixed(precision: 1)) ms; \
            activate \(activated ? "sent" : "refused", privacy: .public), \
            raise \(describe(raiseError), privacy: .public)
            """)
    }

    // MARK: - Helpers

    private nonisolated static func describe(_ error: AXError?) -> String {
        guard let error else { return "skipped, no element" }
        return error == .success ? "ok" : "error \(error.rawValue)"
    }

    private nonisolated static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    private nonisolated static func ms(_ from: UInt64, _ to: UInt64) -> Double {
        (Double(to) - Double(from)) / 1_000_000
    }
}
