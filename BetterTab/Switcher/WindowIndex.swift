import AppKit
import ApplicationServices
import Synchronization
import os

/// One standard window of an app.
struct AppWindow: @unchecked Sendable {
    /// AX elements are safe to use from any thread.
    let element: AXUIElement
    let title: String
    let isMinimized: Bool
}

/// Reads apps' standard windows through AX, off the main actor. Results arrive on the main actor.
final class WindowIndex {
    private struct Load {
        let onResult: (pid_t, [AppWindow]) -> Void
        let startedAt: UInt64
        var remaining: Int
        var failed = 0
    }

    /// Handlers stay here on the main actor; the readers only send back a load id.
    private var loads: [UInt64: Load] = [:]
    private var nextLoadID: UInt64 = 0
    private let epoch = LoadEpoch()
    private let readers = DispatchQueue(
        label: "com.luksanss.BetterTab.WindowIndex", qos: .userInitiated, attributes: .concurrent)

    private var watchThread: AXObserverThread?
    private var watchHandler: (([AppWindow]) -> Void)?
    private var watchToken: UInt64 = 0
    private var terminationObserver: (any NSObjectProtocol)?

    /// Reads each app's standard windows in parallel, front to back, with a 250 ms AX timeout
    /// per call; a hung app just gets no result. `onResult` fires once per app as it finishes.
    func load(pids: [pid_t], onResult: @escaping (pid_t, [AppWindow]) -> Void) {
        var seen = Set<pid_t>()
        let pids = pids.filter { $0 > 0 && seen.insert($0).inserted }
        guard !pids.isEmpty else { return }
        nextLoadID &+= 1
        let id = nextLoadID
        loads[id] = Load(onResult: onResult, startedAt: DispatchTime.now().uptimeNanoseconds, remaining: pids.count)
        let epoch = epoch
        let wanted = epoch.current
        for pid in pids {
            readers.async { [weak self] in
                // Skipped outright if `cancel()` came first, so nothing lingers after it.
                let read: WindowRead = epoch.current == wanted
                    ? WindowReader.read(pid, isWanted: { epoch.current == wanted }) : .failed
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.finished(load: id, pid: pid, read: read) }
                }
            }
        }
    }

    /// While the list is open: calls `onChange` with the app's fresh windows whenever one is
    /// created, closed, minimized or restored. Replaces any earlier watch.
    func watch(pid: pid_t, onChange: @escaping ([AppWindow]) -> Void) {
        stopWatch()
        let token = watchToken
        watchHandler = onChange
        let deliver: @Sendable (WindowRead) -> Void = { [weak self] read in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.watchRead(read, token: token) }
            }
        }
        let thread = AXObserverThread()
        watchThread = thread
        thread.start(name: "BetterTab.WindowIndex.watch", qos: .userInitiated) { thread in
            WindowWatch.make(pid: pid, thread: thread, deliver: deliver)
        }
        // AX says nothing reliable when a whole app quits, so this covers it.
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let ended = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            guard ended == pid else { return }
            MainActor.assumeIsolated { self?.watchRead(.gone, token: token) }
        }
        // It may have quit before the observer above existed. Async, so never inside this call.
        if NSRunningApplication(processIdentifier: pid)?.isTerminated ?? true {
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.watchRead(.gone, token: token) }
            }
        }
    }

    /// Drops pending results and any watch. Idempotent.
    func cancel() {
        epoch.advance()
        loads.removeAll()
        stopWatch()
    }

    private func finished(load id: UInt64, pid: pid_t, read: WindowRead) {
        guard var load = loads[id] else { return }
        load.remaining -= 1
        let windows: [AppWindow]?
        if case .windows(let raw) = read {
            windows = raw.map(AppWindow.init)
        } else {
            windows = nil
            load.failed += 1
        }
        if load.remaining > 0 {
            loads[id] = load
        } else {
            loads[id] = nil
            let ms = (DispatchTime.now().uptimeNanoseconds &- load.startedAt) / 1_000_000
            windowsLog.debug("""
                windows read in \(ms, privacy: .public) ms; \(load.failed, privacy: .public) apps gave no result
                """)
        }
        if let windows { load.onResult(pid, windows) }
    }

    private func watchRead(_ read: WindowRead, token: UInt64) {
        guard token == watchToken, let handler = watchHandler else { return }
        switch read {
        case .windows(let raw):
            handler(raw.map(AppWindow.init))
        case .gone:
            stopWatch()
            handler([])
        case .failed:
            break
        }
    }

    private func stopWatch() {
        watchToken &+= 1
        watchThread?.stop()
        watchThread = nil
        if let terminationObserver { NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver) }
        terminationObserver = nil
        watchHandler = nil
    }
}

private extension AppWindow {
    init(_ raw: RawWindow) {
        self.init(element: raw.element, title: raw.title, isMinimized: raw.isMinimized)
    }
}

// MARK: - Reading, off the main actor

nonisolated private let windowsLog = Logger(subsystem: "com.luksanss.BetterTab", category: "windows")

/// Bumped by `cancel()`, and read by readers that haven't started yet.
nonisolated private final class LoadEpoch: Sendable {
    private let value = Atomic<UInt64>(0)
    var current: UInt64 { value.load(ordering: .relaxed) }
    func advance() { _ = value.wrappingAdd(1, ordering: .relaxed) }
}

/// An `AppWindow` before it reaches the main actor. A thin AX wrapper, safe on any thread.
nonisolated private struct RawWindow: @unchecked Sendable {
    let element: AXUIElement
    let title: String
    let isMinimized: Bool
}

nonisolated private enum WindowRead: Sendable {
    case windows([RawWindow])
    /// Timed out or refused; the caller gets nothing rather than a guess.
    case failed
    /// The app is gone.
    case gone
}

nonisolated private enum WindowReader {
    /// `docs/architecture.md` § Which windows count: standard windows only, minimized included,
    /// in AX's front-to-back order.
    static func read(_ pid: pid_t, isWanted: () -> Bool) -> WindowRead {
        let app = AXCall.application(pid)
        let (elements, error) = AXCall.elements(app, kAXWindowsAttribute)
        switch error {
        case .success, .noValue: break
        case .invalidUIElement: return .gone
        default: return .failed
        }
        var windows: [RawWindow] = []
        for element in elements {
            guard isWanted() else { return .failed }
            let (subrole, error) = AXCall.string(element, kAXSubroleAttribute)
            // A hung app would cost 250 ms per window; a partial list would be wrong anyway.
            if error == .cannotComplete { return .failed }
            guard subrole == kAXStandardWindowSubrole else { continue }
            windows.append(RawWindow(
                element: element,
                title: AXCall.string(element, kAXTitleAttribute).string ?? "",
                isMinimized: AXCall.bool(element, kAXMinimizedAttribute) ?? false))
        }
        return .windows(windows)
    }
}

// MARK: - Watching one app, on its own thread

nonisolated private enum WatchTiming {
    /// Coalesces bursts (an app closing several windows) and gives a new window a moment to
    /// get its subrole before it's read.
    static let rereadDelay: CFTimeInterval = 0.05
    /// A busy app (say, mid-way through opening a window) gets a couple more tries.
    static let retryDelay: CFTimeInterval = 0.25
    static let retryLimit = 2
}

nonisolated private let perWindowNotifications = [
    kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
]

nonisolated private func windowWatchCallback(
    _ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    Unmanaged<WindowWatch>.fromOpaque(refcon).takeUnretainedValue().scheduleReread()
}

nonisolated private func windowWatchTimerCallback(_ timer: CFRunLoopTimer?, _ info: UnsafeMutableRawPointer?) {
    guard let info else { return }
    Unmanaged<WindowWatch>.fromOpaque(info).takeUnretainedValue().reread()
}

/// Lives on its thread only.
nonisolated private final class WindowWatch: AXObserverWorker {
    private let pid: pid_t
    private let thread: AXObserverThread
    private let deliver: @Sendable (WindowRead) -> Void
    private let app: AXUIElement
    private let observer: AXObserver
    /// Windows with notifications registered, re-registered after each read.
    private var windows: [AXUIElement] = []
    private var pending: CFRunLoopTimer?
    private var retries = 0

    static func make(
        pid: pid_t, thread: AXObserverThread, deliver: @escaping @Sendable (WindowRead) -> Void
    ) -> WindowWatch? {
        var created: AXObserver?
        let result = AXObserverCreate(pid, windowWatchCallback, &created)
        guard result == .success, let created else {
            // Only a quit is noticed then, through NSWorkspace.
            windowsLog.error("AXObserverCreate for the listed app failed (\(result.rawValue, privacy: .public))")
            return nil
        }
        return WindowWatch(pid: pid, observer: created, thread: thread, deliver: deliver)
    }

    private init(pid: pid_t, observer: AXObserver, thread: AXObserverThread, deliver: @escaping @Sendable (WindowRead) -> Void) {
        self.pid = pid
        self.thread = thread
        self.deliver = deliver
        self.observer = observer
        app = AXCall.application(pid)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        let created = AXObserverAddNotification(observer, app, kAXWindowCreatedNotification as CFString, refcon)
        if created != .success {
            windowsLog.error("window-created notification not registered (\(created.rawValue, privacy: .public))")
        }
        // The caller already has the windows; this read only finds which ones to observe.
        switch WindowReader.read(pid, isWanted: { !thread.isStopRequested }) {
        case .windows(let raw): register(raw.map(\.element))
        case .gone:
            deliver(.gone)
            thread.stop()
        case .failed: scheduleReread(after: WatchTiming.retryDelay)
        }
        windowsLog.debug("watching the listed app: \(self.windows.count, privacy: .public) windows observed")
    }

    private var refcon: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }

    fileprivate func scheduleReread(after delay: CFTimeInterval = WatchTiming.rereadDelay) {
        guard pending == nil, !thread.isStopRequested else { return }
        var context = CFRunLoopTimerContext(version: 0, info: refcon, retain: nil, release: nil, copyDescription: nil)
        let timer = CFRunLoopTimerCreate(
            kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + delay, 0, 0, 0,
            windowWatchTimerCallback, &context)
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .defaultMode)
        pending = timer
    }

    fileprivate func reread() {
        pending = nil
        guard !thread.isStopRequested else { return }
        let read = WindowReader.read(pid) { !thread.isStopRequested }
        switch read {
        case .windows(let raw):
            retries = 0
            register(raw.map(\.element))
            deliver(read)
        case .gone:
            deliver(read)
            thread.stop()
        case .failed:
            guard retries < WatchTiming.retryLimit else { return }
            retries += 1
            scheduleReread(after: WatchTiming.retryDelay)
        }
    }

    private func register(_ current: [AXUIElement]) {
        for window in windows where !current.contains(where: { CFEqual($0, window) }) {
            for name in perWindowNotifications { AXObserverRemoveNotification(observer, window, name as CFString) }
        }
        for window in current where !windows.contains(where: { CFEqual($0, window) }) {
            for name in perWindowNotifications {
                AXObserverAddNotification(observer, window, name as CFString, refcon)
            }
        }
        windows = current
    }

    func tearDown() {
        if let pending { CFRunLoopTimerInvalidate(pending) }
        pending = nil
        for window in windows {
            for name in perWindowNotifications { AXObserverRemoveNotification(observer, window, name as CFString) }
        }
        windows = []
        AXObserverRemoveNotification(observer, app, kAXWindowCreatedNotification as CFString)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
}
