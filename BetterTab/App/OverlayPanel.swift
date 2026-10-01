import AppKit

extension NSWindow.Level {
    /// Above the native ⌘⇥ switcher, whose window is at layer 20 (measured 2026-09-29), for the
    /// stack edges. WindowLens draws over the native switcher at `.screenSaver` too.
    static let aboveSwitcher = NSWindow.Level.screenSaver
}

/// A borderless panel that never takes focus from the front app. Shared by the stack edges and the
/// ⌘§ switcher.
final class OverlayPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .aboveSwitcher
        // Shown on whichever Space is active, over full-screen apps too, like the native switcher.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        // BetterTab is never the active app, so the panel mustn't hide when it isn't.
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
