import CoreGraphics
import Dispatch
import Foundation
import Synchronization
import os

// Everything in this file runs on the tap thread, the timeout queue or the main thread, so it's
// all nonisolated. Its design is the reviewed test 0 harness (Experiment/HoldMachine.swift),
// adapted to the product's Idle → Cycling → Picking states.

nonisolated enum TapLog {
    static let logger = Logger(subsystem: "com.luksanss.BetterTab", category: "tap")
}

/// Virtual key codes (Carbon `kVK_*`), kept here so the tap never touches Carbon.
nonisolated enum TapKey {
    static let tab: Int64 = 48
    static let escape: Int64 = 53
    static let command: Int64 = 55
    static let rightCommand: Int64 = 54
    static let leftArrow: Int64 = 123
    static let rightArrow: Int64 = 124
    static let downArrow: Int64 = 125
    static let upArrow: Int64 = 126
    /// `kVK_ISO_Section`: the § key, above Tab on ISO keyboards. ANSI keyboards have no such key.
    static let section: Int64 = 10

    static let arrows: Set<Int64> = [leftArrow, rightArrow, downArrow, upArrow]
}

/// Nanoseconds on a clock that keeps counting while the Mac sleeps (Darwin's CLOCK_MONOTONIC),
/// so time asleep counts towards the no-input timeout.
nonisolated func continuousNanos() -> UInt64 { clock_gettime_nsec_np(CLOCK_MONOTONIC) }

nonisolated enum TapPhase: String, Sendable {
    case idle = "Idle"
    case cycling = "Cycling"
    case picking = "Picking"
    /// The ⌘§ window switcher. Nothing is swallowed that macOS is owed: ⌘ passes both ways.
    case windows = "Windows"
}

nonisolated enum TapInputKind: Sendable {
    case keyDown, keyUp, flagsChanged

    init?(_ type: CGEventType) {
        switch type {
        case .keyDown: self = .keyDown
        case .keyUp: self = .keyUp
        case .flagsChanged: self = .flagsChanged
        default: return nil
        }
    }
}

/// Only plain values, copied out of the CGEvent before the lock is taken.
nonisolated struct TapInput: Sendable {
    let kind: TapInputKind
    let keycode: Int64
    let flags: CGEventFlags
    let autorepeat: Bool
    let now: UInt64
}

nonisolated enum TapVerdict: Sendable {
    /// `keycode` is the ⌘ key the Dock believes is held; its device bit goes on too.
    case pass, passAddingCommand(keycode: Int64), swallow
}

nonisolated struct TapState {
    var phase = TapPhase.idle
    /// Goes up on every phase change, so a stale timeout, message or `endHold` can tell it's stale.
    var generation: UInt64 = 0
    var enteredAt: UInt64 = 0
    /// Set from main: releasing ⌘ now should hold the switcher (the highlighted app has ≥ 2 windows).
    var holdOnRelease = false
    /// True from the moment a ⌘ release is swallowed until the Dock has been given one.
    var owesCommandRelease = false
    /// The ⌘ key (left 55, right 54) whose release became owed. The synthetic release replays it.
    var commandKeycode = TapKey.command
    /// Physical ⌘, as last seen in a flagsChanged event (swallowed or not).
    var commandDown = false
    /// ⌘ was physically pressed again during Picking; the press was swallowed.
    var commandPressedAgain = false
    /// Keys whose keyDown was swallowed: their keyUp and autorepeats are swallowed too.
    var swallowedKeys: Set<Int64> = []
    /// When the last key event arrived during Picking, for the no-input timeout.
    var lastKeyAt: UInt64 = 0
    /// Keys forwarded to main in this Picking session. Logged as a count, never as key codes.
    var keys = 0

    mutating func enter(_ next: TapPhase, at now: UInt64) {
        phase = next
        generation &+= 1
        enteredAt = now
        if next == .picking {
            lastKeyAt = now
            keys = 0
        }
    }
}

/// Log lines decided under the lock and written after it's released. States and counts only.
nonisolated enum TapNote: Sendable {
    case cycleStarted
    case holdStarted
    case releasePassed
    case nativeCancel
    case owedReleasePaid
    case backToCycling(keys: Int)
    case windowsStarted
    case windowsReleased
    case windowsMissedRelease
    case windowsToCycling

    func log() {
        let logger = TapLog.logger
        switch self {
        case .cycleStarted:
            logger.info("Idle → Cycling: ⌘⇥ passed")
        case .holdStarted:
            logger.info("Cycling → Picking: ⌘ release swallowed, switcher held open")
        case .releasePassed:
            logger.info("Cycling → Idle: ⌘ release passed (native switch)")
        case .nativeCancel:
            logger.info("Cycling → Idle: Esc passed (native cancel)")
        case .owedReleasePaid:
            logger.info("Idle: a physical ⌘ release passed, so the Dock has its release")
        case .backToCycling(let keys):
            logger.info("Picking → Cycling: ⌘⇥ again after \(keys, privacy: .public) keys; the ⌘ release is still owed")
        case .windowsStarted:
            logger.info("Idle → Windows: ⌘§ swallowed")
        case .windowsReleased:
            logger.info("Windows → Idle: ⌘ release passed")
        case .windowsMissedRelease:
            logger.info("Windows → Idle: a key came with ⌘ up, so its release got past us")
        case .windowsToCycling:
            logger.info("Windows → Cycling: ⌘⇥ passed")
        }
    }
}

nonisolated struct StepResult: Sendable {
    var verdict = TapVerdict.pass
    var event: TapEvent?
    /// The generation after the step; set by `process`.
    var generation: UInt64 = 0
    var end: EndPlan?
    var note: TapNote?
    var startsPicking = false
}

/// What one exit posts, decided under the lock and carried out after it's released.
nonisolated struct EndPlan: Sendable {
    let from: TapPhase
    let reason: TapEndReason
    let postEscape: Bool
    let postRelease: Bool
    let commandKeycode: Int64
    let keys: Int
    let held: UInt64
    let message: TapMessage?
}

nonisolated private enum TimeoutCheck: Sendable {
    case stale, wait(UInt64), end(EndPlan?)
}

/// The product tap's state machine. `process` runs on the tap thread; everything else may run on
/// any thread. All state sits behind one lock, and nothing slow happens while it's held: logging,
/// posting and messages to main happen after it's released.
nonisolated final class TapMachine: Sendable {
    /// Spec constant: cancel after 15 s with no key pressed.
    static let noInputTimeout: UInt64 = 15 * 1_000_000_000

    private let state = Mutex(TapState())
    private let send: @Sendable (TapMessage) -> Void
    private let timeoutQueue = DispatchQueue(label: "com.luksanss.BetterTab.tap.timeout")

    init(send: @escaping @Sendable (TapMessage) -> Void) {
        self.send = send
    }

    var holdOnRelease: Bool {
        get { state.withLock { $0.holdOnRelease } }
        set { state.withLock { $0.holdOnRelease = newValue } }
    }

    // MARK: Tap thread

    func process(_ input: TapInput) -> TapVerdict {
        let result = state.withLock { s in
            var result = Self.step(&s, input)
            result.generation = s.generation
            return result
        }
        result.note?.log()
        if let end = result.end { execute(end) }
        if let event = result.event { send(TapMessage(event: event, generation: result.generation)) }
        if result.startsPicking { scheduleTimeout(result.generation, after: Self.noInputTimeout) }
        return result.verdict
    }

    /// macOS turned the tap off. Events went past it meanwhile, so a hold can't be trusted.
    func tapWasDisabled() {
        end(.cancel, reason: .tapDisabled)
        resetTracking()
    }

    private static func step(_ s: inout TapState, _ e: TapInput) -> StepResult {
        var r = StepResult()
        let command = e.flags.contains(.maskCommand)
        // Every key event during Picking counts as input for the no-input timeout.
        if s.phase == .picking { s.lastKeyAt = e.now }

        if e.kind == .keyUp, s.swallowedKeys.remove(e.keycode) != nil {
            r.verdict = .swallow
            return r
        }
        if e.kind == .keyDown, s.phase != .picking, s.phase != .windows, s.swallowedKeys.contains(e.keycode) {
            // A key still held from a Picking or Windows session that has ended, or gone back to
            // cycling: keep its repeats away from the Dock and the app.
            if e.autorepeat {
                r.verdict = .swallow
                return r
            }
            s.swallowedKeys.remove(e.keycode)
        }

        switch s.phase {
        case .idle:
            switch e.kind {
            case .keyDown:
                let blocked: CGEventFlags = [.maskControl, .maskAlternate]
                if e.keycode == TapKey.tab, command, e.flags.intersection(blocked).isEmpty {
                    // Main sets it again once it knows the highlighted app's windows.
                    s.holdOnRelease = false
                    s.enter(.cycling, at: e.now)
                    r.event = .cycleStarted
                    r.note = .cycleStarted
                } else if e.keycode == TapKey.section, command, e.flags.intersection(blocked).isEmpty {
                    // ⌘§ does nothing in macOS, so it's always ours. Main ends the session at once
                    // if the front app has fewer than two windows.
                    r.verdict = .swallow
                    s.swallowedKeys.insert(e.keycode)
                    // It came with ⌘, whatever the last flagsChanged said.
                    s.commandDown = true
                    s.enter(.windows, at: e.now)
                    r.event = .windowsStarted(backwards: e.flags.contains(.maskShift))
                    r.note = .windowsStarted
                }
            case .flagsChanged:
                let wasDown = s.commandDown
                s.commandDown = command
                if wasDown, !command, s.owesCommandRelease {
                    s.owesCommandRelease = false
                    r.note = .owedReleasePaid
                }
            case .keyUp:
                break
            }

        case .cycling:
            if e.kind == .flagsChanged {
                let wasDown = s.commandDown
                s.commandDown = command
                if !wasDown, command {
                    // A fresh ⌘ press means we never saw the release. End safely.
                    r.end = planEnd(&s, .confirm, .missedRelease, now: e.now)
                } else if wasDown, !command {
                    if s.holdOnRelease {
                        r.verdict = .swallow
                        if !s.owesCommandRelease {
                            // After ⌘⇥ again, the Dock still misses the first release, so keep its key.
                            s.commandKeycode = e.keycode == TapKey.rightCommand ? TapKey.rightCommand : TapKey.command
                        }
                        s.owesCommandRelease = true
                        s.commandPressedAgain = false
                        s.enter(.picking, at: e.now)
                        r.event = .pickingStarted
                        r.note = .holdStarted
                        r.startsPicking = true
                    } else {
                        s.owesCommandRelease = false
                        s.enter(.idle, at: e.now)
                        r.event = .cycleEnded
                        r.note = .releasePassed
                    }
                }
                return r
            }
            if !command {
                // ⌘ is physically up, so its release got past us.
                r.end = planEnd(&s, .confirm, .missedRelease, now: e.now)
            } else if e.kind == .keyDown, e.keycode == TapKey.escape {
                s.enter(.idle, at: e.now)
                r.event = .cycleEnded
                r.note = .nativeCancel
            }

        case .picking:
            switch e.kind {
            case .flagsChanged:
                r.verdict = .swallow
                let wasDown = s.commandDown
                s.commandDown = command
                if !wasDown, command {
                    s.commandPressedAgain = true
                } else if wasDown, !command, s.commandPressedAgain {
                    // ⌘ pressed and released with no Tab: a cancel.
                    r.end = planEnd(&s, .cancel, .commandTapped, now: e.now)
                }
            case .keyDown:
                if e.keycode == TapKey.tab, s.commandPressedAgain {
                    // ⌘⇥ again. The Dock still believes ⌘ is held, so it moves its highlight on.
                    // The owed release carries over into Cycling.
                    r.verdict = .passAddingCommand(keycode: s.commandKeycode)
                    s.commandPressedAgain = false
                    // The highlight is about to move off the app it was set for; main sets it
                    // again once AX reports where it went.
                    s.holdOnRelease = false
                    r.note = .backToCycling(keys: s.keys)
                    s.enter(.cycling, at: e.now)
                    r.event = .backToCycling
                    return r
                }
                r.verdict = .swallow
                s.swallowedKeys.insert(e.keycode)
                if !e.autorepeat || e.keycode == TapKey.upArrow || e.keycode == TapKey.downArrow {
                    s.keys += 1
                    r.event = .key(UInt16(truncatingIfNeeded: e.keycode))
                }
            case .keyUp:
                // Only keys whose keyDown went to the Dock get here: the Tab of a ⌘⇥ that was
                // still down when ⌘ was released. Its keyUp goes to the Dock too.
                r.verdict = e.keycode == TapKey.tab ? .passAddingCommand(keycode: s.commandKeycode) : .swallow
            }

        case .windows:
            switch e.kind {
            case .flagsChanged:
                s.commandDown = command
                if !command {
                    // ⌘ released: it passes, as it would anyway, and the highlighted window opens.
                    s.owesCommandRelease = false
                    s.enter(.idle, at: e.now)
                    r.event = .windowsEnded(commit: true)
                    r.note = .windowsReleased
                }
            case .keyDown:
                if !command {
                    // ⌘ is physically up, so its release got past us. Do what the release would
                    // have done, and let this key through to the app.
                    s.enter(.idle, at: e.now)
                    r.event = .windowsEnded(commit: true)
                    r.note = .windowsMissedRelease
                } else if e.keycode == TapKey.tab, e.flags.intersection([.maskControl, .maskAlternate]).isEmpty {
                    // ⌘⇥ from the window switcher opens the app switcher, which ends this one.
                    s.holdOnRelease = false
                    s.enter(.cycling, at: e.now)
                    r.event = .cycleStarted
                    r.note = .windowsToCycling
                } else {
                    // The switcher keeps the keyboard until ⌘ goes up: no ⌘-shortcut reaches the app.
                    r.verdict = .swallow
                    s.swallowedKeys.insert(e.keycode)
                    if e.keycode == TapKey.section {
                        // Held down, § repeats and walks on, like Tab in ⌘⇥.
                        r.event = .windowStep(e.flags.contains(.maskShift) ? -1 : 1)
                    } else if !e.autorepeat || TapKey.arrows.contains(e.keycode) {
                        r.event = .key(UInt16(truncatingIfNeeded: e.keycode))
                    }
                }
            case .keyUp:
                // Keys whose keyDown was swallowed were handled above; the rest were down before
                // the switcher opened, and the app gets their keyUp.
                break
            }
        }
        return r
    }

    /// Decides what an exit posts and moves to Idle. The only place that clears
    /// `owesCommandRelease` on the way to a synthetic release, so each owed release is posted once.
    private static func planEnd(_ s: inout TapState, _ how: HoldEnd, _ reason: TapEndReason, now: UInt64) -> EndPlan? {
        let from = s.phase
        let owed = s.owesCommandRelease
        guard from != .idle || owed else { return nil }
        let keys = s.keys
        let held = from == .picking && now > s.enteredAt ? now - s.enteredAt : 0
        s.owesCommandRelease = false
        s.commandPressedAgain = false
        if from != .idle { s.enter(.idle, at: now) }
        let event: TapEvent? = switch from {
        case .idle: nil
        case .cycling: .cycleEnded
        case .picking: .pickingEnded(reason)
        case .windows: .windowsEnded(commit: false)
        }
        return EndPlan(
            from: from,
            reason: reason,
            // In Idle a native Esc has closed the switcher already, and in Windows the Dock shows
            // none: Esc would reach the front app.
            postEscape: how == .cancel && owed && (from == .cycling || from == .picking),
            postRelease: owed,
            commandKeycode: s.commandKeycode,
            keys: keys,
            held: held,
            message: event.map { TapMessage(event: $0, generation: s.generation) })
    }

    // MARK: Any thread

    /// Ends Picking session `session`, if it's still the one running. Returns whether it did.
    func endHold(_ how: HoldEnd, session: UInt64) -> Bool {
        let plan: EndPlan? = state.withLock { s in
            guard s.phase == .picking, s.generation == session else { return nil }
            return Self.planEnd(&s, how, .requested, now: continuousNanos())
        }
        guard let plan else { return false }
        execute(plan)
        return true
    }

    /// Ends Windows session `session`, if it's still the one running: a pick, a cancel, or an app
    /// with too few windows. Nothing is owed, so nothing is posted. Returns whether it did.
    func endWindows(session: UInt64) -> Bool {
        let ended = state.withLock { s in
            guard s.phase == .windows, s.generation == session else { return false }
            s.enter(.idle, at: continuousNanos())
            return true
        }
        if ended { TapLog.logger.info("Windows → Idle: ended by the controller") }
        return ended
    }

    /// Ends whatever is running and posts what's owed, in any phase. For stopping and for the tap
    /// being turned off.
    func end(_ how: HoldEnd, reason: TapEndReason) {
        let plan = state.withLock { Self.planEnd(&$0, how, reason, now: continuousNanos()) }
        if let plan { execute(plan) }
    }

    /// Before a tap starts or after it was turned off, what we tracked may be stale.
    func resetTracking() {
        let commandDown = CGEventSource.flagsState(.hidSystemState).contains(.maskCommand)
        state.withLock { s in
            s.commandDown = commandDown
            s.commandPressedAgain = false
            s.swallowedKeys.removeAll()
        }
    }

    private func execute(_ plan: EndPlan) {
        if plan.postEscape { SyntheticKeys.postEscapeWithCommand(commandKeycode: plan.commandKeycode) }
        if plan.postRelease { SyntheticKeys.postCommandRelease(keycode: plan.commandKeycode) }
        TapLog.logger.notice("""
            \(plan.from.rawValue, privacy: .public) → Idle (\(plan.reason.rawValue, privacy: .public)) \
            after \(plan.keys, privacy: .public) keys, \(Double(plan.held) / 1e9, format: .fixed(precision: 1), privacy: .public) s; \
            posted Esc=\(plan.postEscape, privacy: .public) ⌘ release=\(plan.postRelease, privacy: .public)
            """)
        if let message = plan.message { send(message) }
    }

    private func scheduleTimeout(_ generation: UInt64, after nanos: UInt64) {
        // Wall-clock, so time asleep counts: Picking running when the Mac sleeps ends on wake.
        timeoutQueue.asyncAfter(wallDeadline: .now() + .nanoseconds(Int(clamping: nanos))) { [self] in
            checkTimeout(generation)
        }
    }

    /// One check per Picking session is pending at a time. Keys don't reschedule it; it looks at
    /// the last key's time when it fires and waits out the rest if there was input meanwhile.
    private func checkTimeout(_ generation: UInt64) {
        let check: TimeoutCheck = state.withLock { s in
            guard s.phase == .picking, s.generation == generation else { return .stale }
            let now = continuousNanos()
            let quiet = now > s.lastKeyAt ? now - s.lastKeyAt : 0
            if quiet < Self.noInputTimeout { return .wait(Self.noInputTimeout - quiet) }
            return .end(Self.planEnd(&s, .cancel, .timeout, now: now))
        }
        switch check {
        case .stale:
            break
        case .wait(let remaining):
            scheduleTimeout(generation, after: remaining)
        case .end(let plan):
            if let plan { execute(plan) }
        }
    }
}
