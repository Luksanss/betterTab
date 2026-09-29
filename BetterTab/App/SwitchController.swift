import AppKit
import os

/// Ties the key tap to the switcher reader, the window index, the dots, the window list and the
/// focuser (docs/spec.md § The flow, § States). Main actor only. The tap's own safety nets (the
/// no-input timeout, the tap being turned off, stopping) don't depend on it.
final class SwitchController {
    /// Between cancelling the native switch (Esc, then the ⌘ release) and focusing the picked
    /// window, so the Dock is done before the focus lands. Tunable: acceptance test 4 checks
    /// whether another window of the app flashes up first.
    static let focusDelay: Duration = .milliseconds(50)
    /// How long after the release the list still follows the Dock's highlight. AX can report a
    /// fast Tab this late; later moves come from the pointer hovering over the switcher, and the
    /// list stays on the app the user released on.
    static let highlightCatchUp: Duration = .milliseconds(300)

    /// Sendable, so AppDelegate hands it to the signal handlers too.
    private(set) lazy var tap: KeyTap = KeyTap { [weak self] message in self?.handle(message) }

    private let watcher = SwitcherWatcher()
    private let index = WindowIndex()
    private let list = WindowList()
    private let dots = DotsOverlay()
    private let logger = Logger(subsystem: "com.luksanss.BetterTab", category: "switch")

    private enum Phase: Equatable {
        case idle, cycling
        /// `session` is the tap's generation for this Picking session; `endHold` takes it back.
        case picking(session: UInt64)
    }

    private var phase = Phase.idle
    /// The newest tap generation seen. Messages older than it are late and dropped.
    private var latestGeneration: UInt64 = 0
    /// Each app's standard windows, front to back, only while the switcher is open.
    private var windowsByPid: [pid_t: [AppWindow]] = [:]
    private var requestedPids: Set<pid_t> = []
    /// The app the list shows, and the windows `WindowListAction.pick` indexes.
    private var listed: (pid: pid_t, windows: [AppWindow])?
    /// Bumped whenever results already asked of the index go stale.
    private var epoch = 0
    private var pickingStartedAt: ContinuousClock.Instant?
    /// After ⌘⇥ again the Dock moves its highlight on, but AX reports it a moment later. Until the
    /// highlight leaves this index, a release stays native instead of holding for the wrong app.
    private var highlightLeaving: Int?

    init() {
        watcher.onChange = { [weak self] snapshot in self?.switcherChanged(snapshot) }
        watcher.onClose = { [weak self] in self?.switcherClosed() }
        watcher.onLookupFinished = { found in AppStatus.shared.switcherLookup(succeeded: found) }
    }

    /// Runs the tap exactly while BetterTab has the Accessibility permission.
    func statusChanged() {
        if AppStatus.shared.state == .needsPermission {
            tap.stop()
        } else {
            tap.start()
        }
    }

    // MARK: The tap

    private func handle(_ message: TapMessage) {
        // Messages come from the tap thread, the timeout queue and `endHold`, so they can arrive
        // out of order. Every phase change raises the generation; anything older is stale.
        guard message.generation >= latestGeneration else { return }
        latestGeneration = message.generation
        switch message.event {
        case .cycleStarted:
            startCycle()
        case .pickingStarted:
            phase = .picking(session: message.generation)
            pickingStartedAt = .now
            present(session: message.generation, snapshot: watcher.current)
        case .key(let code):
            key(code, session: message.generation)
        case .backToCycling:
            backToCycling()
        case .cycleEnded, .pickingEnded:
            reset()
        }
    }

    private func startCycle() {
        reset()
        phase = .cycling
        watcher.begin()
    }

    /// Opens the list for the highlighted app, or lets the Dock finish natively when that app has
    /// one window or none. The highlight is read again here, because AX can lag a fast Tab.
    private func present(session: UInt64, snapshot: SwitcherSnapshot?) {
        guard let snapshot else {
            // The switcher has gone already (a click, say): only the ⌘ release is owed.
            end(.releaseOnly, session: session)
            return
        }
        guard let item = snapshot.selected, let pid = item.pid,
              let windows = windowsByPid[pid], windows.count >= 2,
              let screen = screen(containing: snapshot.frame)
        else {
            end(.confirm, session: session)
            return
        }
        listed = (pid, windows)
        list.show(windows: windows.map(Self.listItem), switcherFrame: snapshot.frame,
                  iconFrame: item.frame, screen: screen)
        let epoch = epoch
        index.watch(pid: pid) { [weak self] windows in
            self?.listedWindowsChanged(windows, pid: pid, epoch: epoch)
        }
        logger.info("Picking: listing \(windows.count, privacy: .public) windows")
    }

    private func key(_ code: UInt16, session: UInt64) {
        guard phase == .picking(session: session), let listed,
              let action = list.handle(keyCode: code) else { return }
        switch action {
        case .moveHighlight:
            break
        case .cancel:
            end(.cancel, session: session)
        case .pick(let index):
            guard listed.windows.indices.contains(index) else { return }
            let window = listed.windows[index]
            if index == 0, !window.isMinimized, watcher.current?.selected?.pid == listed.pid {
                // Exactly native: the Dock finishes the switch, which brings this window forward.
                // Only while the Dock still highlights this app, since the pointer can move it.
                end(.confirm, session: session)
            } else if end(.cancel, session: session) {
                logger.info("Picked window \(index + 1, privacy: .public) of \(listed.windows.count, privacy: .public)")
                let pid = listed.pid
                Task {
                    try? await Task.sleep(for: Self.focusDelay)
                    Focuser.focus(pid: pid, window: window.element)
                }
            }
        }
    }

    private func backToCycling() {
        guard case .picking = phase else {
            startCycle()
            return
        }
        list.hide()
        listed = nil
        phase = .cycling
        // Stops the window watch. Loads still pending go with it, so ask again for the apps
        // that have no count yet.
        index.cancel()
        epoch += 1
        requestedPids = Set(windowsByPid.keys)
        if let snapshot = watcher.current {
            loadCounts(snapshot)
            showDots(snapshot)
        }
        highlightLeaving = watcher.current?.selectedIndex
        tap.holdOnRelease = false
    }

    /// Ends the tap's Picking session and hides everything at once, together with the switcher.
    /// False means the tap has already left that session (a timeout, or ⌘⇥ again); its own
    /// message follows and drives what happens next.
    @discardableResult
    private func end(_ how: HoldEnd, session: UInt64) -> Bool {
        guard tap.endHold(how, session: session) else { return false }
        reset()
        return true
    }

    /// Back to Idle: nothing on screen, nothing observed, no window data kept.
    private func reset() {
        phase = .idle
        listed = nil
        epoch += 1
        list.hide()
        dots.hide()
        watcher.end()
        index.cancel()
        windowsByPid = [:]
        requestedPids = []
        pickingStartedAt = nil
        highlightLeaving = nil
        tap.holdOnRelease = false
    }

    // MARK: The switcher and the windows

    private func switcherChanged(_ snapshot: SwitcherSnapshot) {
        guard phase != .idle else { return }
        loadCounts(snapshot)
        showDots(snapshot)
        updateHoldOnRelease(snapshot)
        // During Picking the Dock's highlight moves when AX catches up with a fast Tab, when the
        // listed app's icon goes away, or when the pointer hovers over another icon. Only the
        // first two make the list follow the Dock, also onto an icon with no pid, which `present`
        // lets the Dock finish natively.
        if case .picking(let session) = phase, let listed,
           let selected = snapshot.selected, selected.pid != listed.pid {
            if Self.isGone(listed.pid) {
                end(.cancel, session: session)
            } else if let started = pickingStartedAt, ContinuousClock.now - started < Self.highlightCatchUp {
                present(session: session, snapshot: snapshot)
            }
        }
    }

    private func switcherClosed() {
        guard phase != .idle else { return }
        // Any click closes the native switcher, even one on our own panel. Nothing is left for the
        // Dock to finish or cancel, and Esc would reach the front app, so only the ⌘ release goes.
        if case .picking(let session) = phase {
            tap.endHold(.releaseOnly, session: session)
        }
        reset()
    }

    /// Reads the windows of every listed app not asked about yet, in parallel.
    private func loadCounts(_ snapshot: SwitcherSnapshot) {
        var pids: [pid_t] = []
        for item in snapshot.items {
            if let pid = item.pid, requestedPids.insert(pid).inserted { pids.append(pid) }
        }
        guard !pids.isEmpty else { return }
        let epoch = epoch
        index.load(pids: pids) { [weak self] pid, windows in
            self?.windowsLoaded(windows, pid: pid, epoch: epoch)
        }
    }

    private func windowsLoaded(_ windows: [AppWindow], pid: pid_t, epoch: Int) {
        guard epoch == self.epoch, phase != .idle else { return }
        windowsByPid[pid] = windows
        guard let snapshot = watcher.current else { return }
        showDots(snapshot)
        updateHoldOnRelease(snapshot)
    }

    private func listedWindowsChanged(_ windows: [AppWindow], pid: pid_t, epoch: Int) {
        guard epoch == self.epoch, case .picking(let session) = phase, listed?.pid == pid else { return }
        windowsByPid[pid] = windows
        if Self.isGone(pid) {
            end(.cancel, session: session)
        } else if windows.count < 2 {
            end(.confirm, session: session)
        } else {
            listed?.windows = windows
            list.update(windows: windows.map(Self.listItem))
            if let snapshot = watcher.current { showDots(snapshot) }
        }
    }

    private func showDots(_ snapshot: SwitcherSnapshot) {
        let icons = snapshot.items.map { item in
            (frame: item.frame, windowCount: item.pid.flatMap { windowsByPid[$0]?.count } ?? 0)
        }
        if icons.contains(where: { $0.windowCount >= 2 }) {
            dots.show(switcherFrame: snapshot.frame, icons: icons)
        } else {
            dots.hide()
        }
    }

    /// Releasing ⌘ holds the switcher only on an app already known to have two or more windows.
    /// Until its windows are read, a release stays native.
    private func updateHoldOnRelease(_ snapshot: SwitcherSnapshot?) {
        if let leaving = highlightLeaving {
            guard let snapshot, snapshot.selectedIndex != leaving else {
                tap.holdOnRelease = false
                return
            }
            highlightLeaving = nil
        }
        let count = snapshot?.selected?.pid.flatMap { windowsByPid[$0]?.count } ?? 0
        tap.holdOnRelease = count >= 2
    }

    private func screen(containing frame: CGRect) -> NSScreen? {
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(centre) } ?? NSScreen.main
    }

    private static func listItem(_ window: AppWindow) -> WindowListItem {
        WindowListItem(title: window.title, isMinimized: window.isMinimized)
    }

    private static func isGone(_ pid: pid_t) -> Bool {
        if kill(pid, 0) == -1, errno == ESRCH { return true }
        return NSRunningApplication(processIdentifier: pid)?.isTerminated ?? true
    }
}
