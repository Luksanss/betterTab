import AppKit
import Dispatch
import os

/// Menu-bar UI and lifecycle. Everything here runs on the main thread; the tap, the timeout, the
/// AX probe and the signal handlers never wait for it.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static weak var current: AppDelegate?

    private let machine: HoldMachine
    private let tapHost: TapHost
    private let probe: SwitcherProbe
    private let panel = ClickTestPanel()

    private var statusItem: NSStatusItem?
    private var signalSources: [any DispatchSourceSignal] = []
    private var ticker: Timer?

    private var snapshot = Snapshot(phase: .idle, generation: 0, enteredAt: 0)
    private var location = TapLocation.session
    private var tapCreated: Bool?
    private var permissions = Permissions.current()
    private var armed = true
    private var showPanel = false
    private var switcherLayer: Int?

    private let stateItem = NSMenuItem()
    private let tapItem = NSMenuItem()
    private let permissionItem = NSMenuItem()
    private let requestItem = NSMenuItem()
    private let retryItem = NSMenuItem()
    private let sessionItem = NSMenuItem()
    private let hidItem = NSMenuItem()
    private let armedItem = NSMenuItem()
    private let panelItem = NSMenuItem()

    override init() {
        let machine = HoldMachine(notify: AppDelegate.relayPhase, tabPassed: AppDelegate.relayTab)
        self.machine = machine
        tapHost = TapHost(machine: machine, onResult: AppDelegate.relayTapResult)
        probe = SwitcherProbe(machine: machine, onLayer: AppDelegate.relayLayer)
        super.init()
    }

    // MARK: Relays from other threads

    nonisolated private static func relayPhase(_ snapshot: Snapshot) {
        DispatchQueue.main.async { MainActor.assumeIsolated { current?.phaseChanged(snapshot) } }
    }

    nonisolated private static func relayTab(_ generation: UInt64) {
        DispatchQueue.main.async { MainActor.assumeIsolated { current?.tabPassedDuringHold(generation) } }
    }

    nonisolated private static func relayTapResult(_ location: TapLocation, _ created: Bool) {
        DispatchQueue.main.async { MainActor.assumeIsolated { current?.tapResult(location, created: created) } }
    }

    nonisolated private static func relayLayer(_ layer: Int) {
        DispatchQueue.main.async { MainActor.assumeIsolated { current?.layerFound(layer) } }
    }

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.current = self
        signalSources = SignalGuard.install(tapHost: tapHost)
        buildMenu()
        permissions = Permissions.log("at launch")
        tapHost.start(location)
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        tapHost.stop(reason: "applicationWillTerminate")
    }

    // MARK: Events

    private func phaseChanged(_ new: Snapshot) {
        // Relays come from several threads and may arrive out of order.
        guard new.generation > snapshot.generation else { return }
        snapshot = new
        probe.phaseEntered(new, dockPid: dockPid())
        if new.phase == .holding {
            if showPanel { panel.show(switcherLayer: switcherLayer) }
            startTicker()
        } else {
            panel.close()
            stopTicker()
        }
        refresh()
    }

    private func tabPassedDuringHold(_ generation: UInt64) {
        probe.logSelectionAfterTab(generation: generation, dockPid: dockPid())
    }

    private func tapResult(_ location: TapLocation, created: Bool) {
        guard location == self.location else { return }
        tapCreated = created
        permissions = Permissions.current()
        refresh()
    }

    private func layerFound(_ layer: Int) {
        switcherLayer = layer
        panel.switcherLayerChanged(layer)
    }

    private func dockPid() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
    }

    // MARK: Menu

    private func buildMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        for info in [stateItem, tapItem, permissionItem] {
            info.isEnabled = false
            menu.addItem(info)
        }
        configure(requestItem, "Request permissions", #selector(requestPermissions))
        configure(retryItem, "Retry creating the tap", #selector(retryTap))
        menu.addItem(requestItem)
        menu.addItem(retryItem)
        menu.addItem(.separator())

        let header = NSMenuItem(title: "Tap location", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        configure(sessionItem, "Session tap", #selector(chooseSession))
        configure(hidItem, "HID tap", #selector(chooseHID))
        menu.addItem(sessionItem)
        menu.addItem(hidItem)
        menu.addItem(.separator())

        configure(armedItem, "Hold armed", #selector(toggleArmed))
        configure(panelItem, "Show click-test panel during hold", #selector(togglePanel))
        menu.addItem(armedItem)
        menu.addItem(panelItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem()
        configure(quitItem, "Quit", #selector(quit))
        quitItem.keyEquivalent = "q"
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    private func configure(_ item: NSMenuItem, _ title: String, _ action: Selector) {
        item.title = title
        item.action = action
        item.target = self
    }

    func menuWillOpen(_ menu: NSMenu) {
        permissions = Permissions.current()
        refresh()
    }

    private func refresh() {
        let state: String
        let badge: String
        switch snapshot.phase {
        case .idle:
            state = "Idle"
            badge = "T0"
        case .cycling:
            state = "Cycling"
            badge = "T0 cycling"
        case .holding:
            let now = uptimeNanos()
            let held = Int(seconds(now > snapshot.enteredAt ? now - snapshot.enteredAt : 0))
            state = "Holding \(held) s"
            badge = "T0 holding \(held) s"
        }
        stateItem.title = "State: \(state)" + (armed ? "" : " (hold not armed)")
        statusItem?.button?.title = tapCreated == false ? "T0 no tap" : badge

        let where_ = location == .session ? "session" : "HID"
        let tapState = switch tapCreated {
        case nil: "starting…"
        case true?: "running"
        case false?: "NOT created (see Request permissions)"
        }
        tapItem.title = "Tap: \(where_), \(tapState)"
        func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }
        permissionItem.title = "Accessibility \(yesNo(permissions.accessibility)) · "
            + "Listen \(yesNo(permissions.listen)) · Post \(yesNo(permissions.post))"
        requestItem.isHidden = tapCreated != false
        retryItem.isHidden = tapCreated != false
        sessionItem.state = location == .session ? .on : .off
        hidItem.state = location == .hid ? .on : .off
        armedItem.state = armed ? .on : .off
        panelItem.state = showPanel ? .on : .off
    }

    private func startTicker() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { AppDelegate.current?.refresh() }
        }
        // Common modes, so the title keeps counting while the menu is open.
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: Actions

    @objc private func requestPermissions() {
        Permissions.request()
        permissions = Permissions.current()
        refresh()
    }

    @objc private func retryTap() {
        startTap(at: location)
    }

    @objc private func chooseSession() {
        guard location != .session else { return }
        startTap(at: .session)
    }

    @objc private func chooseHID() {
        guard location != .hid else { return }
        startTap(at: .hid)
    }

    private func startTap(at newLocation: TapLocation) {
        Log.app.notice("MENU tap location \(newLocation.rawValue, privacy: .public)")
        location = newLocation
        tapCreated = nil
        tapHost.start(newLocation)  // Stops the old tap first, posting any owed ⌘ release.
        refresh()
    }

    @objc private func toggleArmed() {
        armed.toggle()
        machine.setArmed(armed)
        refresh()
    }

    @objc private func togglePanel() {
        showPanel.toggle()
        Log.app.notice("MENU click-test panel during hold=\(self.showPanel, privacy: .public)")
        if !showPanel {
            panel.close()
        } else if snapshot.phase == .holding {
            panel.show(switcherLayer: switcherLayer)
        }
        refresh()
    }

    @objc private func quit() {
        Log.app.notice("MENU Quit")
        machine.releaseCommandIfOwed(reason: "Quit", cancel: true)
        NSApp.terminate(nil)
    }
}

/// SIGTERM and SIGINT end a hold safely. They're handled on their own queue, so this works even
/// when the main thread is stuck. `kill -9` can't be caught; that's test 0g.
nonisolated enum SignalGuard {
    static func install(tapHost: TapHost) -> [any DispatchSourceSignal] {
        let queue = DispatchQueue(label: "com.luksanss.BetterTab.Experiment.signals")
        return [(SIGTERM, "SIGTERM"), (SIGINT, "SIGINT")].map { number, name in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler {
                Log.app.notice("SIGNAL \(name, privacy: .public) received")
                tapHost.stop(reason: name)
                // Give the posted events and log lines a moment to leave the process.
                Thread.sleep(forTimeInterval: 0.1)
                exit(0)
            }
            source.resume()
            return source
        }
    }
}
