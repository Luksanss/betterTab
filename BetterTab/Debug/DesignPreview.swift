#if DEBUG
import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

/// The v5 design's scenarios, for checking the stack edges and the window list by eye. Debug
/// builds only.
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

/// Shows the stack edges and the window list over a stand-in switcher.
///
/// The real `StackEdgesOverlay` and `WindowList` are laid over the stand-in's icon frames, the way
/// the controller lays them over the native switcher's AX frames. Keys work as in Picking: letters,
/// arrows and Return pick, Esc closes, and Tab moves on to the next app as ⌘⇥ followed by a release
/// would.
final class DesignPreview {
    static let shared = DesignPreview()

    private let switcher = StandInSwitcher()
    private let stackEdges = StackEdgesOverlay()
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
        stackEdges.show(switcherFrame: switcher.frame,
                  icons: zip(switcher.iconFrames, apps).map { (frame: $0, windowCount: $1.windows.count) })
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
        stackEdges.hide()
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
                  iconFrame: switcher.iconFrames[highlighted], screen: screen)
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
        "Add window list above switcher by jdoe · Pull Request #412 · example/bettertab",
        "Apple Developer Documentation",
    ]

    private static let standard: [PreviewApp] = [
        PreviewApp(name: "Slack", bundleID: "com.tinyspeck.slackmacgap", windows: titled("Slack")),
        PreviewApp(name: "Google Chrome", bundleID: chrome, windows: titled(chromeTitles)),
        PreviewApp(name: "Terminal", bundleID: terminal,
                   windows: titled("jdoe — -zsh — 120×40", "bettertab — swift build — 120×40")),
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
            (terminal, titled("jdoe — -zsh — 120×40", "bettertab — swift build — 120×40"))
        case .notes1:
            (notes, titled("Notes"))
        case .minimized:
            (code, titled("WindowList.swift — bettertab", "README.md — dotfiles")
                + [WindowListItem(title: "App.tsx — website", isMinimized: true)])
        case .eleven:
            (finder, titled("Downloads", "Projects", "bettertab", "Screenshots", "Desktop", "Documents",
                          "Invoices 2026", "Design Assets", "Applications", "website", "Recents"))
        case .untitledAndDuplicates:
            (chrome, titled("New Tab", "New Tab", "", "Inbox (24) - Gmail"))
        case .longTitle:
            (chrome, titled("Window-level switching for the ⌘⇥ app switcher without replacing it: open questions, "
                              + "edge cases and rollout plan · Issue #1287 · example/bettertab",
                          "Inbox (24) - Gmail"))
        }
    }

    private static func titled(_ titles: String...) -> [WindowListItem] { titled(titles) }

    private static func titled(_ titles: [String]) -> [WindowListItem] {
        titles.map { WindowListItem(title: $0, isMinimized: false) }
    }
}

// MARK: - Stand-in switcher

/// Rough scaffolding in place of the native ⌘⇥ switcher: a row of app icons, with the geometry
/// measured from the real one on macOS 27 (five apps: a 712 × 176 pt switcher, 128 pt icons).
private final class StandInSwitcher {
    /// An icon's frame, as AX reports it. The icon image fills it.
    private static let iconSize: CGFloat = 128
    private static let iconGap: CGFloat = 6
    private static let padding: CGFloat = 24
    private static let cornerRadius: CGFloat = 44
    /// The highlight is the icon's frame inset by this much.
    private static let highlightInset: CGFloat = 4
    private static let nameGap: CGFloat = 1

    private let panel = KeyablePanel()
    private let background = NSVisualEffectView()
    private let highlight = TileHighlightView()
    private let nameLabel = NSTextField(labelWithString: "")
    private var iconViews: [NSImageView] = []
    private var names: [String] = []

    var frame: CGRect { panel.frame }
    var screen: NSScreen? { panel.screen }

    /// In global coordinates, like the AX frames the controller will read from the real switcher.
    var iconFrames: [CGRect] {
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
            view.frame = tileRect(index)
            panel.contentView?.addSubview(view)
            return view
        }

        let count = CGFloat(apps.count)
        let size = NSSize(width: 2 * Self.padding + count * Self.iconSize + max(count - 1, 0) * Self.iconGap,
                          height: 2 * Self.padding + Self.iconSize)
        let origin = NSPoint(x: (screen.frame.midX - size.width / 2).rounded(),
                             y: (screen.frame.midY - size.height / 2).rounded())
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        background.frame = NSRect(origin: .zero, size: size)
        background.maskImage = WindowListView.roundedMask(radius: Self.cornerRadius)

        setHighlighted(highlighted)
        panel.makeKeyAndOrderFront(nil)
    }

    func setHighlighted(_ index: Int) {
        guard names.indices.contains(index) else { return }
        let tile = tileRect(index)
        highlight.frame = tile.insetBy(dx: Self.highlightInset, dy: Self.highlightInset)
        nameLabel.stringValue = names[index]
        nameLabel.sizeToFit()
        nameLabel.setFrameOrigin(NSPoint(x: (tile.midX - nameLabel.frame.width / 2).rounded(),
                                         y: tile.minY - Self.nameGap - nameLabel.frame.height))
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func tileRect(_ index: Int) -> CGRect {
        CGRect(x: Self.padding + CGFloat(index) * (Self.iconSize + Self.iconGap), y: Self.padding,
               width: Self.iconSize, height: Self.iconSize)
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
