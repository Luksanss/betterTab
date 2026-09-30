import AppKit

/// Stack edges above the native switcher's icons: for an app with two or more windows, the top
/// edges of more windows peek out behind its icon, one edge for two windows and two for three or
/// more. A click-through panel laid over the switcher.
final class StackEdgesOverlay {
    static let maxEdges = 2
    /// The visible icon, a rounded square, is this share of the icon's AX frame: Apple's icon grid
    /// draws an 824 pt body on a 1024 pt canvas. Measured on macOS 27: 128 pt frames, 103 pt bodies.
    static let bodyScale: CGFloat = 824.0 / 1024
    /// Each edge rises this far above the one in front of it, as a share of the body's side. Two
    /// edges fill the room up to the Dock's highlight, which is the frame inset by 4 pt: 8.5 pt
    /// above a 103 pt body.
    static let rise: CGFloat = 0.041
    /// Each edge is this much narrower than the one in front of it, as a share of the body's side.
    static let narrowing: CGFloat = 0.10
    /// Corner radius as a share of the width, close to the icon body's own corners.
    static let cornerScale: CGFloat = 0.225
    /// The clear line between an edge and whatever is in front of it, as a share of the body's
    /// side: 1 pt on a 103 pt body, thinner when the switcher shrinks its icons.
    static let gap: CGFloat = 1.0 / 103

    private let panel = OverlayPanel()
    private let edgesView = StackEdgesView()

    init() {
        panel.ignoresMouseEvents = true
        panel.contentView = edgesView
        #if DEBUG
        Self.debugInstances.append(SelfTestWeak(object: self))
        #endif
    }

    /// Frames are AppKit global coordinates. Showing again replaces the edges, for counts that
    /// arrive after the switcher has appeared.
    func show(switcherFrame: CGRect, icons: [(frame: CGRect, windowCount: Int)]) {
        panel.setFrame(switcherFrame, display: false)
        edgesView.icons = icons.map { icon in
            (frame: icon.frame.offsetBy(dx: -switcherFrame.minX, dy: -switcherFrame.minY), windowCount: icon.windowCount)
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// The icon's visible body, and the windows peeking out behind it, front to back. No edges for
    /// fewer than two windows, or a frame AX hasn't given yet.
    static func stack(iconFrame: CGRect, windowCount: Int) -> (body: CGRect, edges: [CGRect]) {
        let side = min(iconFrame.width, iconFrame.height) * bodyScale
        let body = CGRect(x: iconFrame.midX - side / 2, y: iconFrame.midY - side / 2, width: side, height: side)
        guard windowCount >= 2, !iconFrame.isEmpty else { return (body, []) }
        let edges = (1...min(windowCount - 1, maxEdges)).map { depth in
            let width = side * (1 - narrowing * CGFloat(depth))
            return CGRect(x: body.midX - width / 2, y: body.minY + side * rise * CGFloat(depth), width: width, height: side)
        }
        return (body, edges)
    }
}

private final class StackEdgesView: NSView {
    /// In this view's coordinates.
    var icons: [(frame: CGRect, windowCount: Int)] = [] {
        didSet { needsDisplay = true }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current else { return }
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        // Front edge first; the one behind it is fainter. Both were too faint to read at a glance
        // at [0.56, 0.34] dark and [0.36, 0.22] light.
        let alphas: [CGFloat] = isDark ? [0.85, 0.55] : [0.62, 0.40]

        for icon in icons {
            let stack = StackEdgesOverlay.stack(iconFrame: icon.frame, windowCount: icon.windowCount)
            guard !stack.edges.isEmpty else { continue }
            let gap = stack.body.width * StackEdgesOverlay.gap
            // A layer of its own, so each knockout clears only the edges behind it.
            context.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
            for depth in stack.edges.indices.reversed() {
                let edge = stack.edges[depth]
                let inFront = depth == 0 ? stack.body : stack.edges[depth - 1]
                context.compositingOperation = .sourceOver
                NSColor.labelColor.withAlphaComponent(alphas[depth]).setFill()
                Self.roundedRect(edge).fill()
                context.compositingOperation = .clear
                Self.roundedRect(inFront.insetBy(dx: -gap, dy: -gap)).fill()
            }
            context.cgContext.endTransparencyLayer()
        }
        context.compositingOperation = .sourceOver
    }

    private static func roundedRect(_ rect: CGRect) -> NSBezierPath {
        let radius = rect.width * StackEdgesOverlay.cornerScale
        return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }
}

#if DEBUG
/// What the self-test reads. Read-only; the geometry comes from `stack`, as `draw` does.
extension StackEdgesOverlay {
    struct DebugIcon {
        /// AppKit global.
        let frame: CGRect
        let windowCount: Int
        /// The edges drawn behind this icon.
        let edgeCount: Int
        /// The front edge's frame, AppKit global; nil when no edges are drawn.
        let frontEdge: CGRect?
        /// The top of the back edge, AppKit global; nil when no edges are drawn.
        let top: CGFloat?
    }

    struct DebugState {
        let isVisible: Bool
        let frame: CGRect
        let icons: [DebugIcon]
    }

    fileprivate static var debugInstances: [SelfTestWeak<StackEdgesOverlay>] = []

    /// Every live overlay, oldest first.
    static var debugStates: [DebugState] {
        debugInstances.removeAll { $0.object == nil }
        return debugInstances.compactMap { $0.object?.debugState }
    }

    var debugState: DebugState {
        let origin = panel.frame.origin
        let icons = edgesView.icons.map { icon -> DebugIcon in
            let frame = icon.frame.offsetBy(dx: origin.x, dy: origin.y)
            let stack = Self.stack(iconFrame: frame, windowCount: icon.windowCount)
            guard let front = stack.edges.first, let back = stack.edges.last else {
                return DebugIcon(frame: frame, windowCount: icon.windowCount, edgeCount: 0, frontEdge: nil, top: nil)
            }
            return DebugIcon(frame: frame, windowCount: icon.windowCount, edgeCount: stack.edges.count,
                             frontEdge: front, top: back.maxY)
        }
        return DebugState(isVisible: panel.isVisible, frame: panel.frame, icons: icons)
    }
}
#endif
