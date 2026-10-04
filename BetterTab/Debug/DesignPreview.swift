#if DEBUG
import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

/// The stack edges over a stand-in switcher, for checking them by eye. Debug builds only.
///
/// The real `StackEdgesOverlay` is laid over the stand-in's icon frames, the way the controller lays
/// it over the native switcher's AX frames. Tab moves the highlight on, and Esc closes.
final class DesignPreview {
    static let shared = DesignPreview()

    private let switcher = StandInSwitcher()
    private let stackEdges = StackEdgesOverlay()
    private var highlighted = 0
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    func show() {
        tearDown()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let apps = PreviewApp.standard
        // As after one ⌘⇥ from Slack.
        highlighted = 1

        // The local key monitor only sees keys while BetterTab is active.
        NSApp.unhide(nil)
        NSApp.activate()
        switcher.show(apps: apps.map { ($0.name, $0.icon) }, highlighted: highlighted, on: screen)
        stackEdges.show(switcherFrame: switcher.frame,
                        icons: zip(switcher.iconFrames, apps).map { (frame: $0, windowCount: $1.windows) })

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
        stackEdges.hide()
        switcher.hide()
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.modifierFlags.contains(.command) { return event }
        switch Int(event.keyCode) {
        case kVK_Tab:
            highlighted = (highlighted + 1) % PreviewApp.standard.count
            switcher.setHighlighted(highlighted)
        case kVK_Escape:
            close()
        default:
            break
        }
        return nil
    }
}

// MARK: - Scenario data

private struct PreviewApp {
    let name: String
    let bundleID: String
    /// Windows on every Space, the number the stack edges show.
    let windows: Int

    var icon: NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }
        return NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
    }

    /// No count, then 3, 2, 2 and 11, then none.
    static let standard: [PreviewApp] = [
        PreviewApp(name: "Slack", bundleID: "com.tinyspeck.slackmacgap", windows: 1),
        PreviewApp(name: "Google Chrome", bundleID: "com.google.Chrome", windows: 3),
        PreviewApp(name: "Terminal", bundleID: "com.apple.Terminal", windows: 2),
        PreviewApp(name: "Visual Studio Code", bundleID: "com.microsoft.VSCode", windows: 2),
        PreviewApp(name: "Finder", bundleID: "com.apple.finder", windows: 11),
        PreviewApp(name: "Notes", bundleID: "com.apple.Notes", windows: 1),
        PreviewApp(name: "Claude", bundleID: "com.anthropic.claudefordesktop", windows: 1),
        PreviewApp(name: "Calendar", bundleID: "com.apple.iCal", windows: 1),
        PreviewApp(name: "Photos", bundleID: "com.apple.Photos", windows: 1),
        PreviewApp(name: "System Settings", bundleID: "com.apple.systempreferences", windows: 1),
    ]
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
        background.maskImage = WindowSwitcherView.roundedMask(radius: Self.cornerRadius)

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
