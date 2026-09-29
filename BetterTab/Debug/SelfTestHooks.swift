#if DEBUG
import CoreGraphics

/// What the controller publishes for the self-test to check against. Debug builds only; main
/// actor. The controller writes, the self-test reads; nothing else uses it.
enum SelfTestHooks {
    /// "idle", "cycling" or "picking", as `SwitchController` sees it.
    static var phase = "idle"
    /// The app whose list is showing, or 0.
    static var listedPid: pid_t = 0
    /// The listed windows in row order (row A first), empty when no list shows.
    static var listedWindowIDs: [CGWindowID] = []
    /// Every focus the controller hands to `Focuser`, oldest first.
    static var focusRequests: [(pid: pid_t, windowID: CGWindowID)] = []
}
#endif
