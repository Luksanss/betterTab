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

    /// Whether two lists would give the same tiles, the same outlines and the same focus targets.
    static func sameRows(_ a: [AppWindow], _ b: [AppWindow]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { a, b in
            a.windowID == b.windowID && a.title == b.title && a.isMinimized == b.isMinimized
                && (a.element == nil) == (b.element == nil) && a.spaceID == b.spaceID && a.isFullScreen == b.isFullScreen
                && a.frame == b.frame
        }
    }
}

/// Every app's real windows on every Space. SkyLight says which windows exist, with no
/// permission; AX adds titles and elements, and drops windows that aren't standard ones. The work
/// runs off the main actor; results arrive on it. Nothing runs between sessions apart from the
/// one-shot warm-up.
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

    init() {
        SkyLightWindows.warmUp()
    }

    /// Reads each app's windows. `onResult` fires straight away with SkyLight's windows (titles
    /// empty, elements from the cache), then again for an app whenever AX or the remote-token
    /// scan changes what it has: titles, elements, windows that turn out not to be standard. An
    /// app with no real window gets no call. A hung app keeps SkyLight's untitled windows.
    /// `withFrames` reads each window's frame too, one round trip per window, for ⌘§'s outlines.
    func load(
        pids: [pid_t], withFrames: Bool = false, onResult: @escaping (pid_t, [AppWindow]) -> Void
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
            cache: cache, readers: readers, scans: scans, scanBudget: Self.scanBudget, withFrames: withFrames,
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
    /// scan, so the first ⌘§ finds their elements cached. Delivers nothing.
    func warmUp(pids: [pid_t]) {
        guard !warmedUp else { return }
        warmedUp = true
        WindowLoader(
            cache: cache, readers: readers, scans: scans, scanBudget: Self.warmUpScanBudget, withFrames: false,
            isWanted: { true }, deliver: { _, _ in }, finished: { _, _ in }
        ).start(pids)
    }

    /// Drops pending results and stops scans. Idempotent.
    func cancel() {
        epoch.advance()
        loads.removeAll()
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
}

// MARK: - Off the main actor

/// Bumped by `cancel()`, and read by readers and scans.
nonisolated private final class LoadEpoch: Sendable {
    private let value = Atomic<UInt64>(0)
    var current: UInt64 { value.load(ordering: .relaxed) }
    func advance() { _ = value.wrappingAdd(1, ordering: .relaxed) }
}
