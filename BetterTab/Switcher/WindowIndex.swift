import ApplicationServices

/// One standard window of an app.
struct AppWindow: @unchecked Sendable {
    /// AX elements are safe to use from any thread.
    let element: AXUIElement
    let title: String
    let isMinimized: Bool
}

/// Reads apps' standard windows through AX, off the main actor. Results arrive on the main actor.
final class WindowIndex {
    /// Reads each app's standard windows in parallel, front to back, with a 250 ms AX timeout
    /// per call; a hung app just gets no result. `onResult` fires once per app as it finishes.
    func load(pids: [pid_t], onResult: @escaping (pid_t, [AppWindow]) -> Void) {}

    /// While the list is open: calls `onChange` with the app's fresh windows whenever one is
    /// created, closed, minimized or restored. Replaces any earlier watch.
    func watch(pid: pid_t, onChange: @escaping ([AppWindow]) -> Void) {}

    /// Drops pending results and any watch. Idempotent.
    func cancel() {}
}
