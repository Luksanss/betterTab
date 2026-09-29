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
        #if DEBUG
        Self.debugInstances.append(SelfTestWeak(object: self))
        #endif
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
        // An icon AX hasn't given a frame for yet arrives empty; its dots come with the next read.
        for icon in icons where icon.windowCount >= 2 && !icon.frame.isEmpty {
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

#if DEBUG
/// What the self-test reads. Read-only; the geometry repeats `DotsView.draw`'s.
extension DotsOverlay {
    struct DebugIcon {
        /// AppKit global.
        let frame: CGRect
        let windowCount: Int
        /// The dots drawn under this icon.
        let dotCount: Int
        /// The row of dots, AppKit global; nil when none are drawn.
        let dotsFrame: CGRect?
    }

    struct DebugState {
        let isVisible: Bool
        let frame: CGRect
        let icons: [DebugIcon]
    }

    fileprivate static var debugInstances: [SelfTestWeak<DotsOverlay>] = []

    /// Every live overlay, oldest first.
    static var debugStates: [DebugState] {
        debugInstances.removeAll { $0.object == nil }
        return debugInstances.compactMap { $0.object?.debugState }
    }

    var debugState: DebugState {
        let origin = panel.frame.origin
        let icons = dotsView.icons.map { icon -> DebugIcon in
            let frame = icon.frame.offsetBy(dx: origin.x, dy: origin.y)
            guard icon.windowCount >= 2, !icon.frame.isEmpty else {
                return DebugIcon(frame: frame, windowCount: icon.windowCount, dotCount: 0, dotsFrame: nil)
            }
            let count = min(icon.windowCount, Self.maxDots)
            let width = CGFloat(count) * Self.dotDiameter + CGFloat(count - 1) * Self.dotGap
            let centreY = frame.minY + Self.dotCentreAboveIconBottom
            let dots = CGRect(x: frame.midX - width / 2, y: centreY - Self.dotDiameter / 2,
                              width: width, height: Self.dotDiameter)
            return DebugIcon(frame: frame, windowCount: icon.windowCount, dotCount: count, dotsFrame: dots)
        }
        return DebugState(isVisible: panel.isVisible, frame: panel.frame, icons: icons)
    }
}
#endif
