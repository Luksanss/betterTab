import CoreFoundation
import CoreGraphics
import Dispatch
import Foundation
import Synchronization
import os

/// What the tap tells the controller. Delivered on the main queue.
nonisolated enum TapEvent: Sendable {
    /// ⌘⇥ was pressed and passed on: the native switcher is opening.
    case cycleStarted
    /// Cycling ended: ⌘ released, a native Esc, a missed release, or the tap stopping.
    case cycleEnded
    /// A keyDown during Windows, swallowed. Autorepeats come only for the arrows.
    case key(UInt16)
    /// ⌘§ was pressed and swallowed: the window switcher for the front app opens. Shift steps
    /// backwards, as in ⌘⇧⇥.
    case windowsStarted(backwards: Bool)
    /// § again during Windows, swallowed: move the highlight by this much. Repeats while held.
    case windowStep(Int)
    /// Windows ended. `commit` when ⌘ was released, so the highlighted window opens; false when
    /// the tap stopped or was turned off. Not sent when the controller ended it with `endWindows`.
    case windowsEnded(commit: Bool)
}

nonisolated struct TapMessage: Sendable {
    let event: TapEvent
    /// The tap's generation once the event happened. Every phase change raises it, so a late
    /// message can be told apart. During Windows it names the session to pass to `endWindows`.
    let generation: UInt64
}

nonisolated enum TapEndReason: String, Sendable {
    /// macOS turned the tap off, so events may have gone past it.
    case tapDisabled
    /// `stop()`: quit, or the permission going away.
    case stopped
}

/// The product key tap. It watches ⌘⇥ pass by, so the stack edges can be drawn over the native
/// switcher, and runs ⌘§, swallowing § and the keys pressed while its switcher is open. It never
/// swallows ⌘, so macOS is never owed a ⌘ release. Sendable, so any thread can stop it.
nonisolated final class KeyTap: Sendable {
    private let machine: TapMachine
    private let aboveTab: KeyAboveTab
    private let current = Mutex<TapThread?>(nil)

    /// Main actor, for `KeyAboveTab`.
    @MainActor init(deliver: @escaping @MainActor @Sendable (TapMessage) -> Void) {
        aboveTab = KeyAboveTab()
        machine = TapMachine { message in
            DispatchQueue.main.async { MainActor.assumeIsolated { deliver(message) } }
        }
    }

    /// Creates the tap on its own thread, unless one exists already.
    func start() {
        let tap: TapThread? = current.withLock { current in
            guard current == nil else { return nil }
            let tap = TapThread(machine: machine, aboveTab: aboveTab)
            current = tap
            return tap
        }
        guard let tap else { return }
        machine.resetTracking()
        tap.start()
    }

    /// Any thread. The tap goes off first, so nothing new can start, and then whatever was running
    /// ends.
    func stop() {
        let old = current.withLock { current -> TapThread? in
            defer { current = nil }
            return current
        }
        old?.stop()
        machine.end(reason: .stopped)
    }

    /// Main actor. Ends Windows session `session` (the generation of its `.windowsStarted`). False
    /// once that session is over.
    @discardableResult
    func endWindows(session: UInt64) -> Bool {
        machine.endWindows(session: session)
    }
}

// CFMachPort and CFRunLoop are safe to enable, disable, stop and wake from any thread.
nonisolated private struct PortRef: @unchecked Sendable { let port: CFMachPort }
nonisolated private struct LoopRef: @unchecked Sendable { let loop: CFRunLoop }

nonisolated private struct LoopControl: Sendable {
    var loop: LoopRef?
    var stopRequested = false
}

/// The C callback: no captures, no isolation. `refcon` is the `TapThread` that owns the tap.
nonisolated private func keyTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<TapThread>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
}

/// One session-level event tap on a dedicated thread with its own run loop, so AX work, logging
/// or a busy main thread can never delay the callback.
nonisolated private final class TapThread: Sendable {
    private let machine: TapMachine
    private let aboveTab: KeyAboveTab
    private let port = Mutex<PortRef?>(nil)
    private let control = Mutex(LoopControl())
    private let finished = DispatchSemaphore(value: 0)

    private static let mask: CGEventMask = [CGEventType.keyDown, .keyUp, .flagsChanged]
        .reduce(0) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }

    init(machine: TapMachine, aboveTab: KeyAboveTab) {
        self.machine = machine
        self.aboveTab = aboveTab
    }

    func start() {
        // The thread's closure keeps `self` alive for as long as the tap exists.
        let thread = Thread { [self] in run() }
        thread.name = "BetterTab.KeyTap"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    private func run() {
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: Self.mask, callback: keyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            TapLog.logger.error("tapCreate returned nil: no key tap, so no stack edges and no ⌘§")
            finished.signal()
            return
        }
        let runLoop: CFRunLoop = CFRunLoopGetCurrent()
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        CFRunLoopAddSource(runLoop, source, .commonModes)
        port.withLock { $0 = PortRef(port: created) }
        control.withLock { $0.loop = LoopRef(loop: runLoop) }
        // Taps are enabled when created; enabling here again could race with stop().
        TapLog.logger.notice("Key tap running on its own thread")

        // No timeout, so nothing wakes this thread while idle (spec: no timers, no polling).
        // `stop()` ends the run with a block queued on this run loop, which waits until the run
        // starts, so it can't be missed the way a bare CFRunLoopStop issued just before it can.
        while !control.withLock({ $0.stopRequested }) {
            if CFRunLoopRunInMode(.defaultMode, 1.0e10, false) == .finished {
                // The tap's port went away underneath us (macOS can invalidate it), so the run
                // loop has no source left and would return at once, forever. End whatever was
                // running.
                TapLog.logger.error("Key tap's port is gone; the tap has stopped")
                machine.end(reason: .tapDisabled)
                break
            }
        }

        CGEvent.tapEnable(tap: created, enable: false)
        CFRunLoopRemoveSource(runLoop, source, .commonModes)
        CFMachPortInvalidate(created)
        port.withLock { $0 = nil }
        TapLog.logger.notice("Key tap stopped")
        finished.signal()
    }

    /// Any thread. Turns the tap off at once, then waits briefly for its thread to finish.
    func stop() {
        // Flag the stop first, so a disabled event arriving meanwhile can't turn the tap back on.
        let loop = control.withLock { control -> LoopRef? in
            control.stopRequested = true
            return control.loop
        }
        port.withLock { ref in
            if let ref { CGEvent.tapEnable(tap: ref.port, enable: false) }
        }
        if let loop {
            CFRunLoopPerformBlock(loop.loop, CFRunLoopMode.defaultMode.rawValue) {
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
            CFRunLoopWakeUp(loop.loop)
        }
        if finished.wait(timeout: .now() + 2) == .timedOut {
            TapLog.logger.error("Key tap thread didn't finish within 2 s (the tap is off)")
        }
    }

    /// Tap thread only. Keep it tiny: copy a few fields, one short lock, return.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // A tap being stopped must stay off.
            if !control.withLock({ $0.stopRequested }) {
                port.withLock { ref in
                    if let ref { CGEvent.tapEnable(tap: ref.port, enable: true) }
                }
            }
            TapLog.logger.error("""
                Key tap disabled by \(type == .tapDisabledByTimeout ? "timeout" : "user input", privacy: .public); \
                re-enabled it unless it's being stopped
                """)
            machine.tapWasDisabled()
            return Unmanaged.passUnretained(event)
        }
        guard let kind = TapInputKind(type) else { return Unmanaged.passUnretained(event) }

        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let keyboardType = event.getIntegerValueField(.keyboardEventKeyboardType)
        let input = TapInput(
            kind: kind,
            keycode: keycode,
            aboveTab: kind != .flagsChanged
                && aboveTab.matches(keycode: keycode, keyboardType: keyboardType),
            flags: event.flags,
            autorepeat: kind == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0)

        switch machine.process(input) {
        case .pass:
            return Unmanaged.passUnretained(event)
        case .swallow:
            return nil
        }
    }
}
