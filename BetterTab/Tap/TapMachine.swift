import CoreGraphics
import Foundation
import Synchronization
import os

// Everything in this file runs on the tap thread or the main thread, so it's all nonisolated.

nonisolated enum TapLog {
    static let logger = Logger(subsystem: "com.luksanss.BetterTab", category: "tap")
}

/// Virtual key codes (Carbon `kVK_*`), kept here so the tap never touches Carbon.
nonisolated enum TapKey {
    static let tab: Int64 = 48
    static let escape: Int64 = 53
    static let leftArrow: Int64 = 123
    static let rightArrow: Int64 = 124
    static let downArrow: Int64 = 125
    static let upArrow: Int64 = 126
    /// `kVK_ISO_Section`: the § key, above Tab on ISO keyboards. ANSI keyboards have no such key.
    static let section: Int64 = 10
    /// `kVK_ANSI_Grave`: the ` key, above Tab on ANSI keyboards and left of Z on ISO ones.
    static let grave: Int64 = 50

    static let arrows: Set<Int64> = [leftArrow, rightArrow, downArrow, upArrow]
}

nonisolated enum TapPhase: String, Sendable {
    case idle = "Idle"
    /// The native ⌘⇥ switcher is up. Everything passes; the controller draws the stack edges.
    case cycling = "Cycling"
    /// The ⌘§ window switcher. § and the keys pressed meanwhile are swallowed; ⌘ passes both ways.
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
    /// The key above Tab on the keyboard it came from (`KeyAboveTab`), written § below.
    let aboveTab: Bool
    let flags: CGEventFlags
    let autorepeat: Bool
}

nonisolated enum TapVerdict: Sendable {
    case pass, swallow
}

nonisolated struct TapState {
    var phase = TapPhase.idle
    /// Goes up on every phase change, so a stale message or `endWindows` can tell it's stale.
    var generation: UInt64 = 0
    /// Physical ⌘, as last seen in a flagsChanged event.
    var commandDown = false
    /// Keys whose keyDown was swallowed: their keyUp and autorepeats are swallowed too.
    var swallowedKeys: Set<Int64> = []

    mutating func enter(_ next: TapPhase) {
        phase = next
        generation &+= 1
    }
}

/// Log lines decided under the lock and written after it's released. States only.
nonisolated enum TapNote: Sendable {
    case cycleStarted
    case releasePassed
    case nativeCancel
    case cycleMissedRelease
    case windowsStarted
    case windowsReleased
    case windowsMissedRelease
    case windowsToCycling

    func log() {
        let logger = TapLog.logger
        switch self {
        case .cycleStarted:
            logger.info("Idle → Cycling: ⌘⇥ passed")
        case .releasePassed:
            logger.info("Cycling → Idle: ⌘ release passed (native switch)")
        case .nativeCancel:
            logger.info("Cycling → Idle: Esc passed (native cancel)")
        case .cycleMissedRelease:
            logger.info("Cycling → Idle: ⌘ is up, so its release got past us")
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
    var note: TapNote?
}

/// The product tap's state machine: Idle, Cycling while the native ⌘⇥ switcher is up, and Windows
/// for ⌘§. `process` runs on the tap thread; everything else may run on any thread. All state sits
/// behind one lock, and nothing slow happens while it's held: logging and messages to main happen
/// after it's released. ⌘ is never swallowed, so no exit has anything to post.
nonisolated final class TapMachine: Sendable {
    private let state = Mutex(TapState())
    private let send: @Sendable (TapMessage) -> Void

    init(send: @escaping @Sendable (TapMessage) -> Void) {
        self.send = send
    }

    // MARK: Tap thread

    func process(_ input: TapInput) -> TapVerdict {
        let result = state.withLock { s in
            var result = Self.step(&s, input)
            result.generation = s.generation
            return result
        }
        result.note?.log()
        if let event = result.event { send(TapMessage(event: event, generation: result.generation)) }
        return result.verdict
    }

    /// macOS turned the tap off. Events went past it meanwhile, so what it tracked can't be trusted.
    func tapWasDisabled() {
        end(reason: .tapDisabled)
        resetTracking()
    }

    private static func step(_ s: inout TapState, _ e: TapInput) -> StepResult {
        var r = StepResult()
        let command = e.flags.contains(.maskCommand)
        let blocked: CGEventFlags = [.maskControl, .maskAlternate]

        if e.kind == .keyUp, s.swallowedKeys.remove(e.keycode) != nil {
            r.verdict = .swallow
            return r
        }
        if e.kind == .keyDown, s.phase != .windows, s.swallowedKeys.contains(e.keycode) {
            // A key still held from a Windows session that has ended: keep its repeats away from
            // the app.
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
                if e.keycode == TapKey.tab, command, e.flags.intersection(blocked).isEmpty {
                    // It came with ⌘, whatever the last flagsChanged said, so its release ends it.
                    s.commandDown = true
                    s.enter(.cycling)
                    r.event = .cycleStarted
                    r.note = .cycleStarted
                } else if e.aboveTab, command, e.flags.intersection(blocked).isEmpty {
                    // ⌘§ does nothing in macOS, so it's always ours. Main ends the session at once
                    // if the front app has fewer than two windows.
                    r.verdict = .swallow
                    s.swallowedKeys.insert(e.keycode)
                    // It came with ⌘, whatever the last flagsChanged said.
                    s.commandDown = true
                    s.enter(.windows)
                    r.event = .windowsStarted(backwards: e.flags.contains(.maskShift))
                    r.note = .windowsStarted
                }
            case .flagsChanged:
                s.commandDown = command
            case .keyUp:
                break
            }

        case .cycling:
            if e.kind == .flagsChanged {
                let wasDown = s.commandDown
                s.commandDown = command
                if wasDown != command {
                    // A ⌘ release ends the native switch. A fresh ⌘ press means we never saw the
                    // release.
                    s.enter(.idle)
                    r.event = .cycleEnded
                    r.note = command ? .cycleMissedRelease : .releasePassed
                }
                return r
            }
            if !command {
                // ⌘ is physically up, so its release got past us.
                s.enter(.idle)
                r.event = .cycleEnded
                r.note = .cycleMissedRelease
            } else if e.kind == .keyDown, e.keycode == TapKey.escape {
                s.enter(.idle)
                r.event = .cycleEnded
                r.note = .nativeCancel
            }

        case .windows:
            switch e.kind {
            case .flagsChanged:
                s.commandDown = command
                if !command {
                    // ⌘ released: it passes, as it would anyway, and the highlighted window opens.
                    s.enter(.idle)
                    r.event = .windowsEnded(commit: true)
                    r.note = .windowsReleased
                }
            case .keyDown:
                if !command {
                    // ⌘ is physically up, so its release got past us. Do what the release would
                    // have done, and let this key through to the app.
                    s.enter(.idle)
                    r.event = .windowsEnded(commit: true)
                    r.note = .windowsMissedRelease
                } else if e.keycode == TapKey.tab, e.flags.intersection(blocked).isEmpty {
                    // ⌘⇥ from the window switcher opens the app switcher, which ends this one.
                    s.enter(.cycling)
                    r.event = .cycleStarted
                    r.note = .windowsToCycling
                } else {
                    // The switcher keeps the keyboard until ⌘ goes up: no ⌘-shortcut reaches the app.
                    r.verdict = .swallow
                    s.swallowedKeys.insert(e.keycode)
                    if e.aboveTab {
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

    // MARK: Any thread

    /// Ends Windows session `session`, if it's still the one running: a pick, a cancel, or an app
    /// with too few windows. Returns whether it did.
    func endWindows(session: UInt64) -> Bool {
        let ended = state.withLock { s in
            guard s.phase == .windows, s.generation == session else { return false }
            s.enter(.idle)
            return true
        }
        if ended { TapLog.logger.info("Windows → Idle: ended by the controller") }
        return ended
    }

    /// Ends whatever is running, in any phase. For stopping and for the tap being turned off.
    func end(reason: TapEndReason) {
        let ended = state.withLock { s -> (from: TapPhase, message: TapMessage)? in
            let from = s.phase
            guard from != .idle else { return nil }
            s.enter(.idle)
            let event: TapEvent = from == .windows ? .windowsEnded(commit: false) : .cycleEnded
            return (from, TapMessage(event: event, generation: s.generation))
        }
        guard let ended else { return }
        TapLog.logger.notice("\(ended.from.rawValue, privacy: .public) → Idle (\(reason.rawValue, privacy: .public))")
        send(ended.message)
    }

    /// Before a tap starts or after it was turned off, what we tracked may be stale.
    func resetTracking() {
        let commandDown = CGEventSource.flagsState(.hidSystemState).contains(.maskCommand)
        state.withLock { s in
            s.commandDown = commandDown
            s.swallowedKeys.removeAll()
        }
    }
}
