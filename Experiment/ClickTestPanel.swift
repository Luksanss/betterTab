import AppKit
import os

/// For test 0b's follow-up: does clicking our own non-activating panel close or confirm the held
/// switcher? Shown only during a hold, and only when the menu toggle is on.
final class ClickTestPanel {
    /// Used until the switcher's window layer has been logged.
    static let fallbackLevel = NSWindow.Level.popUpMenu

    private var panel: NSPanel?

    static func level(aboveSwitcherLayer layer: Int?) -> NSWindow.Level {
        layer.map { NSWindow.Level(rawValue: $0 + 1) } ?? fallbackLevel
    }

    func show(switcherLayer: Int?) {
        guard panel == nil, let screen = NSScreen.main else { return }
        let size = NSSize(width: 200, height: 60)
        let origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 40)
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = Self.level(aboveSwitcherLayer: switcherLayer)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .systemYellow
        panel.contentView = ClickTestView(frame: NSRect(origin: .zero, size: size))
        panel.orderFrontRegardless()
        self.panel = panel
        Log.panel.notice("""
            PANEL shown at level \(panel.level.rawValue, privacy: .public) \
            (\(switcherLayer == nil ? "fallback .popUpMenu" : "switcher layer + 1", privacy: .public))
            """)
    }

    func switcherLayerChanged(_ layer: Int) {
        guard let panel else { return }
        let level = Self.level(aboveSwitcherLayer: layer)
        guard panel.level != level else { return }
        panel.level = level
        Log.panel.notice("PANEL moved to level \(level.rawValue, privacy: .public) (switcher layer + 1)")
    }

    func close() {
        guard let panel else { return }
        panel.orderOut(nil)
        self.panel = nil
        Log.panel.notice("PANEL closed")
    }
}

private final class ClickTestView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let label = NSTextField(labelWithString: "Click me")
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.textColor = .black
        label.sizeToFit()
        label.frame.origin = NSPoint(x: (frame.width - label.frame.width) / 2, y: (frame.height - label.frame.height) / 2)
        addSubview(label)
    }

    required init?(coder: NSCoder) { nil }

    // Deliver the click without activating the app first.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Clicks on the label count as clicks on the panel.
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }

    override func mouseDown(with event: NSEvent) {
        Log.panel.notice("PANEL mouseDown received by the click-test panel")
    }

    override func mouseUp(with event: NSEvent) {
        Log.panel.notice("PANEL mouseUp received by the click-test panel")
    }
}
