#if DEBUG
import AppKit

// ⌘§, mapped to docs/spec.md § Acceptance tests 22–25. Each starts from the home app, which needs
// two or more windows: scratch TextEdit documents are the safe choice, as for ⌘⇥.

extension SelfTest {
    func runWindowScenarios() async throws {
        refreshWindows()
        let count = home.map { windowsByPid[$0.processIdentifier]?.count ?? 0 } ?? 0
        let tooFew = count < 2 ? "the home app has fewer than two windows" : nil
        try await scenario("windows-flip", skip: tooFew) { try await windowsFlip($0) }
        try await scenario("windows-escape", skip: tooFew) { try await windowsEscape($0) }
        try await scenario("windows-cycle", skip: tooFew ?? (count < 3 ? "the home app has fewer than three windows" : nil)) {
            try await windowsCycle($0)
        }
    }

    // MARK: 22. A quick ⌘§ flips, and flips back

    private func windowsFlip(_ run: ScenarioRun) async throws {
        guard let home, try await restoreHome(run), keysAllowed(run) else { return }
        let pid = home.processIdentifier
        guard let first = await focusedWindow(pid) else {
            run.fail("can't read the home app's focused window")
            return
        }
        guard let flipped = try await quickFlip(pid, run) else { return }
        run.check(flipped != first, "the flip focused the window it started from")
        run.note("flipped from window \(first) to \(flipped)")
        try await sleep(0.3, run)
        guard let back = try await quickFlip(pid, run) else { return }
        run.check(back == first, "the second flip went to window \(back), not back to \(first)")
        try await checkCommandUp(run)
        try await checkpoint("windows-flipped", run)
    }

    /// A ⌘§ tap faster than the switcher's delay. Returns the window it focused, once focused.
    private func quickFlip(_ pid: Int32, _ run: ScenarioRun) async throws -> UInt32? {
        let sessions = SelfTestHooks.windowSessions.count
        let keys = keys
        let held = await selfTestOffMain { keys.quickCommandSection(gap: 0.012) }
        let released = ContinuousClock.now
        run.check(held < 0.1, "the tap took \(Int(held * 1000)) ms, not under 100")
        guard try await waitFor(1, run, { SelfTestHooks.windowSessions.count > sessions }) != nil,
              let session = SelfTestHooks.windowSessions.last
        else {
            run.fail("no ⌘§ session ended within 1 s of the tap (phase \(phase))")
            return nil
        }
        run.check(!session.shown, "the switcher appeared for a quick tap")
        guard session.windowIDs.count >= 2, session.highlight == 1 else {
            run.fail("the session had \(session.windowIDs.count) tiles, highlight \(session.highlight + 1), not 2")
            return nil
        }
        let expected = session.windowIDs[1]
        let focused = try await waitFor(2, run) {
            guard self.frontPid == pid else { return false }
            return await self.focusedWindow(pid) == expected
        }
        run.ms = focused.map { _ in Self.ms(since: released) }
        guard focused != nil else {
            let now = await focusedWindow(pid)
            run.fail("after 2 s window \(now.map(String.init) ?? "none") is focused, not \(expected)")
            return nil
        }
        return expected
    }

    // MARK: 25. Esc changes nothing

    private func windowsEscape(_ run: ScenarioRun) async throws {
        guard let home, try await restoreHome(run), keysAllowed(run) else { return }
        let pid = home.processIdentifier
        let before = await focusedWindow(pid)
        let requests = SelfTestHooks.focusRequests.count
        guard try await openWindowSwitcher(run) else { return }
        run.check(SelfTestHooks.switcherHighlight == 1, "tile \(SelfTestHooks.switcherHighlight + 1) is highlighted, not 2")
        let expected = min(WindowSwitcherModel.maxTiles, windowsByPid[pid]?.count ?? 0)
        run.check(SelfTestHooks.switcherWindowIDs.count >= expected,
                  "\(SelfTestHooks.switcherWindowIDs.count) windows in the switcher, expected \(expected)")
        keys.press(SelfTestKeys.escape)
        let closed = try await waitFor(1, run) { self.phase == "idle" && !SelfTestHooks.switcherVisible }
        run.ms = closed
        run.check(closed != nil, "after 1 s: phase \(phase), switcher visible \(SelfTestHooks.switcherVisible)")
        keys.commandUp()
        try await sleep(0.3, run)
        run.check(SelfTestHooks.focusRequests.count == requests, "Esc, then the ⌘ release, still focused a window")
        run.check(await focusedWindow(pid) == before, "the focused window changed")
        try await checkCommandUp(run)
    }

    // MARK: 23. Holding ⌘ and stepping

    private func windowsCycle(_ run: ScenarioRun) async throws {
        guard let home, try await restoreHome(run), keysAllowed(run) else { return }
        let pid = home.processIdentifier
        guard try await openWindowSwitcher(run) else { return }
        keys.press(SelfTestKeys.section)
        let stepped = try await waitFor(0.5, run) { SelfTestHooks.switcherHighlight == 2 }
        run.check(stepped != nil, "§ left the highlight on tile \(SelfTestHooks.switcherHighlight + 1), not 3")
        let ids = SelfTestHooks.switcherWindowIDs
        guard ids.count >= 3 else {
            run.fail("\(ids.count) windows in the switcher, not 3 or more")
            return
        }
        try await checkpoint("windows-open", run)
        let released = ContinuousClock.now
        keys.commandUp()
        let focused = try await waitFor(2, run) {
            guard self.frontPid == pid else { return false }
            return await self.focusedWindow(pid) == ids[2]
        }
        run.ms = focused.map { _ in Self.ms(since: released) }
        run.check(focused != nil, "after 2 s window \(ids[2]) isn't focused")
        run.check(!SelfTestHooks.switcherVisible, "the switcher is still visible")
        try await checkCommandUp(run)
    }

    /// ⌘ down, then §. Returns true once the switcher is on screen, within 600 ms. ⌘ stays held.
    private func openWindowSwitcher(_ run: ScenarioRun) async throws -> Bool {
        keys.commandDown()
        try await sleep(0.04, run)
        keys.press(SelfTestKeys.section)
        let pressed = ContinuousClock.now
        guard try await waitFor(0.6, run, { SelfTestHooks.switcherVisible }) != nil else {
            run.fail("no switcher within 600 ms of ⌘§ (phase \(phase), tiles \(SelfTestHooks.switcherWindowIDs.count))")
            return false
        }
        run.note("switcher up \(Self.ms(since: pressed)) ms after ⌘§")
        return true
    }

    /// Keys go to the front app if anything is off, so none are posted with the screen locked.
    private func keysAllowed(_ run: ScenarioRun) -> Bool {
        guard let reason = Self.screenLockReason() else { return true }
        run.fail("didn't post a key: \(reason)")
        return false
    }
}
#endif
