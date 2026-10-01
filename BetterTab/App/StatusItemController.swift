import AppKit

/// The menu-bar item and its native menu.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let permission: AccessibilityPermission
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusLineView = StatusLineView()
    private let grantItem = NSMenuItem(title: "Grant Accessibility…", action: nil, keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: nil, keyEquivalent: "")

    #if DEBUG
    /// Debug › Status forces what the item shows. nil follows the real state.
    private var forcedState: AppStatus.State?
    private let debugStates: [(title: String, state: AppStatus.State?)] = [
        ("Automatic", nil),
        ("Active", .active),
        ("Needs permission", .needsPermission),
        ("Can’t find switcher", .switcherNotFound),
    ]
    private var debugStateItems: [NSMenuItem] = []
    /// Debug › Run Self-Test. Set by AppDelegate.
    var runSelfTest: (() -> Void)?
    #endif

    init(permission: AccessibilityPermission) {
        self.permission = permission
        super.init()
        statusItem.button?.image = StatusIcon.image
        statusItem.menu = makeMenu()
        update()
    }

    /// Redraws the icon and the status line from the current state.
    func update() {
        let state = displayedState
        statusItem.button?.appearsDisabled = state != .active
        statusLineView.show(state.title, color: state.color)
        grantItem.isHidden = state != .needsPermission
    }

    private var displayedState: AppStatus.State {
        #if DEBUG
        if let forcedState { return forcedState }
        #endif
        return AppStatus.shared.state
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let statusLine = NSMenuItem()
        statusLine.view = statusLineView
        menu.addItem(statusLine)

        grantItem.target = self
        grantItem.action = #selector(grantAccessibility)
        menu.addItem(grantItem)
        menu.addItem(.separator())

        launchAtLoginItem.target = self
        launchAtLoginItem.action = #selector(toggleLaunchAtLogin)
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())

        #if DEBUG
        menu.addItem(makeDebugItem())
        #endif

        // Information, not an action, so it's drawn disabled.
        let version = NSMenuItem(title: Self.versionTitle, action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)

        let quit = NSMenuItem(title: "Quit BetterTab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    /// "Version 0.1.87". Releases set the last part from the commit count (docs/releasing.md).
    private static var versionTitle: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        #if DEBUG
        return "Version \(version) (Debug)"
        #else
        return "Version \(version)"
        #endif
    }

    // The system owns the Launch at Login state and the user can change it in System Settings, so
    // read it each time the menu opens instead of watching it.
    func menuNeedsUpdate(_ menu: NSMenu) {
        launchAtLoginItem.state = LaunchAtLogin.isEnabled ? .on : .off
        #if DEBUG
        for (item, entry) in zip(debugStateItems, debugStates) {
            item.state = entry.state == forcedState ? .on : .off
        }
        #endif
    }

    @objc private func grantAccessibility() {
        permission.requestAccess()
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.toggle()
        launchAtLoginItem.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    #if DEBUG
    private func makeDebugItem() -> NSMenuItem {
        let status = NSMenu()
        debugStateItems = debugStates.enumerated().map { index, entry in
            let item = NSMenuItem(title: entry.title, action: #selector(forceState(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            status.addItem(item)
            return item
        }

        let debug = NSMenu()
        let preview = NSMenuItem(title: "Preview Stack Edges", action: #selector(showPreview), keyEquivalent: "")
        preview.target = self
        debug.addItem(preview)
        debug.addItem(withTitle: "Status", action: nil, keyEquivalent: "").submenu = status
        debug.addItem(.separator())
        let selfTest = NSMenuItem(title: "Run Self-Test", action: #selector(runSelfTestItem), keyEquivalent: "")
        selfTest.target = self
        debug.addItem(selfTest)

        let item = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        item.submenu = debug
        return item
    }

    @objc private func showPreview() {
        DesignPreview.shared.show()
    }

    @objc private func forceState(_ sender: NSMenuItem) {
        forcedState = debugStates[sender.tag].state
        update()
    }

    @objc private func runSelfTestItem() {
        // It presses keys system-wide for a couple of minutes, so a stray click mustn't start it.
        let alert = NSAlert()
        alert.messageText = "Run the self-test?"
        alert.informativeText = """
            For about a minute BetterTab presses ⌘⇥, ⌘§ and Esc itself and switches between \
            apps, windows and Spaces. Don't touch the keyboard or mouse while it runs; a click \
            stops it. The report goes to ~/Library/Logs/BetterTab/self-test.json.
            """
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runSelfTest?()
    }
    #endif
}

private extension AppStatus.State {
    var title: String {
        switch self {
        case .active: "Active"
        case .needsPermission: "Needs Accessibility permission"
        case .switcherNotFound: "Can’t find the ⌘⇥ switcher"
        }
    }

    var color: NSColor {
        switch self {
        case .active: .systemGreen
        case .needsPermission: .systemOrange
        case .switcherNotFound: .systemRed
        }
    }
}
