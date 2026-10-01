import AppKit

/// The ⌘§ switcher's panel, centred on the display like the native ⌘⇥ switcher. The controller
/// owns the model and feeds it keys; this draws it and reports the pointer.
final class WindowSwitcher {
    /// Kept free on each side of the visible frame when the HUD has to shrink to fit.
    private static let screenMargin: CGFloat = 20
    /// How far the pointer has to travel from where it was at `show` before it moves the
    /// highlight. The HUD opens in the middle of the display, often right under a resting pointer,
    /// and that pointer mustn't pick the window ⌘'s release opens.
    private static let pointerSlop: CGFloat = 3

    /// The pointer is over a tile, by tile number (a position in `model.tiles`).
    var onHover: ((Int) -> Void)?
    /// A click went down and up on the same tile, by tile number.
    var onClick: ((Int) -> Void)?

    var isVisible: Bool { panel.isVisible }

    private let panel = OverlayPanel()
    private let switcherView = WindowSwitcherView()
    private var model = WindowSwitcherModel()
    private var labels = KeyLabels.qwerty
    /// The display it opened on, AppKit global coordinates.
    private var screenFrames: (frame: CGRect, visibleFrame: CGRect)?
    /// Where the pointer was at `show`, until it has moved away. AppKit global coordinates.
    private var restingPointer: NSPoint?

    init() {
        // Unlike the stack edges, it isn't over the native switcher, which any click would close.
        panel.ignoresMouseEvents = false
        panel.hasShadow = true
        panel.contentView = NSView()
        panel.contentView?.addSubview(switcherView)
        switcherView.onHover = { [weak self] tile in self?.hover(tile) }
        switcherView.onClick = { [weak self] tile in self?.onClick?(tile) }
        #if DEBUG
        Self.debugInstances.append(SelfTestWeak(object: self))
        #endif
    }

    /// Opens at once, centred on the whole display: the design has no opening animation.
    func show(_ model: WindowSwitcherModel, on screen: NSScreen) {
        labels = KeyLabels.current()
        screenFrames = (screen.frame, screen.visibleFrame)
        restingPointer = NSEvent.mouseLocation
        layout(model)
        panel.orderFrontRegardless()
    }

    /// Redraws for a new highlight or new windows, keeping the labels and the display.
    func update(_ model: WindowSwitcherModel) {
        layout(model)
    }

    /// Also drops the titles and frames the view holds (docs/spec.md § Privacy).
    func hide() {
        panel.orderOut(nil)
        layout(WindowSwitcherModel())
    }

    /// Clicks always count; hovering counts once the pointer has really moved.
    private func hover(_ tile: Int) {
        if let resting = restingPointer {
            let now = NSEvent.mouseLocation
            guard hypot(now.x - resting.x, now.y - resting.y) > Self.pointerSlop else { return }
            restingPointer = nil
        }
        onHover?(tile)
    }

    private func layout(_ model: WindowSwitcherModel) {
        self.model = model
        guard let screenFrames else { return }
        // Nine tiles and "+N more" are 1224 pt wide, which a small display can't fit.
        let natural = WindowSwitcherView.size(for: model)
        let available = screenFrames.visibleFrame.width - Self.screenMargin * 2
        let scale = natural.width > available ? available / natural.width : 1
        switcherView.render(model, labels: labels, scale: scale)

        let size = switcherView.frame.size
        let frame = NSRect(x: (screenFrames.frame.midX - size.width / 2).rounded(),
                           y: (screenFrames.frame.midY - size.height / 2).rounded(),
                           width: size.width, height: size.height)
        if panel.frame != frame {
            panel.setFrame(frame, display: false)
            switcherView.setFrameOrigin(.zero)
        }
        panel.invalidateShadow()
    }
}

#if DEBUG
/// What the self-test reads. Read-only; changes nothing.
extension WindowSwitcher {
    struct DebugState {
        let isVisible: Bool
        /// The panel, AppKit global.
        let frame: CGRect
        let tileCount: Int
        /// The badges shown, tile A first.
        let labels: [String]
        let highlight: Int
        let overflowCount: Int
    }

    fileprivate static var debugInstances: [SelfTestWeak<WindowSwitcher>] = []

    /// Every live switcher, oldest first.
    static var debugStates: [DebugState] {
        debugInstances.removeAll { $0.object == nil }
        return debugInstances.compactMap { $0.object?.debugState }
    }

    var debugState: DebugState {
        DebugState(
            isVisible: panel.isVisible,
            frame: panel.frame,
            tileCount: model.tiles.count,
            labels: Array(labels.prefix(model.tiles.count)),
            highlight: model.highlight,
            overflowCount: model.overflowCount)
    }
}
#endif
