import AppKit

/// The ⌘§ switcher's HUD: a row of tiles, one per window, each a miniature of the window's display
/// with the window's outline at its real position, and the highlighted window's title under the
/// row. Sizes come from design v6 ("window outlines"), in points.
final class WindowSwitcherView: NSView {
    static let cornerRadius: CGFloat = 28
    static let padding: CGFloat = 14
    static let minWidth: CGFloat = 400
    static let tileSpacing: CGFloat = 4
    static let titleSpacing: CGFloat = 10
    static let titleMaxWidth: CGFloat = 440
    static let titleInset: CGFloat = 12

    /// A tile under the pointer, by tile number (a position in `model.tiles`).
    var onHover: ((Int) -> Void)?
    /// A click that went down and up on the same tile, by tile number.
    var onClick: ((Int) -> Void)?

    private let background = WindowSwitcherView.makeBackground()
    private var tileViews: [WindowSwitcherTileView] = []
    private let overflow = WindowSwitcherOverflowView()
    private let titleView = WindowSwitcherTitleView()
    private var pressedTile: Int?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.minWidth, height: 0))
        wantsLayer = true
        background.autoresizingMask = [.width, .height]
        addSubview(background)
        addSubview(overflow)
        addSubview(titleView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    /// The natural size, before any scaling to fit the display.
    static func size(for model: WindowSwitcherModel) -> NSSize {
        metrics(for: model).size
    }

    /// Resizes to fit the model, times `scale`, and lays out the tiles. Cheap enough to call on
    /// every highlight move: only tiles that changed redraw.
    func render(_ model: WindowSwitcherModel, labels: [String], scale: CGFloat = 1) {
        let metrics = Self.metrics(for: model)
        // The frame is scaled and the bounds aren't, so everything below lays out in design points.
        setFrameSize(NSSize(width: (metrics.size.width * scale).rounded(),
                            height: (metrics.size.height * scale).rounded()))
        setBoundsSize(metrics.size)
        background.frame = bounds

        while tileViews.count < model.tiles.count {
            let tile = WindowSwitcherTileView()
            addSubview(tile, positioned: .below, relativeTo: titleView)
            tileViews.append(tile)
        }
        while tileViews.count > model.tiles.count {
            tileViews.removeLast().removeFromSuperview()
        }

        let top = Self.padding
        var x = ((bounds.width - metrics.rowWidth) / 2).rounded(.down)
        for (index, (tileView, tile)) in zip(tileViews, model.tiles).enumerated() {
            tileView.frame = NSRect(x: x, y: top, width: WindowSwitcherTileView.width, height: WindowSwitcherTileView.height)
            x += WindowSwitcherTileView.width + Self.tileSpacing
            tileView.configure(letter: index < labels.count ? labels[index] : "", tile: tile,
                               isHighlighted: index == model.highlight)
        }

        // After the last tile's spacing, so it keeps the 4 pt gap.
        overflow.isHidden = model.overflowCount == 0
        overflow.frame = NSRect(x: x, y: top, width: WindowSwitcherOverflowView.width, height: WindowSwitcherTileView.height)
        overflow.text = "+\(model.overflowCount) more"

        let highlighted = model.tiles.indices.contains(model.highlight) ? model.tiles[model.highlight] : nil
        let titleWidth = min(Self.titleMaxWidth, bounds.width - (Self.padding + Self.titleInset) * 2)
        titleView.frame = NSRect(x: ((bounds.width - titleWidth) / 2).rounded(),
                                 y: top + WindowSwitcherTileView.height + Self.titleSpacing,
                                 width: titleWidth, height: CGFloat(metrics.titleLines) * WindowSwitcherTitleView.lineHeight)
        titleView.configure(title: highlighted?.title ?? "", isMinimized: highlighted?.isMinimized ?? false)
    }

    /// The HUD's size depends on every title, not just the highlighted one, so it keeps its size
    /// while the highlight moves: the widest title sets the width, and if any title needs two
    /// lines, both are kept free.
    private static func metrics(for model: WindowSwitcherModel) -> (size: NSSize, rowWidth: CGFloat, titleLines: Int) {
        let tiles = CGFloat(model.tiles.count)
        let hasOverflow = model.overflowCount > 0
        var rowWidth = tiles * WindowSwitcherTileView.width + max(tiles - 1, 0) * tileSpacing
        if hasOverflow { rowWidth += (tiles > 0 ? tileSpacing : 0) + WindowSwitcherOverflowView.width }

        let widestTitle = model.tiles.map { WindowSwitcherTitleView.width(of: $0.title) }.max() ?? 0
        let titleBlockWidth = min(widestTitle, titleMaxWidth) + titleInset * 2
        let maxWidth = max(560, padding * 2 + tiles * (WindowSwitcherTileView.width + tileSpacing)
                           + (hasOverflow ? WindowSwitcherOverflowView.width + tileSpacing : 0))
        let width = max(minWidth, min(maxWidth, max(rowWidth, titleBlockWidth) + padding * 2))

        let titleLines = widestTitle > titleMaxWidth ? WindowSwitcherTitleView.maxLines : 1
        let height = padding + WindowSwitcherTileView.height + titleSpacing
            + CGFloat(titleLines) * WindowSwitcherTitleView.lineHeight + padding
        return (NSSize(width: width, height: height), rowWidth, titleLines)
    }

    // MARK: Mouse

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // .activeAlways: BetterTab is never the active app while the switcher is up.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hover(event) }
    override func mouseMoved(with event: NSEvent) { hover(event) }

    override func mouseDown(with event: NSEvent) {
        pressedTile = tile(at: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressedTile = nil }
        guard let tile = tile(at: event), tile == pressedTile else { return }
        onClick?(tile)
    }

    private func hover(_ event: NSEvent) {
        if let tile = tile(at: event) { onHover?(tile) }
    }

    /// The "+N more" tile isn't one of these, so it can't be hovered or clicked.
    private func tile(at event: NSEvent) -> Int? {
        let point = convert(event.locationInWindow, from: nil)
        return tileViews.firstIndex { $0.frame.contains(point) }
    }

    // MARK: Background

    /// A system material, so it follows light and dark mode and Reduce Transparency. `.hudWindow`
    /// is the closest to the native ⌘⇥ switcher's glass, which the design copies.
    private static func makeBackground() -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = roundedMask(radius: cornerRadius)
        return view
    }

    /// A stretchable rounded rect. For behind-window blending, a mask image is what clips the blur
    /// and gives the window shadow its shape.
    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// One window: the display it's on, with the window's outline, and the letter badge under it.
final class WindowSwitcherTileView: NSView {
    static let width: CGFloat = 120
    static let height: CGFloat = 112
    private static let cornerRadius: CGFloat = 20
    /// Where the display box goes. 92 × 60 is the main display (1512 × 982); other shapes are fitted
    /// inside and centred, so the badges stay in line.
    private static let displaySlot = NSRect(x: (width - 92) / 2, y: 16, width: 92, height: 60)
    private static let displayRadius: CGFloat = 4
    private static let outlineRadius: CGFloat = 3
    private static let outlineStroke: CGFloat = 1.5
    /// So a tiny window still shows.
    private static let minimumOutline = NSSize(width: 4, height: 3)
    private static let badgeTop = displaySlot.maxY + 10
    private static let badgeSize: CGFloat = 20
    private static let badgeRadius: CGFloat = 5
    private static let markerGap: CGFloat = 5
    private static let badgeFont = NSFont.systemFont(ofSize: 11.5, weight: .semibold)

    private var letter = ""
    private var tile: WindowSwitcherModel.Tile?
    private var isHighlighted = false
    private let glyph = MinimizedGlyphView()

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.height))
        glyph.isHidden = true
        // MinimizedGlyphView draws at 0.7; the design wants 0.6 here.
        glyph.alphaValue = 0.6 / 0.7
        addSubview(glyph)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    func configure(letter: String, tile: WindowSwitcherModel.Tile, isHighlighted: Bool) {
        guard letter != self.letter || tile != self.tile || isHighlighted != self.isHighlighted else { return }
        self.letter = letter
        self.tile = tile
        self.isHighlighted = isHighlighted
        glyph.isHidden = !tile.isMinimized
        let badge = badgeFrame
        glyph.setFrameOrigin(NSPoint(x: badge.maxX + Self.markerGap, y: badge.midY - glyph.frame.height / 2))
        setAccessibilityLabel("\(letter): \(tile.title)")
        setAccessibilitySelected(isHighlighted)
        needsDisplay = true
    }

    /// The badge and the minimized marker are centred together.
    private var badgeFrame: NSRect {
        let rowWidth = Self.badgeSize + (tile?.isMinimized == true ? Self.markerGap + glyph.frame.width : 0)
        return NSRect(x: ((Self.width - rowWidth) / 2).rounded(), y: Self.badgeTop, width: Self.badgeSize, height: Self.badgeSize)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let tile else { return }
        let isDark = effectiveAppearance.isDark
        if isHighlighted {
            NSColor(white: isDark ? 1 : 0, alpha: 0.16).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius).fill()
        }

        let box = Self.displayBox(for: tile.displayFrame)
        NSColor(white: isDark ? 1 : 0, alpha: isDark ? 0.05 : 0.04).setFill()
        NSBezierPath(roundedRect: box, xRadius: Self.displayRadius, yRadius: Self.displayRadius).fill()
        NSColor(white: isDark ? 1 : 0, alpha: isDark ? 0.16 : 0.13).setStroke()
        let boxEdge = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5),
                                   xRadius: Self.displayRadius - 0.5, yRadius: Self.displayRadius - 0.5)
        boxEdge.lineWidth = 1
        boxEdge.stroke()

        if let outline = Self.outline(of: tile.windowFrame, on: tile.displayFrame, in: box) {
            drawOutline(outline, clippedTo: box, isMinimized: tile.isMinimized, isDark: isDark)
        }
        drawBadge(isDark: isDark)
    }

    private func drawOutline(_ rect: NSRect, clippedTo box: NSRect, isMinimized: Bool, isDark: Bool) {
        let accent = NSColor.controlAccentColor
        let fill = isHighlighted ? accent.withAlphaComponent(0.22) : NSColor(white: 1, alpha: isDark ? 0.1 : 0.6)
        let stroke = isHighlighted ? accent
            : isDark ? NSColor(srgbRed: 245 / 255, green: 245 / 255, blue: 247 / 255, alpha: 0.7)
            : NSColor(srgbRed: 29 / 255, green: 29 / 255, blue: 31 / 255, alpha: 0.55)

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: box, xRadius: Self.displayRadius, yRadius: Self.displayRadius).addClip()
        // A minimized window fades as a whole, fill and edge together.
        let context = NSGraphicsContext.current?.cgContext
        if isMinimized {
            context?.setAlpha(0.4)
            context?.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: Self.outlineRadius, yRadius: Self.outlineRadius).fill()
        // Inside the rect, like a CSS border.
        let inset = Self.outlineStroke / 2
        let edge = NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset),
                                xRadius: Self.outlineRadius - inset, yRadius: Self.outlineRadius - inset)
        edge.lineWidth = Self.outlineStroke
        stroke.setStroke()
        edge.stroke()
        if isMinimized { context?.endTransparencyLayer() }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawBadge(isDark: Bool) {
        let badge = badgeFrame
        let fill = isHighlighted ? NSColor.controlAccentColor
            : isDark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: 0.07)
        fill.setFill()
        NSBezierPath(roundedRect: badge, xRadius: Self.badgeRadius, yRadius: Self.badgeRadius).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.badgeFont, .foregroundColor: isHighlighted ? NSColor.white : .labelColor,
        ]
        let size = (letter as NSString).size(withAttributes: attributes)
        (letter as NSString).draw(at: NSPoint(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2),
                                  withAttributes: attributes)
    }

    /// The display's shape, fitted into the slot and centred. The whole slot if the display is unknown.
    private static func displayBox(for display: CGRect) -> NSRect {
        let slot = displaySlot
        guard !display.isNull, display.width > 0, display.height > 0 else { return slot }
        let scale = min(slot.width / display.width, slot.height / display.height)
        let width = halfPoint(display.width * scale)
        let height = halfPoint(display.height * scale)
        return NSRect(x: halfPoint(slot.midX - width / 2), y: halfPoint(slot.midY - height / 2), width: width, height: height)
    }

    /// The window's frame mapped from its display into the box, both top-left origin. Kept inside
    /// the box and at least `minimumOutline`. Nil when the window's frame is unknown.
    private static func outline(of window: CGRect, on display: CGRect, in box: NSRect) -> NSRect? {
        guard !window.isNull, !window.isInfinite, !display.isNull, display.width > 0, display.height > 0 else { return nil }
        // Separate scales, so a full-screen window fills the box exactly after the box's rounding.
        let scaleX = box.width / display.width
        let scaleY = box.height / display.height
        let x = span(from: (window.minX - display.minX) * scaleX, to: (window.maxX - display.minX) * scaleX,
                     within: box.width, minimum: minimumOutline.width)
        let y = span(from: (window.minY - display.minY) * scaleY, to: (window.maxY - display.minY) * scaleY,
                     within: box.height, minimum: minimumOutline.height)
        return NSRect(x: box.minX + x.start, y: box.minY + y.start, width: x.end - x.start, height: y.end - y.start)
    }

    /// One axis of `outline`: rounded to half points, clamped to 0…length, grown to `minimum`.
    private static func span(from start: CGFloat, to end: CGFloat, within length: CGFloat,
                             minimum: CGFloat) -> (start: CGFloat, end: CGFloat) {
        var start = min(max(halfPoint(start), 0), length)
        var end = min(max(halfPoint(end), 0), length)
        if end - start < minimum {
            start = min(max(halfPoint((start + end - minimum) / 2), 0), max(length - minimum, 0))
            end = min(start + minimum, length)
        }
        return (start, end)
    }

    private static func halfPoint(_ value: CGFloat) -> CGFloat {
        (value * 2).rounded() / 2
    }
}

/// The highlighted window's title, under the tiles: centred, up to two lines, the tail truncated.
final class WindowSwitcherTitleView: NSView {
    static let lineHeight: CGFloat = 16
    static let maxLines = 2
    private static let font = NSFont.systemFont(ofSize: 12, weight: .medium)

    /// On one line, for sizing the HUD.
    static func width(of title: String) -> CGFloat {
        ceil((title as NSString).size(withAttributes: [.font: font]).width)
    }

    private var title = ""
    private var isMinimized = false

    override var isFlipped: Bool { true }

    func configure(title: String, isMinimized: Bool) {
        guard title != self.title || isMinimized != self.isMinimized else { return }
        self.title = title
        self.isMinimized = isMinimized
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.minimumLineHeight = Self.lineHeight
        paragraph.maximumLineHeight = Self.lineHeight
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph,
            // A fixed line height puts all the extra space above the text; split it, as CSS does.
            .baselineOffset: (Self.lineHeight - (Self.font.ascender - Self.font.descender)) / 2,
        ]
        let height = min(bounds.height, Self.lineHeight * CGFloat(Self.maxLines))
        NSGraphicsContext.saveGraphicsState()
        if isMinimized {
            NSGraphicsContext.current?.cgContext.setAlpha(0.6)
        }
        (title as NSString).draw(with: NSRect(x: 0, y: 0, width: bounds.width, height: height),
                                 options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                 attributes: attributes, context: nil)
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// "+N more" after the tiles, for windows past the ninth. Can't be picked.
final class WindowSwitcherOverflowView: NSView {
    static let width: CGFloat = 76
    private static let font = NSFont.systemFont(ofSize: 12)

    var text = "" {
        didSet {
            guard text != oldValue else { return }
            setAccessibilityLabel(text)
            needsDisplay = true
        }
    }

    init() {
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: NSColor.secondaryLabelColor]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
                                withAttributes: attributes)
    }
}

private extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

/// A window with a bar along its bottom: the minimized marker, drawn in the label colour, or white
/// when highlighted.
final class MinimizedGlyphView: NSView {
    var isHighlighted = false {
        didSet { if isHighlighted != oldValue { needsDisplay = true } }
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 13, height: 10))
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Minimized")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let stroke: CGFloat = 1.3
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(0.7)
        (isHighlighted ? NSColor.white : .labelColor).set()

        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: stroke / 2, dy: stroke / 2), xRadius: 2.5, yRadius: 2.5)
        outline.lineWidth = stroke
        outline.stroke()
        NSBezierPath(rect: NSRect(x: 2, y: bounds.height - 1.5 - stroke, width: bounds.width - 4, height: stroke)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
