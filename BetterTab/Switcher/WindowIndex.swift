import AppKit
import ApplicationServices
import Synchronization
import os

/// One real window of an app, on any Space.
nonisolated struct AppWindow: @unchecked Sendable {
    let windowID: CGWindowID
    /// nil until AX has resolved the window; windows on other Spaces may need a remote-token scan.
    /// Focusing works without it. AX elements are safe to use from any thread.
    let element: AXUIElement?
    /// Empty while unknown.
    let title: String
    let isMinimized: Bool
    /// The Space it's on, or 0 if unknown.
    let spaceID: UInt64
    let isFullScreen: Bool
    /// In the window server's global coordinates (points, top-left origin). `.null` if unknown.
    let frame: CGRect

    init(
        windowID: CGWindowID, element: AXUIElement?, title: String, isMinimized: Bool,
        spaceID: UInt64 = 0, isFullScreen: Bool = false, frame: CGRect = .null
    ) {
        self.windowID = windowID
        self.element = element
        self.title = title
        self.isMinimized = isMinimized
        self.spaceID = spaceID
        self.isFullScreen = isFullScreen
        self.frame = frame
    }

    /// This window, with the title and element of `earlier` where it has none of its own.
    func filling(from earlier: AppWindow) -> AppWindow {
        AppWindow(
            windowID: windowID, element: element ?? earlier.element, title: title.isEmpty ? earlier.title : title,
            isMinimized: isMinimized, spaceID: spaceID, isFullScreen: isFullScreen,
            frame: frame.isNull ? earlier.frame : frame)
    }

    /// Whether two lists would give the same rows, the same outlines and the same focus targets.
    static func sameRows(_ a: [AppWindow], _ b: [AppWindow]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { a, b in
            a.windowID == b.windowID && a.title == b.title && a.isMinimized == b.isMinimized
                && (a.element == nil) == (b.element == nil) && a.spaceID == b.spaceID && a.isFullScreen == b.isFullScreen
                && a.frame == b.frame
        }
    }
}

/// Every app's real windows on every Space. SkyLight says which windows exist, with no
/// permission; AX adds titles and elements. The work runs off the main actor; results arrive on
/// it. Nothing runs between sessions apart from the one-shot warm-ups.
final class WindowIndex {
    /// Remote-token scanning time per app per load.
    static let scanBudget = 0.060
    /// The warm-up's, which nothing waits for.
    static let warmUpScanBudget = 0.250

    private struct Load {
        let onResult: (pid_t, [AppWindow]) -> Void
        let startedAt: UInt64
        var remaining: Int
        var answered = 0
        var unanswered = 0
        var skipped = 0
    }

    /// Handlers stay here on the main actor; the readers only send back a load id.
    private var loads: [UInt64: Load] = [:]
    private var nextLoadID: UInt64 = 0
    private let epoch = LoadEpoch()
    private let cache = ElementCache()
    private let readers = DispatchQueue(
        label: "com.luksanss.BetterTab.WindowIndex", qos: .userInitiated, attributes: .concurrent)
    private let scans = DispatchQueue(
        label: "com.luksanss.BetterTab.WindowIndex.scan", qos: .userInitiated, attributes: .concurrent)
    private var warmedUp = false

    private var watchThread: AXObserverThread?
    private var watchHandler: (([AppWindow]) -> Void)?
    private var watchToken: UInt64 = 0
    private var terminationObserver: (any NSObjectProtocol)?

    init() {
        SkyLightWindows.warmUp()
    }

    /// Reads each app's windows. `onResult` fires straight away with SkyLight's windows (titles
    /// empty, elements from the cache), then again for an app whenever AX or the remote-token
    /// scan changes what it has: titles, elements, windows that turn out not to be standard. An
    /// app with no real window gets no call. A hung app keeps SkyLight's untitled windows.
    func load(
        pids: [pid_t], order: WindowOrder = .mainWindowFirst, onResult: @escaping (pid_t, [AppWindow]) -> Void
    ) {
        var seen = Set<pid_t>()
        let pids = pids.filter { $0 > 0 && seen.insert($0).inserted }
        guard !pids.isEmpty else { return }
        nextLoadID &+= 1
        let id = nextLoadID
        loads[id] = Load(onResult: onResult, startedAt: DispatchTime.now().uptimeNanoseconds, remaining: pids.count)
        let epoch = epoch
        let wanted = epoch.current
        WindowLoader(
            cache: cache, readers: readers, scans: scans, scanBudget: Self.scanBudget, order: order,
            // Checked before every step and every scanned id, so nothing lingers after `cancel()`.
            isWanted: { epoch.current == wanted },
            deliver: { [weak self] pid, windows in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.loads[id]?.onResult(pid, windows) }
                }
            },
            finished: { [weak self] pid, answer in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.finished(load: id, answer: answer) }
                }
            }
        ).start(pids)
    }

    /// Once, when BetterTab first has Accessibility: resolves the apps' windows, with a longer
    /// scan, so the first ⌘⇥ finds their elements cached. Delivers nothing.
    func warmUp(pids: [pid_t]) {
        guard !warmedUp else { return }
        warmedUp = true
        WindowLoader(
            cache: cache, readers: readers, scans: scans, scanBudget: Self.warmUpScanBudget, order: .mainWindowFirst,
            isWanted: { true }, deliver: { _, _ in }, finished: { _, _ in }
        ).start(pids)
    }

    /// While the list is open: calls `onChange` with the app's fresh windows whenever one on the
    /// current Space is created, or any known one is closed, minimized or restored. Replaces any
    /// earlier watch.
    func watch(pid: pid_t, onChange: @escaping ([AppWindow]) -> Void) {
        stopWatching()
        let token = watchToken
        watchHandler = onChange
        let deliver: @Sendable (WatchRead) -> Void = { [weak self] read in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.watchRead(read, token: token) }
            }
        }
        let cache = cache
        let thread = AXObserverThread()
        watchThread = thread
        thread.start(name: "BetterTab.WindowIndex.watch", qos: .userInitiated) { thread in
            WindowWatch.make(pid: pid, cache: cache, thread: thread, deliver: deliver)
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

    /// Ends the watch only; loads carry on. Idempotent.
    func stopWatching() {
        watchToken &+= 1
        watchThread?.stop()
        watchThread = nil
        if let terminationObserver { NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver) }
        terminationObserver = nil
        watchHandler = nil
    }

    /// Drops pending results, stops scans and any watch. Idempotent.
    func cancel() {
        epoch.advance()
        loads.removeAll()
        stopWatching()
    }

    private func finished(load id: UInt64, answer: AXAnswer?) {
        guard var load = loads[id] else { return }
        load.remaining -= 1
        switch answer {
        case nil: load.skipped += 1
        case .answered?: load.answered += 1
        default: load.unanswered += 1
        }
        loads[id] = load
        guard load.remaining == 0 else { return }
        let ms = (DispatchTime.now().uptimeNanoseconds &- load.startedAt) / 1_000_000
        windowsLog.debug("""
            windows read in \(ms, privacy: .public) ms: AX answered for \(load.answered, privacy: .public) apps, \
            gave no answer for \(load.unanswered, privacy: .public), \(load.skipped, privacy: .public) needed none
            """)
    }

    private func watchRead(_ read: WatchRead, token: UInt64) {
        guard token == watchToken, let handler = watchHandler else { return }
        switch read {
        case .windows(let windows):
            handler(windows)
        case .gone:
            stopWatching()
            handler([])
        }
    }
}

// MARK: - Off the main actor

/// Bumped by `cancel()`, and read by readers and scans.
nonisolated private final class LoadEpoch: Sendable {
    private let value = Atomic<UInt64>(0)
    var current: UInt64 { value.load(ordering: .relaxed) }
    func advance() { _ = value.wrappingAdd(1, ordering: .relaxed) }
}

nonisolated private enum WatchRead: Sendable {
    case windows([AppWindow])
    /// The app is gone.
    case gone
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

/// Lives on its thread only. AX observes the windows it has elements for, which includes those
/// on other Spaces that the cache has resolved; each read asks SkyLight too, so a window closed
/// anywhere drops out.
nonisolated private final class WindowWatch: AXObserverWorker {
    private let pid: pid_t
    private let cache: ElementCache
    private let thread: AXObserverThread
    private let deliver: @Sendable (WatchRead) -> Void
    private let app: AXUIElement
    private let observer: AXObserver
    /// Windows with notifications registered, updated after each answered read.
    private var windows: [AXUIElement] = []
    private var delivered: [AppWindow]?
    private var pending: CFRunLoopTimer?
    private var retries = 0

    static func make(
        pid: pid_t, cache: ElementCache, thread: AXObserverThread, deliver: @escaping @Sendable (WatchRead) -> Void
    ) -> WindowWatch? {
        var created: AXObserver?
        let result = AXObserverCreate(pid, windowWatchCallback, &created)
        guard result == .success, let created else {
            // Only a quit is noticed then, through NSWorkspace.
            windowsLog.error("AXObserverCreate for the listed app failed (\(result.rawValue, privacy: .public))")
            return nil
        }
        return WindowWatch(pid: pid, cache: cache, observer: created, thread: thread, deliver: deliver)
    }

    private init(
        pid: pid_t, cache: ElementCache, observer: AXObserver, thread: AXObserverThread,
        deliver: @escaping @Sendable (WatchRead) -> Void
    ) {
        self.pid = pid
        self.cache = cache
        self.thread = thread
        self.deliver = deliver
        self.observer = observer
        app = AXCall.application(pid)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        let created = AXObserverAddNotification(observer, app, kAXWindowCreatedNotification as CFString, refcon)
        if created != .success {
            windowsLog.error("window-created notification not registered (\(created.rawValue, privacy: .public))")
        }
        // This read finds which windows to observe. It's delivered too, because the caller's
        // windows were read when the switcher opened, and the app may have lost some since.
        read()
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
        read()
    }

    private func read() {
        let thread = thread
        guard !thread.isStopRequested else { return }
        let real = SkyLightWindows.snapshot().map { $0.windowsByPid[pid] ?? [] }
        let pass = WindowReader.axPass(
            pid: pid, real: real.map { Set($0.map(\.windowID)) }, cache: cache, isWanted: { !thread.isStopRequested })
        switch pass.answer {
        case .gone:
            deliver(.gone)
            thread.stop()
            return
        case .answered:
            retries = 0
            register(pass.facts.values.map(\.element.element))
        case .noAnswer:
            if retries < WatchTiming.retryLimit {
                retries += 1
                scheduleReread(after: WatchTiming.retryDelay)
            }
        case .unavailable:
            break
        }
        // Without SkyLight, an app that didn't answer has nothing to show, and saying so would
        // close the list.
        guard real != nil || pass.answer == .answered else { return }
        let windows = WindowReader.windows(
            real: real, pass: pass, cached: cache.elements(of: pid), cachedFront: cache.front(of: pid))
        if let delivered, AppWindow.sameRows(delivered, windows) { return }
        delivered = windows
        deliver(.windows(windows))
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
