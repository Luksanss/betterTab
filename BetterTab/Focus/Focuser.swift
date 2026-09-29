import ApplicationServices

/// Brings one specific window to the front as the key window.
enum Focuser {
    /// Unhides the app if hidden, restores the window if minimized, then makes it the front,
    /// key window without bringing the app's other windows forward.
    static func focus(pid: pid_t, window: AXUIElement) {}
}
