import AppKit
import QuartzCore

/// The window list above the highlighted icon of the native switcher. A controller shows it on
/// release, feeds it key codes from the event tap, and hides it together with the switcher.
final class WindowList {
    /// Off until the experiment shows that clicking our panel doesn't end the held-open native
    /// switcher (docs/architecture.md § The experiment, test 0b). Off means clicks pass through.
    static let acceptsMouseByDefault = false

    /// A row was clicked. The value indexes the `windows` array, like `WindowListAction.pick`.
    var onPick: ((Int) -> Void)?

    private(set) var model = WindowListModel(windows: [])
    private(set) var labels = KeyLabels.qwerty
    var isVisible: Bool { panel.isVisible }

    // The panel reaches this far below the list, so the list can rise into place without being
    // clipped by the window's edge. It sits in the gap above the switcher and is transparent.
    private static let riseDistance: CGFloat = 8
    private static let fadeDuration: CFTimeInterval = 0.11
    private static let moveDuration: CFTimeInterval = 0.15
    private static let startScale: CGFloat = 0.96

    private let panel = OverlayPanel()
    private let listView = WindowListView()
    private var anchor: (switcherFrame: CGRect, iconFrame: CGRect, visibleFrame: CGRect)?

    init(acceptsMouse: Bool = WindowList.acceptsMouseByDefault) {
        panel.ignoresMouseEvents = !acceptsMouse
        panel.hasShadow = true
        panel.contentView = NSView()
        panel.contentView?.addSubview(listView)
        listView.onHover = { [weak self] row in self?.hover(row) }
        listView.onClick = { [weak self] row in self?.click(row) }
        #if DEBUG
        Self.debugInstances.append(SelfTestWeak(object: self))
        #endif
    }

    /// Opens the list with row A highlighted. Frames are AppKit global coordinates.
    func show(windows: [WindowListItem], switcherFrame: CGRect, iconFrame: CGRect, screen: NSScreen) {
        model = WindowListModel(windows: windows)
        labels = KeyLabels.current()
        anchor = (switcherFrame, iconFrame, screen.visibleFrame)
        guard let placement = layout() else { return }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        animateIn(originX: placement.originX)
    }

    /// Refreshes the rows, for when the app loses windows while the list is open.
    func update(windows: [WindowListItem]) {
        model.setWindows(windows)
        layout()
    }

    /// Letters and Return pick, Esc cancels, arrows move the highlight (already applied when this
    /// returns). Any other key gives nil. Hiding is left to the caller, which closes the list and
    /// the switcher together.
    func handle(keyCode: UInt16) -> WindowListAction? {
        let action = model.handle(keyCode: keyCode)
        if case .moveHighlight = action {
            listView.render(model, labels: labels)
        }
        return action
    }

    /// Closes at once: the native switcher vanishes instantly, and they close together. Also drops
    /// the titles the model and the rows hold (docs/spec.md § Privacy).
    func hide() {
        listView.layer?.removeAllAnimations()
        panel.orderOut(nil)
        model = WindowListModel(windows: [])
        listView.render(model, labels: labels)
    }

    @discardableResult
    private func layout() -> WindowListPlacement? {
        listView.render(model, labels: labels)
        guard let anchor else { return nil }
        let placement = WindowListPlacement(listSize: listView.frame.size, switcherFrame: anchor.switcherFrame,
                                            iconFrame: anchor.iconFrame, visibleFrame: anchor.visibleFrame)
        var frame = placement.frame
        frame.origin.y -= Self.riseDistance
        frame.size.height += Self.riseDistance
        panel.setFrame(frame, display: false)
        listView.setFrameOrigin(NSPoint(x: 0, y: Self.riseDistance))
        panel.invalidateShadow()
        return placement
    }

    /// Fades in over 110 ms; rises 8 pt and grows from 96 % over 150 ms, from the icon's centre on
    /// the bottom edge. Under Reduce Motion it only fades.
    private func animateIn(originX: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let layer = listView.layer else { return }
        // A layer transform acts around the anchor point, so fold the pivot into the translation.
        // The view isn't flipped, so y points up and the start is 8 pt lower.
        let scale = Self.startScale
        let anchor = CGPoint(x: layer.anchorPoint.x * layer.bounds.width, y: layer.anchorPoint.y * layer.bounds.height)
        let pivot = CGPoint(x: originX, y: 0)
        var start = CATransform3DMakeTranslation((1 - scale) * (pivot.x - anchor.x),
                                                 (1 - scale) * (pivot.y - anchor.y) - Self.riseDistance, 0)
        start = CATransform3DScale(start, scale, scale, 1)

        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: start)
        animation.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        animation.duration = Self.moveDuration
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1.05)
        // The window shadow isn't recomputed per frame; take it from the settled shape.
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated { self?.panel.invalidateShadow() }
        }
        layer.add(animation, forKey: "open")
        CATransaction.commit()
    }

    private func hover(_ row: Int) {
        guard row != model.highlight else { return }
        model.setHighlight(row)
        listView.render(model, labels: labels)
    }

    private func click(_ row: Int) {
        guard model.rows.indices.contains(row) else { return }
        onPick?(model.rows[row].windowIndex)
    }
}

#if DEBUG
/// What the self-test reads. Read-only; changes nothing.
extension WindowList {
    struct DebugState {
        let isVisible: Bool
        let acceptsMouse: Bool
        /// The list itself, without the transparent margin it rises through. AppKit global.
        let frame: CGRect
        let rowCount: Int
        /// The badges shown, row A first.
        let labels: [String]
        let highlight: Int
        let overflowCount: Int
        let minimizedRows: Int
    }

    fileprivate static var debugInstances: [SelfTestWeak<WindowList>] = []

    /// Every live list, oldest first.
    static var debugStates: [DebugState] {
        debugInstances.removeAll { $0.object == nil }
        return debugInstances.compactMap { $0.object?.debugState }
    }

    var debugState: DebugState {
        let origin = panel.frame.origin
        return DebugState(
            isVisible: panel.isVisible,
            acceptsMouse: !panel.ignoresMouseEvents,
            frame: listView.frame.offsetBy(dx: origin.x, dy: origin.y),
            rowCount: model.rows.count,
            labels: Array(labels.prefix(model.rows.count)),
            highlight: model.highlight,
            overflowCount: model.overflowCount,
            minimizedRows: model.rows.filter(\.isMinimized).count)
    }
}
#endif
