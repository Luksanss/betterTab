import CoreGraphics

/// Where the list goes. All rects are AppKit global screen coordinates (bottom-left origin).
struct WindowListPlacement: Equatable {
    static let gapAboveSwitcher: CGFloat = 10

    /// The list's frame.
    let frame: CGRect
    /// The highlighted icon's centre, as an x offset within `frame`. The open animation grows
    /// from this point on the list's bottom edge.
    let originX: CGFloat

    /// Centred on the icon, 10 pt above the switcher, kept within the switcher's width and then
    /// inside the screen's visible frame.
    init(listSize: CGSize, switcherFrame: CGRect, iconFrame: CGRect, visibleFrame: CGRect) {
        var x = iconFrame.midX - listSize.width / 2
        x = Self.clamp(x, switcherFrame.minX, switcherFrame.maxX - listSize.width)
        x = Self.clamp(x, visibleFrame.minX, visibleFrame.maxX - listSize.width)

        var y = switcherFrame.maxY + Self.gapAboveSwitcher
        y = Self.clamp(y, visibleFrame.minY, visibleFrame.maxY - listSize.height)

        frame = CGRect(origin: CGPoint(x: x.rounded(), y: y.rounded()), size: listSize)
        originX = min(max(iconFrame.midX - frame.minX, 0), listSize.width)
    }

    /// When the range is empty (the list is wider than it), centre in it instead.
    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        low > high ? (low + high) / 2 : min(max(value, low), high)
    }
}
