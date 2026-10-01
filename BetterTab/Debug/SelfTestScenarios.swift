#if DEBUG
import AppKit

// The scenarios, mapped to docs/spec.md § Acceptance tests. Each starts from the home app and
// leaves nothing held; `scenario` cleans up after each one.

extension SelfTest {
    func runScenarios() async throws {
        try await scenario("synthetic-cmd-tab", timeout: 8) { try await syntheticCommandTab($0) }
        guard !dockIgnoresSyntheticKeys else {
            let reason = "the Dock ignores synthetic ⌘⇥"
            for name in ["native-single", "native-multi", "stack-edges"] {
                try await scenario(name, skip: reason) { _ in }
            }
            // ⌘§ is BetterTab's own, so it doesn't depend on the Dock.
            try await runWindowScenarios()
            try await scenario("cmd-not-stuck") { try await commandNotStuck($0) }
            throw Stop.run(
                result: "dock ignores synthetic ⌘⇥",
                finding: """
                    The Dock showed no switcher within 1 s of ⌘ down + Tab posted untagged to the HID tap, so the \
                    stack edges can't be checked synthetically; the ⌘§ scenarios still ran. Check the edges by hand \
                    (docs/spec.md § Acceptance tests).
                    """)
        }

        try await scenario("native-single", skip: targets.single == nil ? "no other app has exactly one window" : nil) {
            try await nativeSwitch($0, to: targets.single)
        }
        try await scenario("native-multi", skip: targets.multi == nil ? "no other app has two or more windows" : nil) {
            try await nativeSwitch($0, to: targets.multi)
        }
        try await scenario("stack-edges") { try await stackEdgesWhileCycling($0) }
        try await runWindowScenarios()
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

    // MARK: 1. Every switch is native

    /// ⌘⇥ to `pid` and release: a plain native switch, whatever the app's window count.
    private func nativeSwitch(_ run: ScenarioRun, to pid: Int32?) async throws {
        guard let pid, try await restoreHome(run),
              let switcher = try await openSwitcher(run), try await highlight(pid, in: switcher, run)
        else { return }
        // Long enough for BetterTab to have read the app's windows and drawn its stack edges.
        try await sleep(0.4, run)
        keys.commandUp()
        let front = try await waitFor(1.5, run) { self.frontPid == pid }
        run.ms = front
        run.check(front != nil, "\(bundle(pid)) isn't in front 1.5 s after the release; \(bundle(frontPid)) is")
        run.check(try await waitFor(1, run, { await self.switcher() == nil }) != nil, "the switcher is still up")
        run.check(phase == "idle", "phase is \(phase), not idle")
        run.check(stackEdges?.isVisible != true, "the stack edges are still visible")
        run.note("\(windowsByPid[pid]?.count ?? 0) windows")
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

    // MARK: 15. ⌘ isn't stuck

    private func commandNotStuck(_ run: ScenarioRun) async throws {
        let actions = try await clean(run)
        if !actions.isEmpty { run.note("had to clean up first: \(actions.joined(separator: ", "))") }
        try await sleep(0.3, run)
        let state = SelfTestKeys.commandState()
        run.check(!state.hid, "the HID state shows ⌘ down")
        run.check(!state.session, "the session state shows ⌘ down")
        run.check(phase == "idle", "phase is \(phase), not idle")
        run.check(stackEdges?.isVisible != true, "the stack edges are visible")
        run.check(await switcher() == nil, "the switcher is up")
        if !sawNonIdlePhase { run.note("SelfTestHooks.phase never left idle during the run") }
    }
}
#endif
