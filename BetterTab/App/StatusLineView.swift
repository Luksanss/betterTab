import AppKit

/// The menu's status line: a coloured dot and the status text. It's a view because a disabled menu
/// item is drawn greyed out even with an explicit text colour, and macOS 27 doesn't draw menu item
/// images. A view in a menu doesn't highlight or take clicks.
final class StatusLineView: NSView {
    // Measured from native menu rows on macOS 27: rows are 24 pt tall, and titles start at 14 pt,
    // or at 28 pt once any item shows a checkmark. The dot sits at 14, so it lines up with plain
    // titles and falls into the checkmark column when there is one.
    private static let rowHeight: CGFloat = 24
    private static let dotX: CGFloat = 14
    private static let dotSize: CGFloat = 8
    private static let textX: CGFloat = 28
    private static let trailing: CGFloat = 14

    private let label = NSTextField(labelWithString: "")
    private var color = NSColor.clear

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: Self.rowHeight))
        autoresizingMask = .width
        label.font = .systemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize, weight: .medium)
        label.textColor = .labelColor
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(_ title: String, color: NSColor) {
        self.color = color
        label.stringValue = title
        label.sizeToFit()
        label.setFrameOrigin(NSPoint(x: Self.textX, y: ((Self.rowHeight - label.frame.height) / 2).rounded()))
        setFrameSize(NSSize(width: Self.textX + label.frame.width + Self.trailing, height: Self.rowHeight))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Set here rather than cached, so the dynamic system colour follows light and dark mode.
        color.setFill()
        let y = (bounds.height - Self.dotSize) / 2
        NSBezierPath(ovalIn: NSRect(x: Self.dotX, y: y, width: Self.dotSize, height: Self.dotSize)).fill()
    }
}
