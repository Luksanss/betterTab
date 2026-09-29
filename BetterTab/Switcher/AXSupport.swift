import ApplicationServices
import CoreFoundation
import Foundation
import Synchronization

/// Thin, synchronous AX reads for the switcher and window readers. Callable from any thread.
nonisolated enum AXCall {
    /// `docs/spec.md` § Constants.
    static let messagingTimeout: Float = 0.25

    static func application(_ pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    static func value(_ element: AXUIElement, _ attribute: String) -> (value: CFTypeRef?, error: AXError) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return (error == .success ? value : nil, error)
    }

    /// Elements handed out by AX carry the default 6 s timeout, so each gets ours.
    static func elements(_ element: AXUIElement, _ attribute: String) -> (elements: [AXUIElement], error: AXError) {
        let (value, error) = value(element, attribute)
        let elements = value as? [AXUIElement] ?? []
        for element in elements { AXUIElementSetMessagingTimeout(element, messagingTimeout) }
        return (elements, error)
    }

    static func children(_ element: AXUIElement) -> (elements: [AXUIElement], error: AXError) {
        elements(element, kAXChildrenAttribute)
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> (string: String?, error: AXError) {
        let (value, error) = value(element, attribute)
        return (value as? String, error)
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        value(element, attribute).value as? Bool
    }

    /// AX's own top-left global coordinates.
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = value(element, kAXPositionAttribute).value,
            CFGetTypeID(position) == AXValueGetTypeID(),
            let size = value(element, kAXSizeAttribute).value,
            CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
            AXValueGetValue(size as! AXValue, .cgSize, &extent)
        else { return nil }
        return CGRect(origin: point, size: extent)
    }

    /// Some elements vend a CFURL, others a path or URL string.
    static func fileURL(_ element: AXUIElement, _ attribute: String) -> URL? {
        let value = value(element, attribute).value
        if let url = value as? URL { return url }
        guard let string = value as? String, !string.isEmpty else { return nil }
        if let url = URL(string: string), url.isFileURL { return url }
        return string.hasPrefix("/") ? URL(fileURLWithPath: string) : nil
    }

    static func sameElements(_ a: [AXUIElement], _ b: [AXUIElement]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { CFEqual($0, $1) }
    }
}

nonisolated struct AXRunLoopRef: @unchecked Sendable { let loop: CFRunLoop }

/// Whatever an `AXObserverThread` runs. Created, used and torn down on that thread only, so it
/// needn't be Sendable; AX and timer callbacks reach it through an unretained refcon.
nonisolated protocol AXObserverWorker: AnyObject {
    /// On the worker's thread, after its run loop has stopped for good.
    func tearDown()
}

/// A short-lived thread with its own run loop, for an `AXObserver`'s source and any timers. It
/// exists only while something is being watched, so nothing runs while BetterTab is idle.
nonisolated final class AXObserverThread: Sendable {
    private struct State: Sendable {
        var loop: AXRunLoopRef?
        var stopRequested = false
    }

    private let state = Mutex(State())

    /// `makeWorker` runs on the new thread; returning nil ends the thread at once.
    func start(
        name: String, qos: QualityOfService,
        makeWorker: @escaping @Sendable (AXObserverThread) -> (any AXObserverWorker)?
    ) {
        // The closure keeps `self` alive until the thread finishes.
        let thread = Thread { [self] in run(makeWorker) }
        thread.name = name
        thread.qualityOfService = qos
        thread.start()
    }

    var isStopRequested: Bool { state.withLock { $0.stopRequested } }

    /// Any thread, including the worker's own. Idempotent and non-blocking.
    func stop() {
        let loop = state.withLock { state -> AXRunLoopRef? in
            state.stopRequested = true
            return state.loop
        }
        guard let loop else { return }
        // Queued on the loop itself, so the stop lands even if the loop isn't running yet.
        CFRunLoopPerformBlock(loop.loop, CFRunLoopMode.defaultMode.rawValue) {
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        CFRunLoopWakeUp(loop.loop)
    }

    private func run(_ makeWorker: @Sendable (AXObserverThread) -> (any AXObserverWorker)?) {
        let loop: CFRunLoop = CFRunLoopGetCurrent()
        let proceed = state.withLock { state -> Bool in
            state.loop = AXRunLoopRef(loop: loop)
            return !state.stopRequested
        }
        defer { state.withLock { $0.loop = nil } }
        guard proceed, let worker = makeWorker(self) else { return }
        while !isStopRequested {
            // `.finished` means no sources or timers are left, so nothing could ever wake us.
            if CFRunLoopRunInMode(.defaultMode, 10, false) == .finished { break }
        }
        worker.tearDown()
    }
}
