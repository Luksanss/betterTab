#if DEBUG
import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

/// The v5 design's scenarios, for checking the dots and the window list by eye before the real
/// switcher is wired up. Debug builds only.
enum PreviewScenario: Int, CaseIterable {
    case chrome3, terminal2, notes1, minimized, eleven, untitledAndDuplicates, longTitle

    var title: String {
        switch self {
        case .chrome3: "Chrome ×3"
        case .terminal2: "Terminal ×2"
        case .notes1: "Notes ×1 (no list)"
        case .minimized: "One minimized window"
        case .eleven: "Finder ×11 (+2 more)"
        case .untitledAndDuplicates: "Untitled + duplicate titles"
        case .longTitle: "Very long title"
        }
    }
}

/// Shows the dots and the window list over a stand-in switcher.
///
/// The real `DotsOverlay` and `WindowList` are laid over the stand-in's tile frames, the way the
/// controller will lay them over the native switcher's AX frames. Keys work as in Picking: letters,
/// arrows and Return pick, Esc closes, and Tab moves on to the next app as ⌘⇥ followed by a release
/// would.
final class DesignPreview {
    static let shared = DesignPreview()

    private let switcher = StandInSwitcher()
    private let dots = DotsOverlay()
    private let list = WindowList(acceptsMouse: true)
    private var apps: [PreviewApp] = []
    private var highlighted = 0
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    init() {
        list.onPick = { [weak self] index in self?.picked(index) }
    }

    func show(_ scenario: PreviewScenario) {
        tearDown()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        apps = PreviewApp.apps(for: scenario)
        // As after one ⌘⇥ from Slack.
        highlighted = 1

        // The local key monitor only sees keys while BetterTab is active.
        NSApp.unhide(nil)
        NSApp.activate()
        switcher.show(apps: apps.map { ($0.name, $0.icon) }, highlighted: highlighted, on: screen)
        dots.show(switcherFrame: switcher.frame,
                  icons: zip(switcher.tileFrames, apps).map { (frame: $0, windowCount: $1.windows.count) })
        openList()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
        // Like the native switcher, go away when focus moves elsewhere.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func close() {
        guard keyMonitor != nil else { return }
        tearDown()
        // Hand focus back to the app that was in front before the preview.
        NSApp.hide(nil)
    }

    private func tearDown() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        list.hide()
        dots.hide()
        switcher.hide()
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.modifierFlags.contains(.command) { return event }
        switch Int(event.keyCode) {
        case kVK_Tab:
            advance()
        case kVK_Escape where !list.isVisible:
            close()
        default:
            // Everything else is swallowed, as the key tap will in Picking.
            guard list.isVisible, let action = list.handle(keyCode: event.keyCode) else { break }
            switch action {
            case .pick(let index): picked(index)
            case .cancel: close()
            case .moveHighlight: break
            }
        }
        return nil
    }

    private func advance() {
        list.hide()
        highlighted = (highlighted + 1) % apps.count
        switcher.setHighlighted(highlighted)
        openList()
    }

    private func openList() {
        let app = apps[highlighted]
        guard app.windows.count >= 2, let screen = switcher.screen else { return }
        list.show(windows: app.windows, switcherFrame: switcher.frame,
                  iconFrame: switcher.tileFrames[highlighted], screen: screen)
    }

    private func picked(_ windowIndex: Int) {
        let row = list.model.rows.firstIndex { $0.windowIndex == windowIndex } ?? 0
        let letter = list.labels.indices.contains(row) ? list.labels[row] : "?"
        let app = apps[highlighted]
        print("DesignPreview: picked \(letter), row \(row + 1): window \(windowIndex + 1) of \(app.windows.count) in \(app.name)")
        close()
    }
}

// MARK: - Scenario data

private struct PreviewApp {
    let name: String
    let bundleID: String
    var windows: [WindowListItem]

    var icon: NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }
        return NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
    }

    private static let chrome = "com.google.Chrome"
    private static let terminal = "com.apple.Terminal"
    private static let code = "com.microsoft.VSCode"
    private static let finder = "com.apple.finder"
    private static let notes = "com.apple.Notes"

    private static let chromeTitles = [
        "Inbox (24) - Gmail",
        "Add window list above switcher by lukas-k · Pull Request #412 · koala42/bettertab",
        "Sprint 34 - BetterTab - Jira",
    ]

    private static let standard: [PreviewApp] = [
        PreviewApp(name: "Slack", bundleID: "com.tinyspeck.slackmacgap", windows: titled("Slack")),
        PreviewApp(name: "Google Chrome", bundleID: chrome, windows: titled(chromeTitles)),
        PreviewApp(name: "Terminal", bundleID: terminal,
                   windows: titled("lukas — -zsh — 120×40", "bettertab — swift build — 120×40")),
        PreviewApp(name: "Visual Studio Code", bundleID: code,
                   windows: titled("WindowList.swift — bettertab", "README.md — dotfiles")),
        PreviewApp(name: "Finder", bundleID: finder, windows: titled("Downloads", "Projects")),
        PreviewApp(name: "Notes", bundleID: notes, windows: titled("Notes")),
        PreviewApp(name: "Claude", bundleID: "com.anthropic.claudefordesktop", windows: titled("Claude")),
        PreviewApp(name: "Calendar", bundleID: "com.apple.iCal", windows: titled("Calendar")),
        PreviewApp(name: "Photos", bundleID: "com.apple.Photos", windows: titled("Photos")),
        PreviewApp(name: "System Settings", bundleID: "com.apple.systempreferences", windows: titled("System Settings")),
    ]

    /// Slack first, then the scenario's app with its windows, then the rest.
    static func apps(for scenario: PreviewScenario) -> [PreviewApp] {
        let (bundleID, windows) = target(of: scenario)
        var apps = standard
        guard let index = apps.firstIndex(where: { $0.bundleID == bundleID }) else { return apps }
        var app = apps.remove(at: index)
        app.windows = windows
        apps.insert(app, at: 1)
        return apps
    }

    private static func target(of scenario: PreviewScenario) -> (bundleID: String, windows: [WindowListItem]) {
        switch scenario {
        case .chrome3:
            (chrome, titled(chromeTitles))
        case .terminal2:
            (terminal, titled("lukas — -zsh — 120×40", "bettertab — swift build — 120×40"))
        case .notes1:
            (notes, titled("Notes"))
        case .minimized:
            (code, titled("WindowList.swift — bettertab", "README.md — dotfiles")
                + [WindowListItem(title: "App.tsx — koala42-web", isMinimized: true)])
        case .eleven:
            (finder, titled("Downloads", "Projects", "bettertab", "Screenshots", "Desktop", "Documents",
                          "Invoices 2026", "Design Assets", "Applications", "koala42-web", "Recents"))
        case .untitledAndDuplicates:
            (chrome, titled("New Tab", "New Tab", "", "Inbox (24) - Gmail"))
        case .longTitle:
            (chrome, titled("Window-level switching for the ⌘⇥ app switcher without replacing it: open questions, "
                              + "edge cases and rollout plan · Issue #1287 · koala42/bettertab",
                          "Inbox (24) - Gmail"))
        }
    }

    private static func titled(_ titles: String...) -> [WindowListItem] { titled(titles) }

    private static func titled(_ titles: [String]) -> [WindowListItem] {
        titles.map { WindowListItem(title: $0, isMinimized: false) }
    }
}

// MARK: - Stand-in switcher

/// Rough scaffolding in place of the native ⌘⇥ switcher: a capsule of app icons.
private final class StandInSwitcher {
    private static let tileSize: CGFloat = 120
    private static let tileGap: CGFloat = 4
    private static let iconSize: CGFloat = 100
    private static let padding = NSEdgeInsets(top: 22, left: 34, bottom: 40, right: 34)
    private static let nameGap: CGFloat = 7

    private let panel = KeyablePanel()
    private let background = NSVisualEffectView()
    private let highlight = TileHighlightView()
    private let nameLabel = NSTextField(labelWithString: "")
    private var iconViews: [NSImageView] = []
    private var names: [String] = []

    var frame: CGRect { panel.frame }
    var screen: NSScreen? { panel.screen }

    /// In global coordinates, like the AX frames the controller will read from the real switcher.
    var tileFrames: [CGRect] {
        names.indices.map { tileRect($0).offsetBy(dx: panel.frame.minX, dy: panel.frame.minY) }
    }

    init() {
        let content = NSView()
        panel.contentView = content
        background.material = .menu
        background.blendingMode = .behindWindow
        background.state = .active
        background.autoresizingMask = [.width, .height]
        content.addSubview(background)
        content.addSubview(highlight)
        nameLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        nameLabel.alignment = .center
        content.addSubview(nameLabel)
    }

    func show(apps: [(name: String, icon: NSImage)], highlighted: Int, on screen: NSScreen) {
        names = apps.map(\.name)
        iconViews.forEach { $0.removeFromSuperview() }
        iconViews = apps.enumerated().map { index, app in
            let view = NSImageView(image: app.icon)
            view.imageScaling = .scaleProportionallyUpOrDown
            view.frame = tileRect(index).insetBy(dx: (Self.tileSize - Self.iconSize) / 2,
                                                 dy: (Self.tileSize - Self.iconSize) / 2)
            panel.contentView?.addSubview(view)
            return view
        }

        let count = CGFloat(apps.count)
        let size = NSSize(width: Self.padding.left + Self.padding.right + count * Self.tileSize + max(count - 1, 0) * Self.tileGap,
                          height: Self.padding.top + Self.tileSize + Self.padding.bottom)
        let origin = NSPoint(x: (screen.frame.midX - size.width / 2).rounded(),
                             y: (screen.frame.midY - size.height / 2).rounded())
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        background.frame = NSRect(origin: .zero, size: size)
        background.maskImage = WindowListView.roundedMask(radius: size.height / 2)

        setHighlighted(highlighted)
        panel.makeKeyAndOrderFront(nil)
    }

    func setHighlighted(_ index: Int) {
        guard names.indices.contains(index) else { return }
        let tile = tileRect(index)
        highlight.frame = tile
        nameLabel.stringValue = names[index]
        nameLabel.sizeToFit()
        nameLabel.setFrameOrigin(NSPoint(x: (tile.midX - nameLabel.frame.width / 2).rounded(),
                                         y: tile.minY - Self.nameGap - nameLabel.frame.height))
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func tileRect(_ index: Int) -> CGRect {
        CGRect(x: Self.padding.left + CGFloat(index) * (Self.tileSize + Self.tileGap), y: Self.padding.bottom,
               width: Self.tileSize, height: Self.tileSize)
    }
}

/// Unlike the overlay panels, the stand-in takes key focus, so the preview's key monitor gets keys.
private final class KeyablePanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
}

private final class TileHighlightView: NSView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        NSColor(white: isDark ? 1 : 0, alpha: 0.16).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 28, yRadius: 28).fill()
    }
}
#endif
