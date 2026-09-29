#if DEBUG
import AppKit

// The scenarios, mapped to docs/spec.md § Acceptance tests. Each starts from the home app and
// leaves nothing held; `scenario` cleans up after each one.

extension SelfTest {
    func runScenarios() async throws {
        try await scenario("synthetic-cmd-tab", timeout: 8) { try await syntheticCommandTab($0) }
        guard !dockIgnoresSyntheticKeys else {
            let reason = "the Dock ignores synthetic ⌘⇥"
            for name in ["single-native", "stack-edges", "list-opens", "esc-cancels", "pick-s", "pick-a", "arrows-return",
                         "cmd-tab-again", "cmd-tap-cancels", "quick-tap-native", "timeout-16s"] {
                try await scenario(name, skip: reason) { _ in }
            }
            try await scenario("cmd-not-stuck") { try await commandNotStuck($0) }
            throw Stop.run(
                result: "dock ignores synthetic ⌘⇥",
                finding: """
                    The Dock showed no switcher within 1 s of ⌘ down + Tab posted untagged to the HID tap, so the \
                    flow can't be driven synthetically. Run docs/spec.md § Acceptance tests by hand.
                    """)
        }

        let noMulti = targets.multi == nil ? "no app has two or more windows" : nil
        let multiWindows = targets.multi.map { windowsByPid[$0]?.count ?? 0 } ?? 0
        try await scenario("single-native", skip: targets.single == nil ? "no other app has exactly one window" : nil) {
            try await singleNative($0)
        }
        try await scenario("stack-edges") { try await stackEdgesWhileCycling($0) }
        try await scenario("list-opens", skip: noMulti) { try await listOpens($0) }
        try await scenario("esc-cancels", skip: noMulti) { try await escapeCancels($0) }
        try await scenario("pick-s", skip: noMulti) {
            try await pick($0, presses: [SelfTestKeys.letterS], row: 1)
        }
        try await scenario("pick-a", skip: noMulti) {
            try await pick($0, presses: [SelfTestKeys.letterA], row: 0)
        }
        try await scenario("arrows-return", skip: noMulti ?? (multiWindows < 3 ? "multi has fewer than 3 windows" : nil)) {
            try await pick($0, presses: [SelfTestKeys.downArrow, SelfTestKeys.downArrow, SelfTestKeys.returnKey], row: 2)
        }
        try await scenario("cmd-tab-again", skip: noMulti) { try await commandTabAgain($0) }
        try await scenario("cmd-tap-cancels", skip: noMulti) { try await commandTapCancels($0) }
        try await scenario("quick-tap-native", skip: noMulti) { try await quickTap($0) }
        try await scenario("timeout-16s", timeout: 30, skip: noMulti ?? (options.long ? nil : "needs --long")) {
            try await noInputTimeout($0)
        }
        try await scenario("cmd-not-stuck") { try await commandNotStuck($0) }
    }

    // MARK: 0. The Dock sees synthetic ⌘⇥

    private func syntheticCommandTab(_ run: ScenarioRun) async throws {
        guard try await restoreHome(run) else { return }
        keys.commandDown()
        try await sleep(0.04, run)
        keys.press(SelfTestKeys.tab)
        guard let ms = try await waitFor(1, every: 0.03, run, { await self.switcher() != nil }) else {
            dockIgnoresSyntheticKeys = true
            run.fail("the Dock showed no switcher within 1 s of a synthetic ⌘⇥ posted to the HID tap")
            keys.commandUp()
            try await sleep(0.3, run)
            // Diagnostic only: does the session tap fare better?
            let session = SelfTestKeys(location: .cgSessionEventTap)
            session.commandDown()
            try await sleep(0.04, run)
            session.press(SelfTestKeys.tab)
            let viaSession = try await waitFor(1, every: 0.03, run) { await self.switcher() != nil }
            if viaSession != nil {
                session.press(SelfTestKeys.escape)
                try await sleep(0.04, run)
            }
            session.commandUp()
            run.note(viaSession.map { "posting to the session tap did show it, after \($0) ms" }
                ?? "posting to the session tap didn't show it either")
            return
        }
        run.ms = ms
        run.note("switcher up \(ms) ms after ⌘⇥")
        let cycling = try await waitFor(0.5, run) { self.phase == "cycling" }
        run.note(cycling != nil ? "controller phase cycling" : "controller phase stayed \(phase)")

        // Esc with ⌘ held is the native cancel, which cleanup relies on too.
        keys.press(SelfTestKeys.escape)
        try await sleep(0.04, run)
        keys.commandUp()
        run.check(try await waitFor(1, run, { await self.switcher() == nil }) != nil, "Esc with ⌘ didn't close the switcher")
        try await sleep(0.3, run)
        run.check(frontPid == home?.processIdentifier, "after the native cancel \(bundle(frontPid)) is in front, not home")
        try await checkCommandUp(run)
    }

    // MARK: 1. A single-window app switches natively

    private func singleNative(_ run: ScenarioRun) async throws {
        guard let single = targets.single, try await restoreHome(run),
              let switcher = try await openSwitcher(run), try await highlight(single, in: switcher, run)
        else { return }
        try await sleep(0.4, run)
        run.check(!tap.holdOnRelease, "holdOnRelease is set for a one-window app")
        let released = ContinuousClock.now
        keys.commandUp()
        var frontAt: Int?
        var sawList = false
        while Self.seconds(since: released) < 1.5 {
            if listVisible || phase == "picking" { sawList = true }
            if frontAt == nil, frontPid == single { frontAt = Self.ms(since: released) }
            if frontAt != nil, Self.seconds(since: released) >= 0.6 { break }
            try await sleep(0.02, run)
        }
        run.ms = frontAt
        run.check(frontAt != nil, "\(bundle(single)) isn't in front after 1.5 s; \(bundle(frontPid)) is")
        run.check(!sawList, "a list opened for a one-window app")
        run.check(phase == "idle", "phase is \(phase), not idle")
        try await checkCommandUp(run)
    }

    // MARK: 2. Stack edges while cycling

    private func stackEdgesWhileCycling(_ run: ScenarioRun) async throws {
        refreshWindows()
        guard try await restoreHome(run), try await openSwitcher(run) != nil else { return }
        var problems: [String] = []
        var last: SelfTestSwitcher?
        let matched = try await waitFor(1, every: 0.03, run) {
            guard let switcher = await self.switcher(items: true) else { return false }
            last = switcher
            problems = self.stackEdgeProblems(switcher)
            return problems.isEmpty
        }
        run.ms = matched
        run.check(matched != nil, "after 1 s: " + problems.joined(separator: "; "))
        if let last {
            let expected = last.items.compactMap(\.pid).filter { (windowsByPid[$0]?.count ?? 0) >= 2 }.count
            let unmatched = last.items.filter { $0.pid == nil }.count
            run.note("\(last.items.count) icons, \(expected) with stack edges expected, \(unmatched) not matched to an app")
            if expected > 0 { run.check(stackEdges?.isVisible == true, "the stack edges panel isn't visible") }
            // AX points, top-left origin, so they line up with a screenshot of the main display.
            let frames = last.items.compactMap(\.frame).map(Self.describe).joined(separator: ", ")
            run.note("AX frames: switcher \(last.frame.map(Self.describe) ?? "?"), icons \(frames)")
        }
        run.note("phase \(phase)")
        try await checkpoint("stack-edges", run)
    }

    /// "x,y w×h", in whole points.
    private static func describe(_ rect: CGRect) -> String {
        "\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))×\(Int(rect.height))"
    }

    /// Wrong counts and misplaced stack edges, by bundle id. Empty when everything matches.
    private func stackEdgeProblems(_ switcher: SelfTestSwitcher) -> [String] {
        let state = stackEdges
        let visible = state?.isVisible ?? false
        var problems: [String] = []
        for item in switcher.items {
            guard let pid = item.pid, let bundle = bundleByPid[pid], let axFrame = item.frame else { continue }
            let frame = appKitRect(axFrame)
            let expected = SelfTestPlan.expectedStackEdges(
                windows: windowsByPid[pid]?.count ?? 0, maxEdges: StackEdgesOverlay.maxEdges)
            let icon = state?.icons
                .filter { hypot($0.frame.midX - frame.midX, $0.frame.midY - frame.midY) <= 8 }
                .min { hypot($0.frame.midX - frame.midX, $0.frame.midY - frame.midY)
                    < hypot($1.frame.midX - frame.midX, $1.frame.midY - frame.midY) }
            let shown = visible ? icon?.edgeCount ?? 0 : 0
            if shown != expected {
                problems.append("\(bundle) shows \(shown) stack edges, expected \(expected)")
            } else if shown > 0, let front = icon?.frontEdge, let top = icon?.top {
                // Centred on the icon, above its body, and inside the Dock's highlight: the frame
                // inset by 4 pt at 128 pt, scaled for smaller icons. The body comes from the AX
                // frame read here, not from the overlay.
                let dx = front.midX - frame.midX
                let rise = top - (frame.midY + frame.height * StackEdgesOverlay.bodyScale / 2)
                let headroom = frame.maxY - top
                if abs(dx) > 2 || rise <= 0 || headroom < frame.height * 4 / 128 {
                    problems.append("""
                        \(bundle)'s stack edges are off their icon (dx \(Int(dx)), \(Int(rise)) pt above the body, \
                        \(Int(headroom)) pt below the icon frame's top)
                        """)
                }
            }
        }
        return problems
    }

    // MARK: 3. The list opens

    private func listOpens(_ run: ScenarioRun) async throws {
        guard let multi = targets.multi else { return }
        refreshWindows()
        let windows = windowsByPid[multi] ?? []
        let expectedRows = min(WindowListModel.maxRows, windows.count)
        guard let opened = try await openList(on: multi, run), let state = list else { return }
        let ids = opened.ids
        run.ms = opened.ms
        run.check(state.rowCount == expectedRows, "\(state.rowCount) rows, expected \(expectedRows)")
        let labels = Array(KeyLabels.current().prefix(state.rowCount))
        run.check(state.labels == labels,
                  "labels \(state.labels.joined(separator: " ")), expected \(labels.joined(separator: " "))")
        run.note("labels \(state.labels.joined(separator: " "))")
        run.check(state.highlight == 0, "row \(state.highlight + 1) is highlighted, not A")
        run.check(ids.count >= state.rowCount, "listedWindowIDs has \(ids.count) ids for \(state.rowCount) rows")
        let known = Set(windows.map(\.id))
        let unknown = ids.filter { !known.contains($0) }.count
        run.check(unknown == 0, "\(unknown) listed ids aren't real windows of \(bundle(multi)) per SkyLight")
        run.check(stackEdges?.isVisible == true, "the stack edges aren't shown during Picking")
        run.check(frontPid == home?.processIdentifier, "\(bundle(frontPid)) is in front, not the home app")
        let held = await switcher(items: true)
        run.check(held != nil, "the native switcher closed on the release: the hold didn't work")
        if let switcher = held, let frame = switcher.frame {
            let switcherFrame = appKitRect(frame)
            let icon = switcher.selected.flatMap { switcher.items.indices.contains($0) ? switcher.items[$0].frame : nil }
                .map(appKitRect)
            let above = state.frame.minY >= switcherFrame.maxY
            let offset = icon.map { Int(state.frame.midX - $0.midX) }
            run.note("list \(above ? "above" : "not above") the switcher, centre \(offset.map { "\($0) pt" } ?? "?") from the icon's")
        }
        let command = SelfTestKeys.commandState()
        run.note("while Picking, ⌘ down per HID \(command.hid), per session \(command.session)")
        // The list stays up for esc-cancels.
        run.keepListOpen = true
        try await checkpoint("list-open", run)
    }

    // MARK: 4. Esc cancels

    private func escapeCancels(_ run: ScenarioRun) async throws {
        guard phase == "picking", listVisible else {
            run.skip("needs the list left open by list-opens")
            return
        }
        guard pressInList(SelfTestKeys.escape, run) else { return }
        let closed = try await waitForIdle(1, run)
        run.ms = closed
        run.check(closed != nil, "after 1 s: phase \(phase), list visible \(listVisible)")
        try await sleep(0.3, run)
        run.check(frontPid == home?.processIdentifier, "\(bundle(frontPid)) is in front, not the home app")
        try await checkCommandUp(run)
    }

    // MARK: 5–7. Picking a window

    /// Opens `multi`'s list, presses `presses`, and expects the window in row `row` to be focused.
    private func pick(_ run: ScenarioRun, presses: [CGKeyCode], row: Int) async throws {
        guard let multi = targets.multi, let ids = try await openList(on: multi, run)?.ids else { return }
        guard ids.count > row else {
            run.fail("listedWindowIDs has \(ids.count) ids, none for row \(row + 1)")
            return
        }
        let expected = ids[row]
        let spacesBefore = SelfTestSkyLight.currentSpaces()
        let targetWasElsewhere = Set(SelfTestSkyLight.spaces(of: expected)).isDisjoint(with: spacesBefore)
        let requestsBefore = SelfTestHooks.focusRequests.count
        for (index, key) in presses.enumerated() {
            if index > 0 { try await sleep(0.04, run) }
            guard pressInList(key, run) else { return }
            if key == SelfTestKeys.downArrow {
                let moved = try await waitFor(0.3, run) { self.list?.highlight == index + 1 }
                run.check(moved != nil, "↓ left the highlight on row \((list?.highlight ?? -1) + 1)")
            }
        }

        let pressed = ContinuousClock.now
        var seen: [UInt32] = []
        var focusedAt: Int?
        while Self.seconds(since: pressed) < 2 {
            let focused = await focusedWindow(multi)
            if let focused, seen.last != focused { seen.append(focused) }
            if frontPid == multi, focused == expected, isOnCurrentSpace(expected) {
                focusedAt = Self.ms(since: pressed)
                break
            }
            try await sleep(0.02, run)
        }
        run.ms = focusedAt
        if focusedAt == nil {
            let focused = await focusedWindow(multi)
            run.fail("""
                after 2 s: \(bundle(frontPid)) in front, focused window \(focused.map(String.init) ?? "none") \
                (expected \(expected), row \(row + 1)), on the current Space \(isOnCurrentSpace(expected))
                """)
        } else {
            try await sleep(0.3, run)
            let focused = await focusedWindow(multi)
            run.check(frontPid == multi && focused == expected, "focus didn't stick: window \(focused.map(String.init) ?? "none") 300 ms later")
        }
        let spacesAfter = SelfTestSkyLight.currentSpaces()
        run.note("window \(expected) (row \(row + 1)); was on another Space \(targetWasElsewhere); Space changed \(spacesBefore != spacesAfter)")
        run.note("focused windows seen, in order: \(seen.map(String.init).joined(separator: " → "))")
        let requests = SelfTestHooks.focusRequests.dropFirst(requestsBefore)
        let matching = requests.last.map { $0.pid == multi && $0.windowID == expected } ?? false
        run.note("\(requests.count) focus requests\(requests.isEmpty ? "" : matching ? ", the last for this window" : ", the last for another window")")
        run.check(!listVisible, "the list is still visible")
        run.check(try await waitFor(1, run, { await self.switcher() == nil }) != nil, "the switcher is still up")
        try await checkCommandUp(run)
        try await checkpoint("picked-row-\(row + 1)", run)
    }

    // MARK: 8. ⌘⇥ again

    private func commandTabAgain(_ run: ScenarioRun) async throws {
        guard let multi = targets.multi else { return }
        let target = targets.second ?? multi
        run.note(targets.second == nil ? "no second multi-window app, so back to multi" : "on to the second app")
        refreshWindows()
        let expectedRows = min(WindowListModel.maxRows, windowsByPid[target]?.count ?? 0)
        guard try await openList(on: multi, run) != nil else { return }
        guard let before = await switcher(), let selected = before.selected, before.count > 0 else {
            run.fail("can't read the switcher's highlight")
            return
        }
        keys.commandDown()
        try await sleep(0.04, run)
        keys.press(SelfTestKeys.tab)
        let next = (selected + 1) % before.count
        let back = try await waitFor(0.8, run) {
            guard self.phase == "cycling", !self.listVisible else { return false }
            return await self.switcher()?.selected == next
        }
        run.ms = back
        guard back != nil else {
            let highlight = await switcher()?.selected
            run.fail("""
                after ⌘⇥ again: phase \(phase), list visible \(listVisible), highlight \(highlight.map { "\($0 + 1)" } ?? "?") \
                (expected \(next + 1))
                """)
            return
        }
        guard let switcher = await switcher(items: true), try await highlight(target, in: switcher, run),
              try await holdReady(run), let opened = try await release(expecting: target, run),
              let state = list
        else { return }
        run.note("list for \(bundle(target)) \(opened.ms) ms after the release")
        run.check(state.rowCount == expectedRows, "\(state.rowCount) rows, expected \(expectedRows)")
        try await checkpoint("back-to-cycling", run)
        guard pressInList(SelfTestKeys.escape, run) else { return }
        run.check(try await waitForIdle(1, run) != nil, "Esc didn't close everything")
        try await sleep(0.3, run)
        run.check(frontPid == home?.processIdentifier, "\(bundle(frontPid)) is in front, not the home app")
    }

    // MARK: 9. A ⌘ tap cancels

    private func commandTapCancels(_ run: ScenarioRun) async throws {
        guard let multi = targets.multi, try await openList(on: multi, run) != nil else { return }
        keys.commandDown()
        try await sleep(0.06, run)
        keys.commandUp()
        let closed = try await waitForIdle(1, run)
        run.ms = closed
        run.check(closed != nil, "after 1 s: phase \(phase), list visible \(listVisible)")
        try await sleep(0.3, run)
        run.check(frontPid == home?.processIdentifier, "\(bundle(frontPid)) is in front, not the home app")
        try await checkCommandUp(run)
    }

    // MARK: 10. A quick tap stays native

    private func quickTap(_ run: ScenarioRun) async throws {
        guard let multi = targets.multi, let app = NSRunningApplication(processIdentifier: multi) else { return }
        // Multi goes right behind home in the switcher's order, so one Tab reaches it.
        app.activate(options: [])
        guard try await waitFor(2, run, { self.frontPid == multi }) != nil else {
            run.fail("couldn't bring \(bundle(multi)) to the front to set up the order")
            return
        }
        try await sleep(0.3, run)
        guard try await restoreHome(run) else { return }
        try await sleep(0.3, run)

        let keys = keys
        let held = await selfTestOffMain { keys.quickCommandTab(gap: 0.012) }
        let released = ContinuousClock.now
        run.note("⌘ held \(Int(held * 1000)) ms")
        run.check(held < 0.06, "the tap took \(Int(held * 1000)) ms, not under 60")
        var frontAt: Int?
        var sawList = false
        while Self.seconds(since: released) < 1.5 {
            if listVisible || phase == "picking" { sawList = true }
            if frontAt == nil, frontPid == multi { frontAt = Self.ms(since: released) }
            if frontAt != nil, Self.seconds(since: released) >= 0.8 { break }
            try await sleep(0.02, run)
        }
        run.ms = frontAt
        run.check(!sawList, "the list opened: BetterTab held a quick tap")
        run.check(frontAt != nil, "\(bundle(multi)) never came to the front; \(bundle(frontPid)) is")
    }

    // MARK: 11. No input for 16 s

    private func noInputTimeout(_ run: ScenarioRun) async throws {
        guard let multi = targets.multi, try await openList(on: multi, run) != nil,
              let released = lastReleaseAt
        else { return }
        let cancelled = try await waitFor(17.5, every: 0.1, run) { self.phase == "idle" && !self.listVisible }
        let after = Self.ms(since: released)
        run.ms = cancelled.map { _ in after }
        guard cancelled != nil else {
            run.fail("still Picking \(after) ms after the release")
            return
        }
        run.check(after >= 14_500, "cancelled \(after) ms after the release, before 15 s")
        run.check(after <= 16_500, "cancelled \(after) ms after the release, well after 15 s")
        run.check(try await waitFor(1, run, { await self.switcher() == nil }) != nil, "the switcher is still up")
        try await sleep(0.3, run)
        run.check(frontPid == home?.processIdentifier, "\(bundle(frontPid)) is in front, not the home app")
        try await checkCommandUp(run)
    }

    // MARK: 12. ⌘ isn't stuck

    private func commandNotStuck(_ run: ScenarioRun) async throws {
        let actions = try await clean(run)
        if !actions.isEmpty { run.note("had to clean up first: \(actions.joined(separator: ", "))") }
        try await sleep(0.3, run)
        let state = SelfTestKeys.commandState()
        run.check(!state.hid, "the HID state shows ⌘ down")
        run.check(!state.session, "the session state shows ⌘ down")
        run.check(phase == "idle", "phase is \(phase), not idle")
        run.check(!listVisible, "the list is visible")
        run.check(stackEdges?.isVisible != true, "the stack edges are visible")
        run.check(await switcher() == nil, "the switcher is up")
        if !sawNonIdlePhase { run.note("SelfTestHooks.phase never left idle during the run") }
    }
}
#endif
