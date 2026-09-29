import CoreGraphics
import Dispatch
import Synchronization
import os

nonisolated enum Phase: String, Sendable {
    case idle = "Idle"
    case cycling = "Cycling"
    case holding = "Holding"
}

nonisolated struct Snapshot: Sendable {
    let phase: Phase
    /// Goes up on every phase change, so a stale timer or probe can tell it's stale.
    let generation: UInt64
    let enteredAt: UInt64
}

nonisolated struct HoldStats: Sendable {
    var mouseMoves = 0
    var mouseDowns = 0
    var mouseUps = 0
    var swallowedKeyDowns = 0
    var tabsPassed = 0
    var loggedFirstMove = false

    var summary: String {
        "mouseMoves=\(mouseMoves) mouseDowns=\(mouseDowns) mouseUps=\(mouseUps) "
            + "swallowedKeyDowns=\(swallowedKeyDowns) tabsPassed=\(tabsPassed)"
    }
}

nonisolated enum EventKind: Sendable {
    case keyDown, keyUp, flagsChanged, mouseMoved, mouseDown, mouseUp, other

    init(_ type: CGEventType) {
        switch type {
        case .keyDown: self = .keyDown
        case .keyUp: self = .keyUp
        case .flagsChanged: self = .flagsChanged
        case .mouseMoved: self = .mouseMoved
        case .leftMouseDown: self = .mouseDown
        case .leftMouseUp: self = .mouseUp
        default: self = .other
        }
    }

    var isKey: Bool { self == .keyDown || self == .keyUp || self == .flagsChanged }
}

/// Only plain values, copied out of the CGEvent before the lock is taken.
nonisolated struct TapInput: Sendable {
    let kind: EventKind
    let keycode: Int64
    let flags: CGEventFlags
    let autorepeat: Bool
    let now: UInt64
}

nonisolated enum Verdict: Sendable {
    /// `keycode` is the ⌘ key the Dock believes is held; its device bit goes on too.
    case pass, passAddingCommand(keycode: Int64), swallow
}

nonisolated struct MachineState {
    var phase = Phase.idle
    var generation: UInt64 = 0
    var enteredAt: UInt64 = 0
    var armed = true
    /// True from the moment a ⌘ release is swallowed until the Dock has been given one.
    var owesCommandRelease = false
    /// The ⌘ key (left 55, right 54) whose release became owed. The synthetic release replays it.
    var commandKeycode = KeyCode.command
    /// Physical ⌘, as last seen in a flagsChanged event (swallowed or not).
    var commandDown = false
    /// ⌘ was physically pressed again during a hold; the press was swallowed.
    var commandPressedAgain = false
    /// Keys whose keyDown was swallowed: their keyUp and autorepeats are swallowed too.
    var swallowedKeys: Set<Int64> = []
    var stats = HoldStats()

    var snapshot: Snapshot { Snapshot(phase: phase, generation: generation, enteredAt: enteredAt) }

    mutating func enter(_ next: Phase, at now: UInt64) {
        phase = next
        generation &+= 1
        enteredAt = now
        if next == .holding { stats = HoldStats() }
    }
}

nonisolated struct StepResult: Sendable {
    var verdict = Verdict.pass
    var notes: [Note] = []
    var end: (reason: String, cancel: Bool)?
    var holdStarted: UInt64?
    var tabPassedInHold: UInt64?
    var changed: Snapshot?
}

nonisolated struct EndPlan: Sendable {
    let from: Phase
    let postEscape: Bool
    let postRelease: Bool
    let commandKeycode: Int64
    let held: UInt64
    let stats: HoldStats
    var snapshot: Snapshot?
}

/// The test-0 state machine. `process` runs on the tap thread; everything else may run on any
/// thread. All state sits behind one lock, and nothing slow happens while it's held: logging and
/// posting happen after it's released.
nonisolated final class HoldMachine: Sendable {
    private let state = Mutex(MachineState())
    private let notify: @Sendable (Snapshot) -> Void
    private let tabPassed: @Sendable (UInt64) -> Void
    private let timeoutQueue = DispatchQueue(label: "com.luksanss.BetterTab.Experiment.timeout")

    init(notify: @escaping @Sendable (Snapshot) -> Void, tabPassed: @escaping @Sendable (UInt64) -> Void) {
        self.notify = notify
        self.tabPassed = tabPassed
    }

    // MARK: Tap thread

    func process(_ input: TapInput) -> Verdict {
        let result = state.withLock { Self.step(&$0, input) }
        for note in result.notes { note.log() }
        if let generation = result.holdStarted { scheduleTimeout(for: generation) }
        if let snapshot = result.changed { notify(snapshot) }
        if let generation = result.tabPassedInHold { tabPassed(generation) }
        if let end = result.end { releaseCommandIfOwed(reason: end.reason, cancel: end.cancel) }
        return result.verdict
    }

    private static func step(_ s: inout MachineState, _ e: TapInput) -> StepResult {
        var r = StepResult()
        let command = e.flags.contains(.maskCommand)

        if e.kind == .keyUp, s.swallowedKeys.remove(e.keycode) != nil {
            r.verdict = .swallow
            return r
        }
        if e.kind == .keyDown, s.phase != .holding, s.swallowedKeys.contains(e.keycode) {
            // A key still held from a hold that has ended, or gone back to cycling: keep its
            // repeats away from the Dock and the app.
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
                if e.keycode == KeyCode.tab, command, e.flags.intersection(blocked).isEmpty {
                    s.enter(.cycling, at: e.now)
                    r.notes.append(.cyclingStarted(flags: e.flags.rawValue))
                    r.changed = s.snapshot
                }
            case .flagsChanged:
                let wasDown = s.commandDown
                s.commandDown = command
                if wasDown, !command, s.owesCommandRelease {
                    s.owesCommandRelease = false
                    r.notes.append(.realReleasePassed)
                }
            default:
                break
            }

        case .cycling:
            if e.kind == .flagsChanged {
                let wasDown = s.commandDown
                s.commandDown = command
                if !wasDown, command {
                    // A fresh ⌘ press means we never saw the release. End safely.
                    r.end = ("missed ⌘ release (new ⌘ press while cycling)", false)
                } else if wasDown, !command {
                    if s.armed {
                        r.verdict = .swallow
                        if !s.owesCommandRelease {
                            // After ⌘⇥ again, the Dock still misses the first release, so keep its key.
                            s.commandKeycode = e.keycode == KeyCode.rightCommand ? KeyCode.rightCommand : KeyCode.command
                        }
                        s.owesCommandRelease = true
                        s.commandPressedAgain = false
                        s.enter(.holding, at: e.now)
                        r.notes.append(.holdStarted(uptime: e.now, flags: e.flags.rawValue))
                        r.holdStarted = s.generation
                        r.changed = s.snapshot
                    } else {
                        s.owesCommandRelease = false
                        s.enter(.idle, at: e.now)
                        r.notes.append(.releasedNotArmed)
                        r.changed = s.snapshot
                    }
                }
                return r
            }
            if !command, e.kind == .keyDown || e.kind == .keyUp {
                // ⌘ is physically up, so its release got past us.
                r.end = ("missed ⌘ release (event without ⌘ while cycling)", false)
            } else if e.kind == .keyDown, e.keycode == KeyCode.escape {
                s.enter(.idle, at: e.now)
                r.notes.append(.nativeCancel)
                r.changed = s.snapshot
            }

        case .holding:
            switch e.kind {
            case .flagsChanged:
                r.verdict = .swallow
                let wasDown = s.commandDown
                s.commandDown = command
                if !wasDown, command {
                    s.commandPressedAgain = true
                    r.notes.append(.swallowedCommandPress)
                } else if wasDown, !command, s.commandPressedAgain {
                    // ⌘ pressed and released with no Tab: end the hold the way a dead harness would.
                    s.commandPressedAgain = false
                    r.end = ("⌘ pressed and released again", false)
                } else {
                    r.notes.append(.swallowedFlags(flags: e.flags.rawValue))
                }
            case .keyDown:
                if e.keycode == KeyCode.tab {
                    r.verdict = .passAddingCommand(keycode: s.commandKeycode)
                    if s.commandPressedAgain {
                        s.commandPressedAgain = false
                        let held = e.now &- s.enteredAt
                        let stats = s.stats
                        s.enter(.cycling, at: e.now)
                        r.notes.append(.backToCycling(held: held, stats: stats))
                        r.changed = s.snapshot
                    } else {
                        s.stats.tabsPassed += 1
                        r.notes.append(.tabPassed(flags: e.flags.rawValue))
                        r.tabPassedInHold = s.generation
                    }
                    return r
                }
                r.verdict = .swallow
                s.swallowedKeys.insert(e.keycode)
                switch e.keycode {
                case KeyCode.returnKey, KeyCode.keypadEnter:
                    r.end = ("Return", false)
                case KeyCode.escape:
                    r.end = ("Esc", true)
                default:
                    s.stats.swallowedKeyDowns += 1
                    r.notes.append(.swallowedKey(code: e.keycode, autorepeat: e.autorepeat))
                }
            case .keyUp:
                r.verdict = e.keycode == KeyCode.tab ? .passAddingCommand(keycode: s.commandKeycode) : .swallow
            case .mouseMoved:
                s.stats.mouseMoves += 1
                if !s.stats.loggedFirstMove {
                    s.stats.loggedFirstMove = true
                    r.notes.append(.mouseDuringHold(what: "first mouseMoved", flags: e.flags.rawValue))
                }
            case .mouseDown:
                s.stats.mouseDowns += 1
                r.notes.append(.mouseDuringHold(what: "leftMouseDown", flags: e.flags.rawValue))
            case .mouseUp:
                s.stats.mouseUps += 1
                r.notes.append(.mouseDuringHold(what: "leftMouseUp", flags: e.flags.rawValue))
            case .other:
                break
            }
        }
        return r
    }

    // MARK: Any thread

    /// The one place that posts the synthetic ⌘ release. Every way out of a hold comes through here.
    /// It's idempotent: only the call that finds the release still owed posts it. `cancel` posts Esc
    /// (with ⌘) first. `onlyHold` makes the call a no-op unless that exact hold is still running.
    func releaseCommandIfOwed(reason: String, cancel: Bool, onlyHold generation: UInt64? = nil) {
        let plan: EndPlan? = state.withLock { s in
            if let generation, s.phase != .holding || s.generation != generation { return nil }
            guard s.phase != .idle || s.owesCommandRelease else { return nil }
            let now = uptimeNanos()
            var plan = EndPlan(
                from: s.phase,
                // In Idle a native Esc has already closed the switcher; Esc would reach the front app.
                postEscape: cancel && s.owesCommandRelease && s.phase != .idle,
                postRelease: s.owesCommandRelease,
                commandKeycode: s.commandKeycode,
                held: s.phase == .holding ? now &- s.enteredAt : 0,
                stats: s.stats)
            s.owesCommandRelease = false
            s.commandPressedAgain = false
            if s.phase != .idle {
                s.enter(.idle, at: now)
                plan.snapshot = s.snapshot
            }
            return plan
        }
        guard let plan else { return }

        if plan.postEscape { Synthetic.postEscapeWithCommand(reason: reason, commandKeycode: plan.commandKeycode) }
        if plan.postRelease { Synthetic.postCommandRelease(reason: reason, keycode: plan.commandKeycode) }
        if plan.from == .holding {
            Log.state.notice("""
                HOLD end (reason: \(reason, privacy: .public)) after \(seconds(plan.held), format: .fixed(precision: 2), privacy: .public) s: \
                \(plan.stats.summary, privacy: .public)
                """)
        }
        Log.state.notice("""
            STATE \(plan.from.rawValue, privacy: .public) → Idle (reason: \(reason, privacy: .public)); \
            posted Esc=\(plan.postEscape, privacy: .public) ⌘release=\(plan.postRelease, privacy: .public)
            """)
        if let snapshot = plan.snapshot { notify(snapshot) }
    }

    func setArmed(_ armed: Bool) {
        let heldGeneration: UInt64? = state.withLock { s in
            s.armed = armed
            return !armed && s.phase == .holding ? s.generation : nil
        }
        Log.state.notice("ARMED hold armed=\(armed, privacy: .public)")
        if let heldGeneration {
            releaseCommandIfOwed(reason: "disarmed during a hold", cancel: true, onlyHold: heldGeneration)
        }
    }

    func isCurrent(_ generation: UInt64) -> Bool {
        state.withLock { $0.generation == generation }
    }

    /// Before a tap starts or after it was disabled, what we tracked may be stale.
    func resetTracking() {
        let commandDown = CGEventSource.flagsState(.hidSystemState).contains(.maskCommand)
        state.withLock { s in
            s.commandDown = commandDown
            s.commandPressedAgain = false
            s.swallowedKeys.removeAll()
        }
    }

    private func scheduleTimeout(for generation: UInt64) {
        // Wall-clock, so time asleep counts: a hold running when the Mac sleeps ends on wake.
        timeoutQueue.asyncAfter(wallDeadline: .now() + Timing.holdSafetyTimeout) { [self] in
            releaseCommandIfOwed(
                reason: "\(Int(Timing.holdSafetyTimeout)) s safety timeout", cancel: true, onlyHold: generation)
        }
    }
}

/// Log lines decided under the lock and written after it's released.
nonisolated enum Note: Sendable {
    case cyclingStarted(flags: UInt64)
    case holdStarted(uptime: UInt64, flags: UInt64)
    case releasedNotArmed
    case nativeCancel
    case realReleasePassed
    case swallowedKey(code: Int64, autorepeat: Bool)
    case swallowedFlags(flags: UInt64)
    case swallowedCommandPress
    case tabPassed(flags: UInt64)
    case backToCycling(held: UInt64, stats: HoldStats)
    case mouseDuringHold(what: String, flags: UInt64)

    func log() {
        switch self {
        case .cyclingStarted(let flags):
            Log.state.notice("STATE Idle → Cycling: ⌘⇥ keyDown passed through (flags=\(hex(flags), privacy: .public))")
        case .holdStarted(let uptime, let flags):
            Log.state.notice("""
                STATE Cycling → Holding: ⌘ release SWALLOWED at uptime \(seconds(uptime), format: .fixed(precision: 3), privacy: .public) s \
                (flags=\(hex(flags), privacy: .public))
                """)
            Log.state.notice("HOLD start")
        case .releasedNotArmed:
            Log.state.notice("STATE Cycling → Idle: ⌘ release passed through (hold not armed)")
        case .nativeCancel:
            Log.state.notice("STATE Cycling → Idle: Esc passed through (native cancel)")
        case .realReleasePassed:
            Log.state.notice("STATE a physical ⌘ release passed through; the Dock has a real release")
        case .swallowedKey(let code, let autorepeat):
            Log.state.notice("SWALLOW keyDown keycode=\(code, privacy: .private)\(autorepeat ? " (autorepeat)" : "", privacy: .public) during hold")
        case .swallowedFlags(let flags):
            Log.state.notice("SWALLOW flagsChanged flags=\(hex(flags), privacy: .public) during hold")
        case .swallowedCommandPress:
            Log.state.notice("SWALLOW ⌘ pressed again during hold (Tab next goes back to Cycling; releasing ⌘ ends the hold)")
        case .tabPassed(let flags):
            Log.state.notice("PASS Tab keyDown with ⌘ added during hold (physical flags=\(hex(flags), privacy: .public))")
        case .backToCycling(let held, let stats):
            Log.state.notice("""
                HOLD end (reason: ⌘⇥ again) after \(seconds(held), format: .fixed(precision: 2), privacy: .public) s: \
                \(stats.summary, privacy: .public)
                """)
            Log.state.notice("STATE Holding → Cycling: ⌘ pressed again, then Tab passed through as ⌘⇥")
        case .mouseDuringHold(let what, let flags):
            Log.state.notice("MOUSE \(what, privacy: .public) during hold, passed through (flags=\(hex(flags), privacy: .public))")
        }
    }
}
