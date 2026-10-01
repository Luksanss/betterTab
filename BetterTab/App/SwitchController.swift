import AppKit

/// Ties the key tap to the switcher reader, the window index and the stack edges, and hands ⌘§ to
/// `WindowSwitchController` (docs/spec.md § ⌘⇥: stack edges, § States). Main actor only. ⌘⇥ itself
/// is native; this only draws over it.
final class SwitchController {
    /// Sendable, so AppDelegate can stop it at quit.
    private(set) lazy var tap: KeyTap = KeyTap { [weak self] message in self?.handle(message) }

    private let watcher = SwitcherWatcher()
    private let index = WindowIndex()
    private let stackEdges = StackEdgesOverlay()
    /// ⌘§. It shares the index, so the element cache warmed while cycling serves it too.
    private lazy var windowSwitch = WindowSwitchController(tap: tap, index: index)

    private enum Phase: Equatable {
        case idle, cycling
    }

    private var phase = Phase.idle {
        didSet { publishForSelfTest() }
    }
    /// The newest tap generation seen. Messages older than it are late and dropped.
    private var latestGeneration: UInt64 = 0
    /// Each app's real windows on every Space, only while the switcher is open. Only the counts
    /// are used.
    private var windowsByPid: [pid_t: [AppWindow]] = [:]
    private var requestedPids: Set<pid_t> = []
    /// Bumped whenever results already asked of the index go stale.
    private var epoch = 0

    init() {
        watcher.onChange = { [weak self] snapshot in self?.switcherChanged(snapshot) }
        watcher.onClose = { [weak self] in self?.reset() }
        watcher.onLookupFinished = { found in AppStatus.shared.switcherLookup(succeeded: found) }
    }

    /// Runs the tap exactly while BetterTab has the Accessibility permission.
    func statusChanged() {
        if AppStatus.shared.state == .needsPermission {
            tap.stop()
        } else {
            tap.start()
            // Once only: the index ignores later calls.
            index.warmUp(pids: Self.regularAppPids())
        }
    }

    // MARK: The tap

    private func handle(_ message: TapMessage) {
        // Messages come from the tap thread and from `stop()`, so they can arrive out of order.
        // Every phase change raises the generation; anything older is stale.
        guard message.generation >= latestGeneration else { return }
        latestGeneration = message.generation
        switch message.event {
        case .cycleStarted:
            startCycle()
        case .cycleEnded:
            reset()
        case .key(let code):
            windowSwitch.key(code, session: message.generation)
        case .windowsStarted(let backwards):
            reset()
            windowSwitch.start(session: message.generation, backwards: backwards)
        case .windowStep(let delta):
            windowSwitch.step(by: delta, session: message.generation)
        case .windowsEnded(let commit):
            windowSwitch.ended(commit: commit)
        }
    }

    private func startCycle() {
        reset()
        phase = .cycling
        // Every app, not just those the switcher lists, so the counts are ready by the time it
        // appears (150–210 ms later).
        load(Self.regularAppPids())
        watcher.begin()
    }

    /// Back to Idle: nothing on screen, nothing observed, no window data kept. Ends ⌘§ too.
    private func reset() {
        windowSwitch.reset()
        phase = .idle
        epoch += 1
        stackEdges.hide()
        watcher.end()
        index.cancel()
        windowsByPid = [:]
        requestedPids = []
    }

    // MARK: The switcher and the windows

    private func switcherChanged(_ snapshot: SwitcherSnapshot) {
        guard phase != .idle else { return }
        // Backstop for a switcher icon whose app wasn't among the regular apps at ⌘⇥.
        load(snapshot.items.compactMap(\.pid))
        showStackEdges(snapshot)
    }

    /// Reads the windows of the apps not asked about yet, in parallel. Each app's result can come
    /// more than once, as windows turn out not to be standard ones.
    private func load(_ pids: [pid_t]) {
        let pids = pids.filter { requestedPids.insert($0).inserted }
        guard !pids.isEmpty else { return }
        let epoch = epoch
        index.load(pids: pids) { [weak self] pid, windows in
            self?.windowsLoaded(windows, pid: pid, epoch: epoch)
        }
    }

    private func windowsLoaded(_ windows: [AppWindow], pid: pid_t, epoch: Int) {
        guard epoch == self.epoch, phase != .idle else { return }
        windowsByPid[pid] = windows
        if let snapshot = watcher.current { showStackEdges(snapshot) }
    }

    private func showStackEdges(_ snapshot: SwitcherSnapshot) {
        let icons = snapshot.items.map { item in
            (frame: item.frame, windowCount: item.pid.flatMap { windowsByPid[$0]?.count } ?? 0)
        }
        if icons.contains(where: { $0.windowCount >= 2 }) {
            stackEdges.show(switcherFrame: snapshot.frame, icons: icons)
        } else {
            stackEdges.hide()
        }
    }

    /// What the self-test reads (Debug builds only): the phase.
    private func publishForSelfTest() {
        #if DEBUG
        switch phase {
        case .idle: SelfTestHooks.phase = "idle"
        case .cycling: SelfTestHooks.phase = "cycling"
        }
        #endif
    }

    private static func regularAppPids() -> [pid_t] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map(\.processIdentifier)
    }
}
