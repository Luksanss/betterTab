import AppKit
import os

/// The ⌘§ window switcher (docs/spec.md § ⌘§): ⌘⇥'s behaviour for the front app's windows. The
/// tap swallows ⌘§ and the keys pressed while the switcher is open, but ⌘ passes both ways, so
/// nothing is owed and every way out only hides the panel. Main actor only.
final class WindowSwitchController {
    /// A quick ⌘§ tap flips windows without the switcher flashing up, as a quick ⌘⇥ flips apps.
    static let showDelay: Duration = .milliseconds(160)
    /// How long a release that came before the windows waits for them before giving up.
    static let lateWindowsLimit: Duration = .seconds(1)

    private let tap: KeyTap
    private let index: WindowIndex
    private let switcher = WindowSwitcher()
    private let logger = Logger(subsystem: "com.luksanss.BetterTab", category: "windows-switch")

    private struct Session {
        /// The tap's generation at ⌘§; `endWindows` takes it back.
        let generation: UInt64
        let pid: pid_t
        let backwards: Bool
        /// In tile order: the window you're in first, minimized windows last.
        var windows: [AppWindow] = []
        var model = WindowSwitcherModel()
        /// The first windows have arrived and the highlight has its starting place.
        var started = false
        /// § pressed again before the windows arrived; applied when they do.
        var pendingSteps = 0
        /// Other keys pressed before the windows arrived, replayed when they do.
        var pendingKeys: [UInt16] = []
        /// The switcher should be on screen: the delay is over, or the user moved the highlight.
        var wantsShow = false
        /// ⌘ went up before the windows arrived: open the highlighted one as soon as they do.
        var releasedEarly = false
        /// Where the switcher shows: the display of the window you're in, fixed for the session.
        var screen: NSScreen?
        /// The switcher has been on screen at some point.
        var shown = false
    }

    private var session: Session? {
        didSet { publishForSelfTest(ended: oldValue) }
    }

    var isActive: Bool { session != nil }

    init(tap: KeyTap, index: WindowIndex) {
        self.tap = tap
        self.index = index
        switcher.onHover = { [weak self] tile in self?.hover(tile) }
        switcher.onClick = { [weak self] tile in self?.click(tile) }
    }

    // MARK: From the tap

    func start(session generation: UInt64, backwards: Bool) {
        reset()
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            tap.endWindows(session: generation)
            return
        }
        let pid = app.processIdentifier
        // SkyLight answers in about a millisecond, so an app with one window lets the tap go at
        // once, before a ⌘-shortcut typed next is swallowed. Without SkyLight, the load decides.
        if let snapshot = SkyLightWindows.snapshot(), (snapshot.windowsByPid[pid]?.count ?? 0) < 2 {
            tap.endWindows(session: generation)
            logger.info("⌘§: the front app has fewer than two windows; nothing to switch")
            return
        }
        session = Session(generation: generation, pid: pid, backwards: backwards)
        index.load(pids: [pid], order: .windowServer) { [weak self] loaded, windows in
            guard loaded == pid else { return }
            self?.windowsLoaded(windows, generation: generation)
        }
        Task { [weak self] in
            try? await Task.sleep(for: Self.showDelay)
            self?.showWhenReady(generation: generation)
        }
    }

    /// § or ⇧§ again, repeats included.
    func step(by delta: Int, session generation: UInt64) {
        guard var session, session.generation == generation else { return }
        if session.started {
            session.model.step(by: delta)
        } else {
            session.pendingSteps += delta
        }
        session.wantsShow = true
        self.session = session
        present()
    }

    func key(_ code: UInt16, session generation: UInt64) {
        guard var session, session.generation == generation else { return }
        guard session.started else {
            // The windows are a few milliseconds away; an early Esc or letter still counts.
            session.pendingKeys.append(code)
            self.session = session
            return
        }
        apply(code)
    }

    /// The tap has left the session: ⌘ went up (`commit`), or the tap stopped or was turned off.
    func ended(commit: Bool) {
        guard var session else { return }
        guard commit else {
            reset()
            return
        }
        if let window = session.model.highlightedWindow, session.started {
            open(window)
            return
        }
        // Released before SkyLight's windows got here, which takes a few milliseconds at most.
        // Nothing is on screen yet, since the switcher shows only once it has tiles.
        session.releasedEarly = true
        self.session = session
        let generation = session.generation
        Task { [weak self] in
            try? await Task.sleep(for: Self.lateWindowsLimit)
            guard let self, self.session?.generation == generation else { return }
            self.logger.error("⌘§: the windows didn't arrive after the release; nothing opened")
            self.reset()
        }
    }

    /// Hides everything and forgets the session. Leaves the tap alone: whoever ends the session
    /// tells the tap first, if it needs telling.
    func reset() {
        guard session != nil else { return }
        switcher.hide()
        session = nil
        index.cancel()
    }

    // MARK: The windows

    private func windowsLoaded(_ windows: [AppWindow], generation: UInt64) {
        guard var session, session.generation == generation else { return }
        // Once the switcher has tiles, no letter may move under the user's finger.
        let windows = session.started ? Self.keepingTiles(of: session.windows, fresh: windows) : windows
        guard windows.count >= 2 else {
            // AX found that some weren't standard windows after all.
            if !session.releasedEarly { tap.endWindows(session: generation) }
            logger.info("⌘§: fewer than two standard windows; nothing to switch")
            reset()
            return
        }
        let displays = DisplayMap()
        let items = windows.map { window in
            WindowSwitcherItem(title: window.title, isMinimized: window.isMinimized,
                               windowFrame: window.frame, displayFrame: displays.display(for: window.frame).frame)
        }
        let highlighted = session.model.highlightedWindow.map { session.windows[$0].windowID }
        session.windows = windows
        if session.started {
            session.model.setWindows(items)
            // A window gone from before the highlight mustn't move it onto another window.
            if let highlighted, let tile = windows.firstIndex(where: { $0.windowID == highlighted }),
               tile < session.model.tiles.count {
                session.model.setHighlight(tile)
            }
        } else {
            // As in ⌘⇥: forwards starts on the window before this one, backwards on the last.
            session.model = WindowSwitcherModel(windows: items)
            session.model.setHighlight(session.backwards ? session.model.tiles.count - 1 : 1)
            session.model.step(by: session.pendingSteps)
            session.started = true
            session.pendingSteps = 0
            session.screen = displays.screen(for: windows[0].frame)
            logger.info("""
                ⌘§: \(windows.count, privacy: .public) windows, \
                \(windows.count(where: \.isFullScreen), privacy: .public) full-screen, \
                \(windows.count(where: { $0.frame.isNull }), privacy: .public) without a frame
                """)
        }
        let pending = session.pendingKeys
        session.pendingKeys = []
        self.session = session
        for code in pending {
            guard self.session?.generation == generation else { return }
            apply(code)
        }
        guard let session = self.session, session.generation == generation else { return }
        if session.releasedEarly, let window = session.model.highlightedWindow {
            open(window)
        } else {
            present()
        }
    }

    private func apply(_ code: UInt16) {
        guard var session else { return }
        let action = session.model.handle(keyCode: code)
        self.session = session
        switch action {
        case nil:
            break
        case .moveHighlight:
            self.session?.wantsShow = true
            present()
        case .pick(let window):
            pick(window)
        case .cancel:
            // If the tap has left already, its message finds no session and does nothing.
            tap.endWindows(session: session.generation)
            logger.info("⌘§ cancelled")
            reset()
        }
    }

    /// A letter, Return or a click, while ⌘ is still held.
    private func pick(_ window: Int) {
        guard let session else { return }
        if tap.endWindows(session: session.generation) {
            open(window)
        } else if let tile = session.model.tiles.firstIndex(where: { $0.windowIndex == window }) {
            // The tap left a moment ago, and its message is on its way. If ⌘ went up, `ended`
            // opens the highlighted window, so make that this one. After ⌘⇥, nothing opens.
            self.session?.model.setHighlight(tile)
        }
    }

    private func showWhenReady(generation: UInt64) {
        guard session?.generation == generation else { return }
        session?.wantsShow = true
        present()
    }

    /// Puts the switcher on screen once it's wanted and has its tiles, and keeps it current.
    private func present() {
        guard let session, session.started, session.wantsShow, !session.releasedEarly else { return }
        if switcher.isVisible {
            switcher.update(session.model)
        } else if let screen = session.screen ?? NSScreen.main {
            switcher.show(session.model, on: screen)
            self.session?.shown = true
        }
    }

    private func hover(_ tile: Int) {
        guard var session, session.model.tiles.indices.contains(tile), tile != session.model.highlight else { return }
        session.model.setHighlight(tile)
        self.session = session
        present()
    }

    private func click(_ tile: Int) {
        guard let session, session.model.tiles.indices.contains(tile) else { return }
        pick(session.model.tiles[tile].windowIndex)
    }

    /// Brings the window forward and ends the session. The first window is the one you're in, so
    /// picking it only closes the switcher.
    private func open(_ index: Int) {
        guard let session, session.windows.indices.contains(index) else {
            reset()
            return
        }
        let window = session.windows[index]
        let pid = session.pid
        logger.info("⌘§: picked window \(index + 1, privacy: .public) of \(session.windows.count, privacy: .public)")
        reset()
        guard index != 0 || window.isMinimized else { return }
        #if DEBUG
        SelfTestHooks.focusRequests.append((pid: pid, windowID: window.windowID))
        #endif
        Focuser.focus(pid: pid, window: window)
    }

    /// What the self-test reads (Debug builds only). `ended` is the session before the change;
    /// when the change ends it, it's recorded.
    private func publishForSelfTest(ended: Session?) {
        #if DEBUG
        if let ended, session?.generation != ended.generation {
            SelfTestHooks.windowSessions.append(
                (ended.windows.map(\.windowID), ended.model.highlight, ended.shown))
        }
        SelfTestHooks.switcherWindowIDs = session?.windows.map(\.windowID) ?? []
        SelfTestHooks.switcherHighlight = session.map { $0.started ? $0.model.highlight : -1 } ?? -1
        SelfTestHooks.switcherVisible = switcher.isVisible
        if session != nil {
            SelfTestHooks.phase = "windows"
        } else if ended != nil {
            SelfTestHooks.phase = "idle"
        }
        #endif
    }

    /// Windows still there keep their tiles (and their title and element, if the fresh read has
    /// none), and new ones go at the end. Tile A stays first.
    private static func keepingTiles(of shown: [AppWindow], fresh: [AppWindow]) -> [AppWindow] {
        // Without SkyLight a window AX can't identify has id 0, and ids can't be matched.
        guard !fresh.contains(where: { $0.windowID == 0 }), !shown.contains(where: { $0.windowID == 0 }) else {
            return fresh
        }
        let byID = Dictionary(fresh.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        let kept = shown.compactMap { old in byID[old.windowID]?.filling(from: old) }
        let keptIDs = Set(kept.map(\.windowID))
        return kept + fresh.filter { !keptIDs.contains($0.windowID) }
    }
}

/// The displays in the window server's global coordinates (top-left origin), as window frames are.
private struct DisplayMap {
    private var displays: [(id: CGDirectDisplayID, frame: CGRect)] = []

    init() {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success else { return }
        displays = ids.prefix(Int(count)).map { ($0, CGDisplayBounds($0)) }
    }

    /// The display showing most of `frame`. A full-screen window's frame is its display's. When
    /// the frame is unknown or on no display, the main display.
    func display(for frame: CGRect) -> (id: CGDirectDisplayID, frame: CGRect) {
        let main = (id: CGMainDisplayID(), frame: CGDisplayBounds(CGMainDisplayID()))
        guard !frame.isNull else { return main }
        func overlap(_ display: CGRect) -> CGFloat {
            let shared = display.intersection(frame)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        return displays.max { overlap($0.frame) < overlap($1.frame) }.flatMap { overlap($0.frame) > 0 ? $0 : nil } ?? main
    }

    func screen(for frame: CGRect) -> NSScreen? {
        let id = display(for: frame).id
        return NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
    }
}
