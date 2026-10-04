import AppKit

/// Stack edges on the native switcher's icons, design v8 direction C, "Count": for an app with two
/// or more windows, the number of its windows in a capsule on the icon's bottom-left corner, where
/// Finder puts its alias arrow. macOS's notification badge owns the top right, and the app's name
/// the bottom. The number has no ceiling, so it says what ⌘§ will be: 2 is a toggle, 5 a look at
/// the HUD. A click-through panel laid over the switcher.
final class StackEdgesOverlay {
    /// The visible icon, a rounded square, is this share of the icon's AX frame. Apple's icon grid
    /// draws an 824 pt body on a 1024 pt canvas, but the 128 and 256 px renditions the switcher
    /// draws snap it to 104 of 128, measured on macOS 27 (and the highlight's top is 8 pt above it).
    static let bodyScale: CGFloat = 104.0 / 128
    /// Sizes are shares of the body's side. The capsule's left side and bottom sit this far past the
    /// body's, so it hangs off the corner a little, as a badge does.
    static let overhang: CGFloat = 0.02
    static let capsuleHeight: CGFloat = 0.26
    /// The capsule grows rightward by this much per digit, past a padding, and is never narrower
    /// than it is tall.
    static let digitWidth: CGFloat = 0.099
    static let padding: CGFloat = 0.14
    /// SF Pro Rounded Semibold, tabular figures.
    static let fontSize: CGFloat = 0.165
    /// The digits' middle sits this far below the capsule's, which reads as centred.
    static let opticalDrop: CGFloat = 0.005
    /// A line on the capsule's edge, half outside, so a white capsule on white glass still has an
    /// outline.
    static let rimWidth: CGFloat = 0.005
    static let shadowDrop: CGFloat = 0.01
    /// The shadow's Gaussian σ. Core Graphics' `blur` is twice it (measured on macOS 27).
    static let shadowSigma: CGFloat = 0.015

    /// What changes between light and dark.
    private struct Style {
        let fill: CGColor
        let text: CGColor
        let rim: CGColor
        let shadow: CGColor

        static let light = Style(fill: srgb(0xFFFFFF), text: srgb(0x1D1D1F),
                                 rim: CGColor(gray: 0, alpha: 0.10), shadow: CGColor(gray: 0, alpha: 0.22))
        static let dark = Style(fill: srgb(0x3A3A3C), text: srgb(0xF5F5F7),
                                rim: CGColor(gray: 1, alpha: 0.14), shadow: CGColor(gray: 0, alpha: 0.50))

        private static func srgb(_ hex: Int) -> CGColor {
            CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }

    private let panel = OverlayPanel()
    private let edgesView = StackEdgesView()

    init() {
        panel.ignoresMouseEvents = true
        panel.contentView = edgesView
        #if DEBUG
        Self.debugInstances.append(SelfTestWeak(object: self))
        #endif
    }

    /// Frames are AppKit global coordinates. Showing again replaces the counts, for counts that
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

    /// The icon's visible body, and the capsule on its bottom-left corner. No capsule for fewer than
    /// two windows, or a frame AX hasn't given yet.
    static func layout(iconFrame: CGRect, windowCount: Int) -> (body: CGRect, capsule: CGRect?) {
        let side = min(iconFrame.width, iconFrame.height) * bodyScale
        let body = CGRect(x: iconFrame.midX - side / 2, y: iconFrame.midY - side / 2, width: side, height: side)
        guard windowCount >= 2, !iconFrame.isEmpty else { return (body, nil) }
        let digits = CGFloat(String(windowCount).count)
        let width = max(capsuleHeight, digits * digitWidth + padding)
        let capsule = CGRect(x: body.minX - side * overhang, y: body.minY - side * overhang,
                             width: side * width, height: side * capsuleHeight)
        return (body, capsule)
    }

    /// Draws every icon's count, in the icons' coordinates, y up. Shadows are in base space, which
    /// for a window and an `NSGraphicsContext(bitmapImageRep:)` is points.
    static func draw(_ icons: [(frame: CGRect, windowCount: Int)], isDark: Bool, in context: CGContext) {
        let style = isDark ? Style.dark : Style.light
        for icon in icons {
            let placed = layout(iconFrame: icon.frame, windowCount: icon.windowCount)
            guard let capsule = placed.capsule else { continue }
            let side = placed.body.width
            let shape = CGPath(roundedRect: capsule, cornerWidth: capsule.height / 2,
                               cornerHeight: capsule.height / 2, transform: nil)

            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -side * shadowDrop), blur: 2 * side * shadowSigma,
                              color: style.shadow)
            context.addPath(shape)
            context.setFillColor(style.fill)
            context.fillPath()
            context.restoreGState()

            context.saveGState()
            context.addPath(shape)
            context.setStrokeColor(style.rim)
            context.setLineWidth(side * rimWidth)
            context.strokePath()
            context.restoreGState()

            drawNumber(icon.windowCount, centredIn: capsule, side: side, colour: style.text, in: context)
        }
    }

    private static func drawNumber(_ number: Int, centredIn capsule: CGRect, side: CGFloat, colour: CGColor,
                                   in context: CGContext) {
        let font = numberFont(size: side * fontSize)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(number), attributes: [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): colour,
        ]))
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        // Figures are as tall as capitals.
        let baseline = capsule.midY - font.capHeight / 2 - side * opticalDrop
        // The text matrix isn't part of the graphics state, so it's put back by hand.
        let textMatrix = context.textMatrix
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: capsule.midX - width / 2, y: baseline)
        CTLineDraw(line, context)
        context.textMatrix = textMatrix
    }

    private static func numberFont(size: CGFloat) -> NSFont {
        let semibold = NSFont.systemFont(ofSize: size, weight: .semibold)
        let rounded = semibold.fontDescriptor.withDesign(.rounded) ?? semibold.fontDescriptor
        let tabular = rounded.addingAttributes([.featureSettings: [[
            NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
            NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
        ]]])
        return NSFont(descriptor: tabular, size: size) ?? semibold
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
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        StackEdgesOverlay.draw(icons, isDark: isDark, in: context)
    }
}

#if DEBUG
/// What the self-test reads. Read-only; the geometry comes from `layout`, as `draw` does.
extension StackEdgesOverlay {
    struct DebugIcon {
        /// AppKit global.
        let frame: CGRect
        let windowCount: Int
        /// The number drawn on this icon; nil when none is.
        let count: Int?
        /// The capsule's frame, AppKit global; nil when none is drawn.
        let capsule: CGRect?
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
            let capsule = Self.layout(iconFrame: frame, windowCount: icon.windowCount).capsule
            return DebugIcon(frame: frame, windowCount: icon.windowCount,
                             count: capsule == nil ? nil : icon.windowCount, capsule: capsule)
        }
        return DebugState(isVisible: panel.isVisible, frame: panel.frame, icons: icons)
    }
}
#endif
