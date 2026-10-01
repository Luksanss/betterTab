#if DEBUG
import CoreGraphics

/// What the controller publishes for the self-test to check against. Debug builds only; main
/// actor. The controller writes, the self-test reads; nothing else uses it.
enum SelfTestHooks {
    /// "idle" or "cycling", as `SwitchController` sees it, or "windows" during ⌘§.
    static var phase = "idle"
    /// Every focus the controller hands to `Focuser`, oldest first.
    static var focusRequests: [(pid: pid_t, windowID: CGWindowID)] = []
    /// The running ⌘§ session's tiles in order (the window you're in first), empty when none runs.
    static var switcherWindowIDs: [CGWindowID] = []
    /// The running ⌘§ session's highlighted tile, or -1.
    static var switcherHighlight = -1
    /// Whether the ⌘§ switcher is on screen.
    static var switcherVisible = false
    /// ⌘§ sessions as they end, oldest first: their tiles, the highlight at the end, and whether
    /// the switcher was ever on screen.
    static var windowSessions: [(windowIDs: [CGWindowID], highlight: Int, shown: Bool)] = []
}
#endif
