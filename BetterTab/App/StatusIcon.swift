import AppKit

/// The menu-bar icon: a window in front of another. A template image, so macOS tints it.
enum StatusIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 14), flipped: true, drawingHandler: draw)
        image.isTemplate = true
        image.accessibilityDescription = "BetterTab"
        return image
    }()

    // Top-left origin, in points, as in the v5 design.
    private nonisolated static func draw(_ bounds: NSRect) -> Bool {
        guard let context = NSGraphicsContext.current else { return false }
        let back = NSRect(x: 6, y: 0, width: 12, height: 9)
        let front = NSRect(x: 0, y: 4, width: 13, height: 10)
        let radius: CGFloat = 2.5
        let line: CGFloat = 1.5

        // Draw in a layer of its own, so the knockout clears only the back window and not whatever
        // is already under the image.
        context.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
        defer { context.cgContext.endTransparencyLayer() }
        NSColor.black.set()

        // Stroke inside the rect, so the outline's outer edge matches the design's frame.
        let inset = line / 2
        let outline = NSBezierPath(
            roundedRect: back.insetBy(dx: inset, dy: inset), xRadius: radius - inset, yRadius: radius - inset
        )
        outline.lineWidth = line
        outline.stroke()

        context.compositingOperation = .clear
        NSBezierPath(
            roundedRect: front.insetBy(dx: -line, dy: -line), xRadius: radius + line, yRadius: radius + line
        ).fill()

        context.compositingOperation = .sourceOver
        NSBezierPath(roundedRect: front, xRadius: radius, yRadius: radius).fill()
        return true
    }
}
