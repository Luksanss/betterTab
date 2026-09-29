import AppKit

/// Window-count dots under the native switcher's icons: one per window, at most 4, for apps with
/// two or more windows. A click-through panel laid over the switcher.
final class DotsOverlay {
    static let maxDots = 4
    static let dotDiameter: CGFloat = 5
    static let dotGap: CGFloat = 4
    /// Dot centres sit this far above the bottom edge of an icon's frame. Unverified: it assumes
    /// the native AX icon frame leaves room below the icon, as the v5 tiles do.
    static let dotCentreAboveIconBottom: CGFloat = 5.5

    private let panel = OverlayPanel()
    private let dotsView = DotsView()

    init() {
        panel.ignoresMouseEvents = true
        panel.contentView = dotsView
    }

    /// Frames are AppKit global coordinates. Showing again replaces the dots, for counts that
    /// arrive after the switcher has appeared.
    func show(switcherFrame: CGRect, icons: [(frame: CGRect, windowCount: Int)]) {
        panel.setFrame(switcherFrame, display: false)
        dotsView.icons = icons.map { icon in
            (frame: icon.frame.offsetBy(dx: -switcherFrame.minX, dy: -switcherFrame.minY), windowCount: icon.windowCount)
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private final class DotsView: NSView {
    /// In this view's coordinates.
    var icons: [(frame: CGRect, windowCount: Int)] = [] {
        didSet { needsDisplay = true }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        NSColor.labelColor.withAlphaComponent(isDark ? 0.72 : 0.6).setFill()

        let diameter = DotsOverlay.dotDiameter
        for icon in icons where icon.windowCount >= 2 {
            let count = min(icon.windowCount, DotsOverlay.maxDots)
            let width = CGFloat(count) * diameter + CGFloat(count - 1) * DotsOverlay.dotGap
            let centreY = icon.frame.minY + DotsOverlay.dotCentreAboveIconBottom
            var x = icon.frame.midX - width / 2
            for _ in 0..<count {
                NSBezierPath(ovalIn: NSRect(x: x, y: centreY - diameter / 2, width: diameter, height: diameter)).fill()
                x += diameter + DotsOverlay.dotGap
            }
        }
    }
}
