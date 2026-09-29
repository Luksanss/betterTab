import AppKit

extension NSWindow.Level {
    /// Above the native ⌘⇥ switcher, for both the stack edges and the list. Unverified: the
    /// switcher's real window layer hasn't been logged yet (docs/architecture.md § The experiment,
    /// test 1).
    /// WindowLens draws over the native switcher at `.screenSaver`, so start there.
    static let aboveSwitcher = NSWindow.Level.screenSaver
}

/// A borderless panel that never takes focus from the front app. Shared by the stack edges and the
/// list.
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
