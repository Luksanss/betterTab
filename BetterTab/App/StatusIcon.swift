import AppKit

/// The menu-bar icon: the app icon's keycap labelled A (`design/icon/make-icon.swift`), drawn
/// small. A template image, so macOS tints it: the key's face is solid with the A cut out of it,
/// and the key's front shows below the face at partial opacity, as the app icon's base does.
enum StatusIcon {
    static let image: NSImage = {
        let image = NSImage(size: cap.size, flipped: true, drawingHandler: draw)
        image.isTemplate = true
        image.accessibilityDescription = "BetterTab"
        return image
    }()

    // Top-left origin, in points: the app icon's proportions, rounded to half points so the edges
    // stay sharp at 2×. The face is inset 1 pt at the sides and 0.5 pt at the top, which leaves
    // 2.5 pt of the key's front showing below it.
    private nonisolated static let cap = NSRect(x: 0, y: 0, width: 15, height: 16)
    private nonisolated static let face = NSRect(x: 1, y: 0.5, width: 13, height: 13)
    private nonisolated static let capOpacity: CGFloat = 0.45

    private nonisolated static func draw(_ bounds: NSRect) -> Bool {
        guard let context = NSGraphicsContext.current else { return false }
        // Draw in a layer of its own, so the knockout clears only the key and not whatever is
        // already under the image.
        context.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
        defer { context.cgContext.endTransparencyLayer() }

        NSColor.black.withAlphaComponent(capOpacity).setFill()
        NSBezierPath(roundedRect: cap, xRadius: 3.5, yRadius: 3.5).fill()

        // Copy, so the face replaces the base under it instead of adding to its opacity.
        context.compositingOperation = .copy
        NSColor.black.setFill()
        NSBezierPath(roundedRect: face, xRadius: 2.5, yRadius: 2.5).fill()

        context.compositingOperation = .clear
        letterA().stroke()
        return true
    }

    /// `make-icon.swift`'s A: two legs meeting at the top and a crossbar 64% of the way down, all
    /// with round ends. Its size and line width keep their ratio to the face, to the half point.
    private nonisolated static func letterA() -> NSBezierPath {
        let height: CGFloat = 7.5, width: CGFloat = 7
        let top = face.midY - height / 2, bottom = face.midY + height / 2
        let barY = top + height * 0.64, half = width / 2 * 0.64
        let path = NSBezierPath()
        path.move(to: NSPoint(x: face.midX - width / 2, y: bottom))
        path.line(to: NSPoint(x: face.midX, y: top))
        path.line(to: NSPoint(x: face.midX + width / 2, y: bottom))
        path.move(to: NSPoint(x: face.midX - half, y: barY))
        path.line(to: NSPoint(x: face.midX + half, y: barY))
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        return path
    }
}
