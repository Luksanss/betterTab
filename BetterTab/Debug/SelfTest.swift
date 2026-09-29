#if DEBUG
import AppKit
import Synchronization
import os

/// A weak reference, so the panels can list themselves for the self-test without being kept alive.
struct SelfTestWeak<Object: AnyObject> {
    weak var object: Object?
}

/// Drives the real ⌘⇥ flow with synthetic keys and writes a pass/fail report. Debug builds only.
///
/// Start it with `--self-test <report.json>` (plus `--long` for the 15 s timeout, `--pause <s>` to
/// hold at checkpoints) or from Debug › Run Self-Test. Keyboard only. Letters, arrows and Return
/// are posted only while the list is open, so they can't reach a real app.
final class SelfTest {
    private static var running: SelfTest?

    static func start(_ options: SelfTestOptions, tap: KeyTap) {
        guard running == nil else {
            selfTestLog.notice("a self-test is already running")
            return
        }
        let test = SelfTest(options: options, tap: tap)
        running = test
        Task {
            await test.run()
            running = nil
        }
    }

    enum Stop: Error {
        /// The scenario ran out of time; the run goes on.
        case scenarioTimeout
        /// The whole run ends.
        case run(result: String, finding: String)
    }

    let options: SelfTestOptions
    let tap: KeyTap
    let keys = SelfTestKeys()
    let recorder: SelfTestRecorder
    let dockPid: Int32?
    private var watchdog: SelfTestWatchdog?
    private let startedAt = ContinuousClock.now

    var match = SelfTestAppMatch()
    var origin: NSRunningApplication?
    var home: NSRunningApplication?
    var targets = SelfTestTargets()
    /// Real windows per app, from SkyLight, in its order.
    var windowsByPid: [Int32: [SelfTestWindow]] = [:]
    var bundleByPid: [Int32: String] = [:]
    var dockIgnoresSyntheticKeys = false
    var sawNonIdlePhase = false
    var sawDots = false
    private var clickSeen = false
    /// Set while `clean` runs, so no stop can cut it off between a ⌘ down and its ⌘ up.
    private var cleaning = false
    /// When the last release that opened a list was posted.
    var lastReleaseAt: ContinuousClock.Instant?

    private init(options: SelfTestOptions, tap: KeyTap) {
        self.options = options
        self.tap = tap
        dockPid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        let report = SelfTestReport(
            macOS: ProcessInfo.processInfo.operatingSystemVersionString,
            startedAt: Date().ISO8601Format(),
            options: .init(long: options.long, pauseSeconds: options.pauseSeconds, trigger: options.trigger))
        recorder = SelfTestRecorder(url: options.reportURL(relativeTo: FileManager.default.currentDirectoryPath),
                                    report: report)
    }

    // MARK: The run

    private func run() async {
        selfTestLog.notice("self-test starting; report at \(self.recorder.url.path, privacy: .public)")
        recorder.update { _ in }
        let limit: Double = options.long ? 120 : 90
        let watchdog = SelfTestWatchdog(seconds: limit) { [keys, recorder, dockPid, quit = options.quitWhenDone] in
            selfTestLog.error("self-test watchdog fired after \(Int(limit), privacy: .public) s")
            let actions = selfTestEmergencyRelease(keys: keys, dockPid: dockPid)
            recorder.update { $0.notes.append("watchdog: \(actions.isEmpty ? "nothing was held" : actions.joined(separator: ", "))") }
            recorder.finish(result: "watchdog", finding: "The run passed its \(Int(limit)) s limit; the watchdog let go of ⌘ and ended it.")
            guard quit else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { NSApp.terminate(nil) } }
            // If the main thread is stuck, SIGTERM stops the key tap (posting any owed ⌘ release) and exits.
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { kill(getpid(), SIGTERM) }
        }
        self.watchdog = watchdog
        watchdog.start()

        var stop: (result: String, finding: String)?
        do {
            try await prepare()
            try await runScenarios()
        } catch Stop.run(let result, let finding) {
            stop = (result, finding)
        } catch {
            stop = ("aborted", "unexpected error: \(error)")
        }
        await finish(stop)
    }

    private func prepare() async throws {
        try checkScreen(before: "anything was run")
        guard try await waitFor(5, every: 0.1, nil, { AppStatus.shared.state == .active }) != nil else {
            if AppStatus.shared.state == .needsPermission {
                throw Stop.run(result: "no Accessibility permission", finding: "BetterTab isn't trusted for Accessibility, so nothing was run.")
            }
            throw Stop.run(result: "switcher not found", finding: "BetterTab's status is “Can’t find the ⌘⇥ switcher”, so nothing was run.")
        }
        // The tap is created on its own thread once the permission is known.
        try await sleep(0.3, nil)

        let others = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != getpid()
                && ($0.bundleIdentifier == Bundle.main.bundleIdentifier || $0.bundleIdentifier == "com.luksanss.BetterTab.Experiment")
        }
        guard others.isEmpty else {
            throw Stop.run(result: "aborted", finding: "Another BetterTab or the Experiment harness is running; two key taps would both act on ⌘⇥. Quit it first.")
        }
        guard dockPid != nil else { throw Stop.run(result: "aborted", finding: "The Dock isn't running.") }
        guard SelfTestSkyLight.isAvailable else {
            throw Stop.run(result: "aborted", finding: "SkyLight's window-list symbols are missing, so windows can't be counted.")
        }

        origin = try await findOrigin()
        try await takeInventory()

        let candidates = bundleByPid.map { pid, bundle in
            SelfTestCandidate(pid: pid, bundleID: bundle, windows: windowsByPid[pid]?.count ?? 0)
        }
        targets = SelfTestPlan.pickTargets(candidates, origin: origin?.processIdentifier)
        home = targets.home.flatMap { NSRunningApplication(processIdentifier: $0) }
        let roles: [(String, Int32?)] = [
            ("origin", origin?.processIdentifier), ("home", targets.home), ("multi", targets.multi),
            ("single", targets.single), ("second", targets.second),
        ]
        let reports = roles.compactMap { role, pid in
            pid.map { SelfTestTargetReport(role: role, bundleID: bundle($0), windows: windowsByPid[$0]?.count ?? 0) }
        }
        let notes = targets.notes
        recorder.update { report in
            report.targets = reports
            report.notes.append(contentsOf: notes)
        }
        guard home != nil else {
            throw Stop.run(result: "aborted", finding: "No regular app to start the scenarios from.")
        }
    }

    /// The app in front when the run starts. `open` without `-g` brings BetterTab itself forward.
    private func findOrigin() async throws -> NSRunningApplication? {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() {
            NSApp.deactivate()
            _ = try await waitFor(1, nil) { self.frontPid != getpid() }
        }
        if let front = NSWorkspace.shared.frontmostApplication, front.activationPolicy == .regular,
           front.processIdentifier != getpid() {
            return front
        }
        // Fall back to the owner of the frontmost normal window.
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for window in windows where (window[kCGWindowLayer as String] as? Int) == 0 {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32, pid != getpid(),
                  let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular
            else { continue }
            app.activate(options: [])
            _ = try await waitFor(2, nil) { self.frontPid == pid }
            recorder.update { $0.notes.append("no regular app was in front, so the owner of the frontmost window became the origin") }
            return app
        }
        return nil
    }

    private func takeInventory() async throws {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != getpid() && !$0.isTerminated
        }
        var match = SelfTestAppMatch()
        for app in apps {
            if let url = app.bundleURL { match.byPath[SelfTestAppMatch.normalized(url)] = app.processIdentifier }
            if let name = app.localizedName, match.byName[name] == nil { match.byName[name] = app.processIdentifier }
            bundleByPid[app.processIdentifier] = app.bundleIdentifier ?? "(no bundle id)"
        }
        self.match = match
        refreshWindows()

        let pids = Array(bundleByPid.keys)
        let axCounts = await selfTestOffMain { () -> [Int32: Int] in
            let counts = Mutex([Int32: Int]())
            DispatchQueue.concurrentPerform(iterations: pids.count) { index in
                guard let count = SelfTestAX.standardWindowCount(pid: pids[index]) else { return }
                counts.withLock { $0[pids[index]] = count }
            }
            return counts.withLock { $0 }
        }
        let current = Set(SelfTestSkyLight.currentSpaces())
        var inventory: [SelfTestInventoryApp] = []
        for (pid, bundle) in bundleByPid {
            let windows = windowsByPid[pid] ?? []
            let elsewhere = windows.filter { window in
                Set(SelfTestSkyLight.spaces(of: window.id)).isDisjoint(with: current)
            }
            inventory.append(SelfTestInventoryApp(
                bundleID: bundle, windows: windows.count,
                minimized: windows.filter(\.minimized).count,
                fullScreen: windows.filter(\.fullScreen).count,
                offCurrentSpace: elsewhere.count,
                axStandardWindows: axCounts[pid]))
        }
        inventory.sort { $0.windows != $1.windows ? $0.windows > $1.windows : $0.bundleID < $1.bundleID }
        recorder.update { $0.inventory = inventory }
        let summary = inventory.filter { $0.windows > 0 }.map { "\($0.bundleID) \($0.windows)" }.joined(separator: ", ")
        selfTestLog.notice("inventory: \(summary, privacy: .public)")
    }

    /// SkyLight's real windows for every app in the inventory. About a millisecond.
    func refreshWindows() {
        windowsByPid = Dictionary(grouping: SelfTestSkyLight.realWindows(of: Set(bundleByPid.keys)), by: \.pid)
    }

    private func finish(_ stop: (result: String, finding: String)?) async {
        if watchdog?.hasFired != true {
            if let actions = try? await clean(nil), !actions.isEmpty {
                recorder.update { $0.notes.append("final cleanup: \(actions.joined(separator: ", "))") }
            }
            // Restoring can fall back to a ⌘⇥, which mustn't reach a lock screen.
            if let origin, !origin.isTerminated, frontPid != origin.processIdentifier, Self.screenLockReason() == nil {
                let restored = (try? await bringToFront(origin, nil)) ?? false
                recorder.update { $0.notes.append(restored ? "origin app restored" : "couldn't bring the origin app back to the front") }
            }
        }
        watchdog?.stop()

        var notes: [String] = []
        let elapsed = Self.seconds(since: startedAt)
        if SelfTestKeys.secondsSinceMouse(clicks: false) < elapsed {
            notes.append("the mouse moved during the run; hovering over the switcher can move its highlight")
        }
        var finding = stop?.finding
        if finding == nil, !dockIgnoresSyntheticKeys, !sawNonIdlePhase {
            finding = sawDots
                ? "SelfTestHooks.phase never left “idle” although dots were drawn: the controller isn't writing the hooks."
                : "The controller never left Idle and drew no dots: BetterTab's key tap may not be running (Input Monitoring?), or the hooks aren't wired."
        }
        recorder.update { $0.notes.append(contentsOf: notes) }
        recorder.finish(result: stop?.result, finding: finding)
        if options.quitWhenDone { NSApp.terminate(nil) }
    }

    // MARK: Scenarios

    /// Runs one scenario with its own time limit, cleans up after it and records the result.
    func scenario(_ name: String, timeout: Double = 12, skip: String? = nil,
                  _ body: (ScenarioRun) async throws -> Void) async throws {
        let run = ScenarioRun(name: name, timeout: timeout)
        if let skip {
            run.skip(skip)
        } else {
            do {
                do {
                    try checkScreen(before: "scenario \(name)")
                    try await body(run)
                } catch Stop.scenarioTimeout {
                    run.fail("timed out after \(Int(timeout)) s")
                }
                if !run.keepListOpen {
                    let actions = try await clean(nil)
                    if !actions.isEmpty { run.note("cleanup: \(actions.joined(separator: ", "))") }
                }
            } catch let stop as Stop {
                if case .run(_, let finding) = stop { run.fail("run stopped: \(finding)") }
                record(run)
                throw stop
            }
        }
        record(run)
    }

    private func record(_ run: ScenarioRun) {
        let result = SelfTestScenarioResult(
            name: run.name, pass: run.skipReason == nil && run.failures.isEmpty, skipped: run.skipReason != nil,
            detail: run.detail, ms: run.ms, durationMs: Self.ms(since: run.started))
        recorder.update { $0.add(result) }
        let status = result.skipped ? "SKIP" : result.pass ? "PASS" : "FAIL"
        selfTestLog.notice("""
            \(status, privacy: .public) \(result.name, privacy: .public) \
            (\(result.ms.map { "\($0) ms" } ?? "no latency", privacy: .public)): \(result.detail, privacy: .public)
            """)
    }

    /// Holds for `--pause` seconds so screenshots can be taken from a shell.
    func checkpoint(_ name: String, _ run: ScenarioRun) async throws {
        let seconds = options.pauseSeconds
        guard seconds > 0 else { return }
        selfTestLog.notice("checkpoint \(name, privacy: .public): holding \(seconds, privacy: .public) s")
        recorder.update { $0.checkpoint = name }
        watchdog?.extend(by: seconds)
        run.deadline += .milliseconds(Int(seconds * 1000))
        try await sleep(seconds, run)
        recorder.update { $0.checkpoint = nil }
    }

    // MARK: Waiting

    /// Throws when the watchdog has fired, the screen is locked, someone clicked, or the scenario
    /// is out of time. During `clean` only the watchdog and the scenario's time can stop it.
    func checkStop(_ run: ScenarioRun?) throws {
        if watchdog?.hasFired == true { throw Stop.run(result: "watchdog", finding: "The watchdog ended the run.") }
        if !cleaning { try checkScreen(before: "the next key") }
        let elapsed = Self.seconds(since: startedAt)
        // Once only, so the cleanup after it can still wait for things to settle; a click during
        // `clean` is reported at the next check after it.
        if !cleaning, !clickSeen, elapsed > 0.5, SelfTestKeys.secondsSinceMouse(clicks: true) < elapsed - 0.1 {
            clickSeen = true
            throw Stop.run(result: "aborted", finding: "A mouse click during the run: someone is using the Mac, and a click closes the switcher.")
        }
        if let run, ContinuousClock.now > run.deadline { throw Stop.scenarioTimeout }
    }

    /// Synthetic keys would go to the lock screen or the screen saver, so the run stops.
    func checkScreen(before step: String) throws {
        guard let reason = Self.screenLockReason() else { return }
        selfTestLog.error("self-test stopped before \(step, privacy: .public): \(reason, privacy: .public)")
        throw Stop.run(result: "screen locked", finding: """
            \(reason.prefix(1).uppercased() + reason.dropFirst()), so the run stopped before \(step): synthetic keys \
            would have gone to the lock screen.
            """)
    }

    /// Why keys mustn't be posted now, or nil: the screen is locked, the screen saver is running,
    /// or this session isn't the one on the console.
    static func screenLockReason() -> String? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return "there's no window-server session"
        }
        if (session["CGSSessionScreenIsLocked"] as? Bool) == true { return "the screen is locked" }
        if (session["kCGSSessionOnConsoleKey"] as? Bool) == false { return "this session isn't on the console" }
        let lockApps = ["com.apple.loginwindow", "com.apple.ScreenSaver.Engine"]
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.ScreenSaver.Engine").isEmpty {
            return "the screen saver is running"
        }
        if let front = NSWorkspace.shared.frontmostApplication,
           lockApps.contains(front.bundleIdentifier ?? "")
            || ["loginwindow", "ScreenSaverEngine"].contains(front.executableURL?.lastPathComponent ?? "") {
            return "\(front.executableURL?.lastPathComponent ?? "loginwindow") is in front"
        }
        return nil
    }

    func sleep(_ seconds: Double, _ run: ScenarioRun?) async throws {
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
        try checkStop(run)
    }

    /// Polls until `condition` holds. Returns the milliseconds it took, or nil after `timeout`.
    func waitFor(_ timeout: Double, every interval: Double = 0.02, _ run: ScenarioRun?,
                 _ condition: () async -> Bool) async throws -> Int? {
        let start = ContinuousClock.now
        while true {
            if await condition() { return Self.ms(since: start) }
            if Self.seconds(since: start) >= timeout { return nil }
            try await sleep(interval, run)
        }
    }

    static func ms(since start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }

    static func seconds(since start: ContinuousClock.Instant) -> Double {
        Double(ms(since: start)) / 1000
    }

    // MARK: Observing

    var frontPid: Int32? { NSWorkspace.shared.frontmostApplication?.processIdentifier }

    var phase: String {
        let phase = SelfTestHooks.phase
        if phase != "idle" { sawNonIdlePhase = true }
        return phase
    }

    /// The controller's list: the preview's accepts the mouse, the controller's doesn't.
    var list: WindowList.DebugState? {
        WindowList.debugStates.first { !$0.acceptsMouse }
    }

    var listVisible: Bool { list?.isVisible ?? false }

    var dots: DotsOverlay.DebugState? {
        let states = DotsOverlay.debugStates
        let state = states.first(where: \.isVisible) ?? states.first
        if state?.isVisible == true { sawDots = true }
        return state
    }

    func switcher(items: Bool = false) async -> SelfTestSwitcher? {
        guard let dockPid else { return nil }
        let match = match
        return await selfTestOffMain { SelfTestAX.switcher(dockPid: dockPid, match: match, withItems: items) }
    }

    func focusedWindow(_ pid: Int32) async -> UInt32? {
        await selfTestOffMain { SelfTestAX.focusedWindow(pid: pid) }
    }

    func isOnCurrentSpace(_ window: UInt32) -> Bool {
        !Set(SelfTestSkyLight.spaces(of: window)).isDisjoint(with: SelfTestSkyLight.currentSpaces())
    }

    func bundle(_ pid: Int32?) -> String {
        guard let pid else { return "none" }
        if pid == getpid() { return "BetterTab" }
        return bundleByPid[pid] ?? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "unknown app"
    }

    /// AX's top-left global rect in AppKit's bottom-left coordinates.
    func appKitRect(_ rect: CGRect) -> CGRect {
        let screens = NSScreen.screens
        let height = (screens.first { $0.frame.origin == .zero } ?? screens.first)?.frame.height ?? 0
        return CGRect(x: rect.minX, y: height - rect.minY - rect.height, width: rect.width, height: rect.height)
    }

    // MARK: Driving

    /// Brings the home app to the front, where every scenario starts.
    func restoreHome(_ run: ScenarioRun) async throws -> Bool {
        guard let home, !home.isTerminated else {
            run.fail("the home app is gone")
            return false
        }
        if frontPid == home.processIdentifier { return true }
        // Coming back from another Space, the Dock shows no switcher until the slide is over. The
        // slide starts after the app is frontmost, so decide from where home's windows are now.
        let windows = windowsByPid[home.processIdentifier] ?? []
        let slides = !windows.isEmpty && !windows.contains { isOnCurrentSpace($0.id) }
        guard try await bringToFront(home, run) else {
            run.fail("couldn't bring the home app (\(bundle(home.processIdentifier))) to the front; frontmost is \(bundle(frontPid))")
            return false
        }
        // Let the Dock's app order settle before the next ⌘⇥.
        try await sleep(slides ? 1.2 : 0.25, run)
        return true
    }

    /// `activate` is only a request since macOS 14. If it's ignored, a quick ⌘⇥ tap (always
    /// native) goes back to the previous app, which is `app` whenever a scenario has just left it.
    func bringToFront(_ app: NSRunningApplication, _ run: ScenarioRun?) async throws -> Bool {
        let pid = app.processIdentifier
        app.activate(options: [])
        if try await waitFor(1, nil, { self.frontPid == pid }) != nil { return true }
        app.activate(options: [.activateAllWindows])
        if try await waitFor(0.7, nil, { self.frontPid == pid }) != nil { return true }
        guard !keys.isCommandHeld, await switcher() == nil, phase == "idle", Self.screenLockReason() == nil
        else { return false }
        let keys = keys
        _ = await selfTestOffMain { keys.quickCommandTab(gap: 0.012) }
        let back = try await waitFor(1, nil) { self.frontPid == pid } != nil
        run?.note(back ? "activate was ignored; a quick ⌘⇥ brought \(bundle(pid)) back" : "activate was ignored, and a quick ⌘⇥ didn't help")
        return back
    }

    /// ⌘ down, then Tab. Returns the Dock's switcher once it's up, within 1 s.
    func openSwitcher(_ run: ScenarioRun) async throws -> SelfTestSwitcher? {
        keys.commandDown()
        try await sleep(0.04, run)
        keys.press(SelfTestKeys.tab)
        var found: SelfTestSwitcher?
        guard let ms = try await waitFor(1, every: 0.03, run, {
            found = await self.switcher(items: true)
            return found != nil
        }), let found else {
            run.fail("no switcher within 1 s of ⌘⇥")
            return nil
        }
        run.note("switcher up after \(ms) ms")
        return found
    }

    /// Tabs until the Dock highlights `pid`.
    func highlight(_ pid: Int32, in switcher: SelfTestSwitcher, _ run: ScenarioRun) async throws -> Bool {
        var items = switcher.items
        var index = items.firstIndex { $0.pid == pid }
        // An icon read while the switcher was still appearing may not be matched to its app yet.
        for _ in 0..<3 where index == nil {
            try await sleep(0.1, run)
            items = await self.switcher(items: true)?.items ?? items
            index = items.firstIndex { $0.pid == pid }
        }
        guard let index else {
            run.fail("\(bundle(pid)) isn't among the switcher's \(items.count) icons")
            return false
        }
        for _ in 0..<3 {
            var current: SelfTestSwitcher?
            _ = try await waitFor(0.5, run) {
                current = await self.switcher()
                return current?.selected != nil || current == nil
            }
            guard let current else {
                run.fail("the switcher closed while tabbing")
                return false
            }
            guard let selected = current.selected else { continue }
            if selected == index { return true }
            // Without ⌘ a Tab would reach the front app.
            guard keys.isCommandHeld else {
                run.fail("⌘ isn't held, so no Tab was posted")
                return false
            }
            for _ in 0..<SelfTestPlan.tabs(from: selected, to: index, count: current.count) {
                keys.press(SelfTestKeys.tab)
                try await sleep(0.04, run)
            }
            if try await waitFor(0.8, run, { await self.switcher()?.selected == index }) != nil { return true }
        }
        run.fail("the highlight didn't reach \(bundle(pid)) (icon \(index + 1))")
        return false
    }

    /// Gives the controller time to read the highlighted app, then waits for it to arm the hold.
    func holdReady(_ run: ScenarioRun) async throws -> Bool {
        try await sleep(0.25, run)
        guard try await waitFor(1.5, run, { self.tap.holdOnRelease }) != nil else {
            run.fail("holdOnRelease never set: the controller doesn't know the highlighted app has ≥ 2 windows")
            return false
        }
        return true
    }

    /// Releases ⌘ and waits up to 500 ms for Picking with the list showing `pid`'s windows.
    func release(expecting pid: Int32, _ run: ScenarioRun) async throws -> (ids: [UInt32], ms: Int)? {
        lastReleaseAt = .now
        keys.commandUp()
        guard let ms = try await waitFor(0.5, every: 0.01, run, { self.phase == "picking" && self.listVisible }) else {
            let up = await switcher() != nil
            run.fail("no list within 500 ms of the release (phase \(phase), list visible \(listVisible), switcher up \(up))")
            return nil
        }
        run.check(SelfTestHooks.listedPid == pid,
                  "the list shows \(bundle(SelfTestHooks.listedPid)), not \(bundle(pid))")
        return (SelfTestHooks.listedWindowIDs, ms)
    }

    /// From home: ⌘⇥ to `pid`, wait for the hold to arm, release. Returns the listed window ids
    /// and how long after the release the list appeared.
    func openList(on pid: Int32, _ run: ScenarioRun) async throws -> (ids: [UInt32], ms: Int)? {
        guard try await restoreHome(run),
              let switcher = try await openSwitcher(run),
              try await highlight(pid, in: switcher, run),
              try await holdReady(run),
              let opened = try await release(expecting: pid, run)
        else { return nil }
        run.note("list open \(opened.ms) ms after the release")
        return opened
    }

    /// Posts `key` only while the list is open, so it can never reach a real app.
    func pressInList(_ key: CGKeyCode, _ run: ScenarioRun) -> Bool {
        guard phase == "picking", listVisible, !keys.isCommandHeld else {
            run.fail("didn't post a key: the list isn't open (phase \(phase), list visible \(listVisible))")
            return false
        }
        if let reason = Self.screenLockReason() {
            run.fail("didn't post a key: \(reason)")
            return false
        }
        keys.press(key)
        return true
    }

    func checkCommandUp(_ run: ScenarioRun) async throws {
        let up = try await waitFor(0.5, run) {
            let state = SelfTestKeys.commandState()
            return !state.hid && !state.session
        }
        if up == nil {
            let state = SelfTestKeys.commandState()
            run.fail("⌘ still down (HID \(state.hid), session \(state.session))")
        }
    }

    /// Waits for the list and the switcher to close and the controller to be idle.
    func waitForIdle(_ timeout: Double, _ run: ScenarioRun) async throws -> Int? {
        try await waitFor(timeout, every: 0.01, run) {
            guard !self.listVisible, self.phase == "idle" else { return false }
            return await self.switcher() == nil
        }
    }

    /// Leaves nothing held: ends Picking or Cycling and makes sure ⌘ is up. Returns what it did.
    /// The gaps inside a ⌘ tap or an Esc-then-⌘-up can't throw, so a stop never leaves ⌘ down.
    func clean(_ run: ScenarioRun?) async throws -> [String] {
        cleaning = true
        defer { cleaning = false }
        var actions: [String] = []
        var up = await switcher() != nil
        if phase == "picking" || (up && !keys.isCommandHeld) {
            // A ⌘ press and release ends Picking in the tap itself, whatever the list shows.
            if keys.isCommandHeld {
                keys.commandUp()
            } else {
                keys.commandDown()
                try? await Task.sleep(for: .milliseconds(40))
                keys.commandUp()
            }
            actions.append("⌘ tap to end Picking")
            _ = try await waitFor(1, run) {
                guard self.phase != "picking" else { return false }
                return await self.switcher() == nil
            }
            up = await switcher() != nil
        }
        if keys.isCommandHeld {
            // Cycling: Esc makes the Dock cancel, then ⌘ goes up.
            if up {
                keys.press(SelfTestKeys.escape)
                actions.append("Esc with ⌘")
                try? await Task.sleep(for: .milliseconds(40))
            }
            keys.commandUp()
            actions.append("⌘ up")
        }
        let flagsUp = try await waitFor(0.5, run) {
            let state = SelfTestKeys.commandState()
            return !state.hid && !state.session
        }
        if flagsUp == nil {
            keys.commandUp()
            actions.append("extra ⌘ up: the flags showed ⌘ down")
        }
        if try await waitFor(1, run, { await self.switcher() == nil }) == nil {
            actions.append("the switcher is still up")
        }
        return actions
    }
}

/// One scenario's findings.
final class ScenarioRun {
    let name: String
    let started = ContinuousClock.now
    var deadline: ContinuousClock.Instant
    private(set) var notes: [String] = []
    private(set) var failures: [String] = []
    private(set) var skipReason: String?
    var ms: Int?
    /// list-opens leaves the list up for esc-cancels.
    var keepListOpen = false

    init(name: String, timeout: Double) {
        self.name = name
        deadline = started + .milliseconds(Int(timeout * 1000))
    }

    func check(_ condition: Bool, _ failure: @autoclosure () -> String) {
        if !condition { failures.append(failure()) }
    }

    func fail(_ failure: String) { failures.append(failure) }
    func note(_ note: String) { notes.append(note) }
    func skip(_ reason: String) { skipReason = reason }

    var detail: String {
        if let skipReason { return "skipped: \(skipReason)" }
        let parts = (failures.isEmpty ? [] : ["FAILED: " + failures.joined(separator: "; ")]) + notes
        return parts.joined(separator: " | ")
    }
}
#endif
