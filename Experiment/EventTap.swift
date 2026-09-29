import CoreFoundation
import CoreGraphics
import Dispatch
import Foundation
import Synchronization
import os

nonisolated enum TapLocation: String, Sendable {
    case session, hid

    var cgLocation: CGEventTapLocation { self == .session ? .cgSessionEventTap : .cghidEventTap }
}

// CFMachPort and CFRunLoop are safe to enable, disable, stop and wake from any thread.
nonisolated struct PortRef: @unchecked Sendable { let port: CFMachPort }
nonisolated struct LoopRef: @unchecked Sendable { let loop: CFRunLoop }

nonisolated struct LoopControl: Sendable {
    var loop: LoopRef?
    var stopRequested = false
}

/// The C callback: no captures, no isolation. `refcon` is the `EventTap` that owns the tap.
nonisolated private func tapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
}

/// One event tap on a dedicated thread with its own run loop, so AX work, logging or the main
/// thread can never delay the callback.
nonisolated final class EventTap: Sendable {
    let location: TapLocation
    private let machine: HoldMachine
    private let onResult: @Sendable (TapLocation, Bool) -> Void
    private let port = Mutex<PortRef?>(nil)
    private let control = Mutex(LoopControl())
    private let finished = DispatchSemaphore(value: 0)

    private static let mask: CGEventMask = [
        CGEventType.keyDown, .keyUp, .flagsChanged, .mouseMoved, .leftMouseDown, .leftMouseUp,
    ].reduce(0) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }

    init(location: TapLocation, machine: HoldMachine, onResult: @escaping @Sendable (TapLocation, Bool) -> Void) {
        self.location = location
        self.machine = machine
        self.onResult = onResult
    }

    func start() {
        // The thread's closure keeps `self` alive for as long as the tap exists.
        let thread = Thread { [self] in run() }
        thread.name = "BetterTab.Experiment.EventTap"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    private func run() {
        Permissions.log("before tapCreate(\(location.rawValue))")
        guard let created = CGEvent.tapCreate(
            tap: location.cgLocation, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: Self.mask, callback: tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            Log.tap.error("TAP tapCreate(\(self.location.rawValue, privacy: .public)) returned nil: NO tap")
            onResult(location, false)
            finished.signal()
            return
        }
        let runLoop: CFRunLoop = CFRunLoopGetCurrent()
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        CFRunLoopAddSource(runLoop, source, .commonModes)
        port.withLock { $0 = PortRef(port: created) }
        control.withLock { $0.loop = LoopRef(loop: runLoop) }
        // Taps are enabled when created; enabling here again could race with stop().
        Log.tap.notice("TAP tapCreate(\(self.location.rawValue, privacy: .public)) returned a tap; running on its own thread")
        onResult(location, true)

        // The timeout only bounds how long a missed CFRunLoopStop can delay shutdown.
        while !control.withLock({ $0.stopRequested }) {
            _ = CFRunLoopRunInMode(.defaultMode, 1, false)
        }

        CGEvent.tapEnable(tap: created, enable: false)
        CFRunLoopRemoveSource(runLoop, source, .commonModes)
        CFMachPortInvalidate(created)
        port.withLock { $0 = nil }
        Log.tap.notice("TAP \(self.location.rawValue, privacy: .public) stopped")
        finished.signal()
    }

    /// Any thread. Turns the tap off at once, then waits briefly for its thread to finish.
    func stop() {
        // Flag the stop first, so a disabled event arriving meanwhile can't turn the tap back on.
        let loop = control.withLock { c -> LoopRef? in
            c.stopRequested = true
            return c.loop
        }
        port.withLock { ref in
            if let ref { CGEvent.tapEnable(tap: ref.port, enable: false) }
        }
        if let loop {
            CFRunLoopStop(loop.loop)
            CFRunLoopWakeUp(loop.loop)
        }
        if finished.wait(timeout: .now() + 2) == .timedOut {
            Log.tap.error("TAP \(self.location.rawValue, privacy: .public) thread did not finish within 2 s (tap is disabled)")
        }
    }

    /// Tap thread only. Keep it tiny: copy a few fields, one short lock, return.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let why = type == .tapDisabledByTimeout ? "timeout" : "user input"
            // A tap being replaced must stay off, or two taps would both act on each event.
            if !control.withLock({ $0.stopRequested }) {
                port.withLock { ref in
                    if let ref { CGEvent.tapEnable(tap: ref.port, enable: true) }
                }
            }
            Log.tap.error("TAP disabled by \(why, privacy: .public); re-enabled it unless it's being stopped")
            // A hold can't be trusted across a gap in which events went past us.
            machine.releaseCommandIfOwed(reason: "tap disabled by \(why)", cancel: true)
            machine.resetTracking()
            return Unmanaged.passUnretained(event)
        }
        if Synthetic.isOurs(event) { return Unmanaged.passUnretained(event) }

        let kind = EventKind(type)
        let input = TapInput(
            kind: kind,
            keycode: kind.isKey ? event.getIntegerValueField(.keyboardEventKeycode) : -1,
            flags: event.flags,
            autorepeat: kind == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            now: uptimeNanos())

        switch machine.process(input) {
        case .pass:
            return Unmanaged.passUnretained(event)
        case .passAddingCommand(let keycode):
            event.flags = Synthetic.withCommand(event.flags, keycode: keycode)
            return Unmanaged.passUnretained(event)
        case .swallow:
            return nil
        }
    }
}

/// Owns the one live tap. Sendable, so the signal handlers can stop it too.
nonisolated final class TapHost: Sendable {
    private let machine: HoldMachine
    private let onResult: @Sendable (TapLocation, Bool) -> Void
    private let current = Mutex<EventTap?>(nil)

    init(machine: HoldMachine, onResult: @escaping @Sendable (TapLocation, Bool) -> Void) {
        self.machine = machine
        self.onResult = onResult
    }

    /// Stops any running tap (posting an owed release), then starts one at `location`.
    func start(_ location: TapLocation) {
        stop(reason: "tap recreated")
        machine.resetTracking()
        let tap = EventTap(location: location, machine: machine, onResult: onResult)
        current.withLock { $0 = tap }
        tap.start()
    }

    /// The tap goes off first and the owed release is posted second, so no new hold can start in
    /// between.
    func stop(reason: String) {
        let old = current.withLock { c -> EventTap? in
            defer { c = nil }
            return c
        }
        old?.stop()
        machine.releaseCommandIfOwed(reason: reason, cancel: true)
    }
}
