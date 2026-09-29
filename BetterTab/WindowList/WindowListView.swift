import AppKit

/// The list itself: frosted background, one row per window, and the "+N more" footer. Sizes come
/// from design v5, in points.
final class WindowListView: NSView {
    static let width: CGFloat = 320
    static let padding: CGFloat = 6
    static let cornerRadius: CGFloat = 18
    static let rowHeight: CGFloat = 32
    static let rowSpacing: CGFloat = 1
    static let footerHeight = OverflowFooterView.height

    /// A row under the pointer, by row number.
    var onHover: ((Int) -> Void)?
    /// A click that went down and up on the same row, by row number.
    var onClick: ((Int) -> Void)?

    private let background = WindowListView.makeBackground()
    private var rowViews: [WindowListRowView] = []
    private let footer = OverflowFooterView()
    private var pressedRow: Int?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 0))
        wantsLayer = true
        background.autoresizingMask = [.width, .height]
        addSubview(background)
        addSubview(footer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    static func size(for model: WindowListModel) -> NSSize {
        let rows = CGFloat(model.rows.count)
        var height = padding * 2 + rows * rowHeight + max(rows - 1, 0) * rowSpacing
        if model.overflowCount > 0 { height += footerHeight }
        return NSSize(width: width, height: height)
    }

    /// Resizes to fit the model and lays out the rows. Cheap enough to call on every highlight move.
    func render(_ model: WindowListModel, labels: [String]) {
        setFrameSize(Self.size(for: model))
        background.frame = bounds

        while rowViews.count < model.rows.count {
            let row = WindowListRowView()
            addSubview(row)
            rowViews.append(row)
        }
        while rowViews.count > model.rows.count {
            rowViews.removeLast().removeFromSuperview()
        }

        // Laid out from the top; this view isn't flipped, so the open animation's maths stays y-up.
        let contentWidth = bounds.width - Self.padding * 2
        var top = bounds.height - Self.padding
        for (index, (row, data)) in zip(rowViews, model.rows).enumerated() {
            row.frame = NSRect(x: Self.padding, y: top - Self.rowHeight, width: contentWidth, height: Self.rowHeight)
            top -= Self.rowHeight + Self.rowSpacing
            row.configure(letter: index < labels.count ? labels[index] : "",
                          title: data.title, isMinimized: data.isMinimized,
                          isHighlighted: index == model.highlight)
        }

        footer.isHidden = model.overflowCount == 0
        footer.frame = NSRect(x: Self.padding, y: Self.padding, width: contentWidth, height: Self.footerHeight)
        footer.text = "+\(model.overflowCount) more"
    }

    // MARK: Mouse. Only reached when the panel accepts mouse events.

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // .activeAlways: BetterTab is never the active app while the list is up.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hover(event) }
    override func mouseMoved(with event: NSEvent) { hover(event) }

    override func mouseDown(with event: NSEvent) {
        pressedRow = row(at: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressedRow = nil }
        guard let row = row(at: event), row == pressedRow else { return }
        onClick?(row)
    }

    private func hover(_ event: NSEvent) {
        if let row = row(at: event) { onHover?(row) }
    }

    private func row(at event: NSEvent) -> Int? {
        let point = convert(event.locationInWindow, from: nil)
        return rowViews.firstIndex { $0.frame.contains(point) }
    }

    // MARK: Background

    /// A system material, so it follows light and dark mode and Reduce Transparency. `.menu`
    /// because the list is a menu-like set of choices with an accent-coloured highlight; it's the
    /// closest system material to v5's frosted panel.
    private static func makeBackground() -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
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

/// One window: letter badge, title, and the minimized marker.
final class WindowListRowView: NSView {
    private static let horizontalPadding: CGFloat = 8
    private static let badgeSize: CGFloat = 20
    private static let badgeRadius: CGFloat = 5
    private static let gap: CGFloat = 10
    private static let cornerRadius: CGFloat = 10
    private static let badgeFont = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
    private static let titleFont = NSFont.systemFont(ofSize: 13, weight: .regular)
    private static let highlightedTitleFont = NSFont.systemFont(ofSize: 13, weight: .medium)

    private var letter = ""
    private var title = ""
    private var isMinimized = false
    private var isHighlighted = false
    private let glyph = MinimizedGlyphView()

    init() {
        super.init(frame: .zero)
        glyph.isHidden = true
        addSubview(glyph)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        glyph.setFrameOrigin(NSPoint(x: bounds.width - Self.horizontalPadding - glyph.frame.width,
                                     y: ((bounds.height - glyph.frame.height) / 2).rounded()))
    }

    func configure(letter: String, title: String, isMinimized: Bool, isHighlighted: Bool) {
        guard letter != self.letter || title != self.title
            || isMinimized != self.isMinimized || isHighlighted != self.isHighlighted else { return }
        self.letter = letter
        self.title = title
        self.isMinimized = isMinimized
        self.isHighlighted = isHighlighted
        glyph.isHidden = !isMinimized
        glyph.isHighlighted = isHighlighted
        setAccessibilityLabel("\(letter): \(title)")
        setAccessibilitySelected(isHighlighted)
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let isDark = effectiveAppearance.isDark
        if isHighlighted {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius).fill()
        }
        let textColor: NSColor = isHighlighted ? .white : .labelColor

        let badge = NSRect(x: Self.horizontalPadding, y: (bounds.height - Self.badgeSize) / 2,
                           width: Self.badgeSize, height: Self.badgeSize)
        let badgeFill = isHighlighted ? NSColor(white: 1, alpha: 0.22)
            : isDark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: 0.07)
        badgeFill.setFill()
        NSBezierPath(roundedRect: badge, xRadius: Self.badgeRadius, yRadius: Self.badgeRadius).fill()

        let letterAttributes: [NSAttributedString.Key: Any] = [.font: Self.badgeFont, .foregroundColor: textColor]
        let letterSize = (letter as NSString).size(withAttributes: letterAttributes)
        (letter as NSString).draw(at: NSPoint(x: badge.midX - letterSize.width / 2, y: badge.midY - letterSize.height / 2),
                                  withAttributes: letterAttributes)

        let font = isHighlighted ? Self.highlightedTitleFont : Self.titleFont
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: textColor, .paragraphStyle: paragraph,
        ]
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let titleX = badge.maxX + Self.gap
        let titleMaxX = bounds.width - Self.horizontalPadding - (isMinimized ? glyph.frame.width + Self.gap : 0)
        let titleRect = NSRect(x: titleX, y: (bounds.height - lineHeight) / 2, width: max(titleMaxX - titleX, 0), height: lineHeight)

        NSGraphicsContext.saveGraphicsState()
        if isMinimized {
            NSGraphicsContext.current?.cgContext.setAlpha(isHighlighted ? 0.75 : 0.5)
        }
        (title as NSString).draw(with: titleRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                 attributes: titleAttributes, context: nil)
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// A window with a bar along its bottom: the minimized marker, drawn in the row's text colour.
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

/// A separator, then "+N more" aligned with the titles. Can't be picked.
final class OverflowFooterView: NSView {
    static let separatorMargin: CGFloat = 4
    static let lineHeight: CGFloat = 26
    static let height = separatorMargin * 2 + 1 + lineHeight
    private static let separatorInset: CGFloat = 8
    private static let leading: CGFloat = 38
    private static let font = NSFont.systemFont(ofSize: 12)

    var text = "" {
        didSet { if text != oldValue { needsDisplay = true } }
    }

    override var isFlipped: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSBezierPath(rect: NSRect(x: Self.separatorInset, y: Self.separatorMargin,
                                  width: bounds.width - Self.separatorInset * 2, height: 1)).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph,
        ]
        let textHeight = ceil(Self.font.ascender - Self.font.descender + Self.font.leading)
        let lineTop = Self.separatorMargin * 2 + 1
        let rect = NSRect(x: Self.leading, y: lineTop + (Self.lineHeight - textHeight) / 2,
                          width: bounds.width - Self.leading - Self.separatorInset, height: textHeight)
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                attributes: attributes, context: nil)
    }
}

private extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}
