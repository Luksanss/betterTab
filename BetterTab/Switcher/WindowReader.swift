import ApplicationServices
import Foundation
import Synchronization
import os

nonisolated let windowsLog = Logger(subsystem: "com.luksanss.BetterTab", category: "windows")

/// The AX elements of apps' windows, kept for the process lifetime so a window on another Space is
/// scanned for once, not on every switch. Elements and ids only: titles are never kept
/// (docs/spec.md § Privacy). Any thread.
nonisolated final class ElementCache: Sendable {
    private struct App: Sendable {
        var elements: [CGWindowID: AXElement] = [:]
        var progress = ScanProgress()
        var scanning = false
        /// Scans in a row that found none of `fruitlessMissing`.
        var fruitless = 0
        var fruitlessMissing: Set<CGWindowID> = []
    }

    /// Fruitless scans for the same missing windows before giving up on them until that set changes.
    static let fruitlessLimit = 3

    private let apps = Mutex<[pid_t: App]>([:])

    func elements(of pid: pid_t) -> [CGWindowID: AXElement] {
        apps.withLock { $0[pid]?.elements ?? [:] }
    }

    /// Forgets windows that have left the window server's list, and apps that have quit.
    func prune(to snapshot: SkyLightSnapshot) {
        apps.withLock { apps in
            for (pid, var app) in apps {
                let real = Set((snapshot.windowsByPid[pid] ?? []).map(\.windowID))
                if real.isEmpty, kill(pid, 0) == -1, errno == ESRCH {
                    apps[pid] = nil
                    continue
                }
                app.elements = app.elements.filter { real.contains($0.key) }
                apps[pid] = app
            }
        }
    }

    func store(_ elements: [CGWindowID: AXElement], of pid: pid_t) {
        apps.withLock { apps in
            var app = apps[pid] ?? App()
            app.elements.merge(elements) { _, new in new }
            apps[pid] = app
        }
    }

    func drop(_ windowID: CGWindowID, of pid: pid_t) {
        apps.withLock { _ = $0[pid]?.elements.removeValue(forKey: windowID) }
    }

    /// Claims the app's scan. nil if one is running already, or it has given up on these windows.
    func beginScan(of pid: pid_t, missing: Set<CGWindowID>) -> ScanProgress? {
        apps.withLock { apps -> ScanProgress? in
            var app = apps[pid] ?? App()
            guard !app.scanning, app.fruitless < Self.fruitlessLimit || app.fruitlessMissing != missing else { return nil }
            app.scanning = true
            apps[pid] = app
            return app.progress
        }
    }

    /// Always follows a `beginScan` that returned progress. A cancelled scan isn't counted as fruitless.
    func endScan(of pid: pid_t, missing: Set<CGWindowID>, progress: ScanProgress, result: WindowScan.Result) {
        apps.withLock { apps in
            var app = apps[pid] ?? App()
            app.scanning = false
            app.progress = progress
            app.elements.merge(result.found) { _, new in new }
            if !result.found.isEmpty {
                app.fruitless = 0
                app.fruitlessMissing = []
            } else if !result.cancelled {
                app.fruitless = missing == app.fruitlessMissing ? app.fruitless + 1 : 1
                app.fruitlessMissing = missing
            }
            apps[pid] = app
        }
    }
}

/// What AX says about one window.
nonisolated struct WindowFacts: Sendable {
    let element: AXElement
    /// nil when AX didn't say; such a window still counts.
    let subrole: String?
    let title: String
    let isMinimized: Bool?
}

nonisolated enum AXAnswer: Sendable, Equatable {
    case answered
    /// Timed out or refused. The app still gets SkyLight's windows, untitled.
    case noAnswer
    /// No Accessibility permission.
    case unavailable
    case gone
}

/// One app's AX answer.
nonisolated struct AXPass: Sendable {
    var answer: AXAnswer
    var facts: [CGWindowID: WindowFacts] = [:]
    /// kAXWindows' order, used only when SkyLight is unavailable.
    var order: [CGWindowID] = []
}

nonisolated enum WindowReader {
    enum FactsRead {
        case facts(WindowFacts)
        case invalid
        case noAnswer
    }

    static func facts(of element: AXElement) -> FactsRead {
        let (values, errors, error) = AXCall.values(
            element.element, [kAXSubroleAttribute, kAXTitleAttribute, kAXMinimizedAttribute])
        if error == .invalidUIElement || errors.first == .invalidUIElement { return .invalid }
        if error == .cannotComplete { return .noAnswer }
        return .facts(WindowFacts(
            element: element, subrole: values[0] as? String, title: values[1] as? String ?? "",
            isMinimized: values[2] as? Bool))
    }

    /// kAXWindows (the current Space, minimized windows and every window of a hidden app), the
    /// main and focused windows (which AX reaches on any Space), and cached elements for the rest;
    /// then each one's subrole, title and minimized state. `real` is SkyLight's windows for the
    /// app, or nil when SkyLight is unavailable.
    static func axPass(pid: pid_t, real: Set<CGWindowID>?, cache: ElementCache, isWanted: () -> Bool) -> AXPass {
        let (values, _, error) = AXCall.values(
            AXCall.application(pid), [kAXWindowsAttribute, kAXMainWindowAttribute, kAXFocusedWindowAttribute])
        switch error {
        case .success: break
        case .apiDisabled: return AXPass(answer: .unavailable)
        case .invalidUIElement: return AXPass(answer: .gone)
        default: return AXPass(answer: .noAnswer)
        }
        var pass = AXPass(answer: .answered)
        var resolved: [CGWindowID: AXElement] = [:]
        func resolve(_ element: AXUIElement) -> CGWindowID? {
            // Elements AX hands out carry its 6 s default timeout.
            AXUIElementSetMessagingTimeout(element, AXCall.messagingTimeout)
            guard let id = AXPrivate.windowID(of: element), real?.contains(id) ?? true else { return nil }
            if resolved[id] == nil { resolved[id] = AXElement(element: element) }
            return id
        }
        for element in values[0] as? [AXUIElement] ?? [] {
            if let id = resolve(element), !pass.order.contains(id) { pass.order.append(id) }
        }
        // Their elements, for windows on other Spaces that kAXWindows leaves out.
        _ = AXCall.asElement(values[1]).flatMap(resolve)
        _ = AXCall.asElement(values[2]).flatMap(resolve)
        if let real {
            for (id, element) in cache.elements(of: pid) where resolved[id] == nil && real.contains(id) {
                resolved[id] = element
            }
        }
        reading: for (id, element) in resolved {
            guard isWanted() else {
                pass.answer = .noAnswer
                break
            }
            switch facts(of: element) {
            case .facts(let facts):
                pass.facts[id] = facts
            case .invalid:
                resolved[id] = nil
                cache.drop(id, of: pid)
            case .noAnswer:
                // Hung: every further window would cost the whole timeout.
                pass.answer = .noAnswer
                break reading
            }
        }
        cache.store(resolved, of: pid)
        return pass
    }

    /// The app's windows as ⌘§ shows them: SkyLight's, less any AX says aren't standard windows,
    /// with what AX knows of each. `pass` is nil before AX has been asked. The order is the window
    /// server's as it stands: the current Space front to back, so the window you're in comes
    /// first, then the other Spaces, most recently visited first, then minimized windows.
    static func windows(real: [SkyLightWindow]?, pass: AXPass?, cached: [CGWindowID: AXElement]) -> [AppWindow] {
        let facts = pass?.facts ?? [:]
        // Without SkyLight, AX's own list is all there is: the current Space only.
        let base = real ?? (pass?.order ?? []).map {
            SkyLightWindow(
                windowID: $0, spaceID: 0, isMinimized: facts[$0]?.isMinimized ?? false, isFullScreen: false, frame: .null)
        }
        var windows: [AppWindow] = []
        for window in base {
            let known = facts[window.windowID]
            if let subrole = known?.subrole, subrole != kAXStandardWindowSubrole { continue }
            if real == nil, known?.subrole == nil { continue }
            windows.append(AppWindow(
                windowID: window.windowID, element: (known?.element ?? cached[window.windowID])?.element,
                title: known?.title ?? "", isMinimized: known?.isMinimized ?? window.isMinimized,
                spaceID: window.spaceID, isFullScreen: window.isFullScreen, frame: window.frame))
        }
        return windows.filter { !$0.isMinimized } + windows.filter(\.isMinimized)
    }
}

/// One `WindowIndex.load`: SkyLight's windows for every app at once, then AX for each app in
/// parallel, then a remote-token scan where AX left windows unresolved. Each step delivers again,
/// but only if it changed something.
nonisolated final class WindowLoader: Sendable {
    private let cache: ElementCache
    private let readers: DispatchQueue
    private let scans: DispatchQueue
    private let scanBudget: Double
    private let withFrames: Bool
    private let isWanted: @Sendable () -> Bool
    private let deliver: @Sendable (pid_t, [AppWindow]) -> Void
    /// Once per app, after its AX pass; nil if it needed none.
    private let finished: @Sendable (pid_t, AXAnswer?) -> Void

    init(
        cache: ElementCache, readers: DispatchQueue, scans: DispatchQueue, scanBudget: Double, withFrames: Bool,
        isWanted: @escaping @Sendable () -> Bool,
        deliver: @escaping @Sendable (pid_t, [AppWindow]) -> Void,
        finished: @escaping @Sendable (pid_t, AXAnswer?) -> Void
    ) {
        self.cache = cache
        self.readers = readers
        self.scans = scans
        self.scanBudget = scanBudget
        self.withFrames = withFrames
        self.isWanted = isWanted
        self.deliver = deliver
        self.finished = finished
    }

    func start(_ pids: [pid_t]) {
        readers.async { [self] in
            guard isWanted() else { return }
            let started = DispatchTime.now().uptimeNanoseconds
            // Only ⌘§ draws window outlines.
            let snapshot = SkyLightWindows.snapshot(framesOf: withFrames ? Set(pids) : [])
            if let snapshot {
                cache.prune(to: snapshot)
                let ms = Double(DispatchTime.now().uptimeNanoseconds &- started) / 1e6
                let windows = snapshot.windowsByPid.values.reduce(0) { $0 + $1.count }
                let several = snapshot.windowsByPid.values.count(where: { $0.count >= 2 })
                windowsLog.debug("""
                    SkyLight: \(windows, privacy: .public) windows, \(several, privacy: .public) apps with two or more, \
                    in \(ms, format: .fixed(precision: 2), privacy: .public) ms
                    """)
            }
            for pid in pids {
                let real = snapshot.map { $0.windowsByPid[pid] ?? [] }
                var shown: [AppWindow] = []
                if let real, !real.isEmpty {
                    shown = WindowReader.windows(real: real, pass: nil, cached: cache.elements(of: pid))
                    deliver(pid, shown)
                }
                // AX only adds titles and drops non-standard windows, and an app with one window or
                // none gets neither stack edges nor a ⌘§ switcher, so it isn't asked.
                if let real, real.count < 2 {
                    finished(pid, nil)
                    continue
                }
                readers.async { [self, shown] in readApp(pid, real: real, shown: shown) }
            }
        }
    }

    private func readApp(_ pid: pid_t, real: [SkyLightWindow]?, shown: [AppWindow]) {
        guard isWanted() else { return }
        let pass = WindowReader.axPass(
            pid: pid, real: real.map { Set($0.map(\.windowID)) }, cache: cache, isWanted: isWanted)
        let cached = cache.elements(of: pid)
        let windows = WindowReader.windows(real: real, pass: pass, cached: cached)
        if !AppWindow.sameRows(windows, shown) { deliver(pid, windows) }
        finished(pid, pass.answer)

        guard pass.answer == .answered, let real else { return }
        let missing = Set(real.map(\.windowID)).subtracting(cached.keys)
        guard !missing.isEmpty, let progress = cache.beginScan(of: pid, missing: missing) else { return }
        scans.async { [self] in
            scan(pid, missing: missing, progress: progress, pass: pass, real: real, shown: windows)
        }
    }

    private func scan(
        _ pid: pid_t, missing: Set<CGWindowID>, progress: ScanProgress, pass: AXPass, real: [SkyLightWindow],
        shown: [AppWindow]
    ) {
        var progress = progress
        let result = WindowScan.run(
            pid: pid, missing: missing, progress: &progress, budget: scanBudget, isWanted: isWanted)
        cache.endScan(of: pid, missing: missing, progress: progress, result: result)
        windowsLog.info("""
            scan: \(result.scanned, privacy: .public) ids from \(result.firstID, privacy: .public) \
            in \(result.milliseconds, format: .fixed(precision: 1), privacy: .public) ms resolved \
            \(result.found.count, privacy: .public) of \(missing.count, privacy: .public) windows\
            \(result.cancelled ? " (cancelled)" : "", privacy: .public); next id \(progress.cursor, privacy: .public) \
            (pid \(pid, privacy: .private))
            """)
        guard !result.found.isEmpty, isWanted() else { return }
        var pass = pass
        for (id, element) in result.found {
            if case .facts(let facts) = WindowReader.facts(of: element) { pass.facts[id] = facts }
        }
        // Read again: the scan took a while, and a window may have closed meanwhile.
        let fresh = SkyLightWindows.snapshot(framesOf: withFrames ? [pid] : [])
            .map { $0.windowsByPid[pid] ?? [] } ?? real
        let windows = WindowReader.windows(real: fresh, pass: pass, cached: cache.elements(of: pid))
        if !AppWindow.sameRows(windows, shown) { deliver(pid, windows) }
    }
}
