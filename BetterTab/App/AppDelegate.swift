import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let permission = AccessibilityPermission()
    private let controller = SwitchController()
    private var statusItem: StatusItemController?
    private var signalSources: [any DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        signalSources = TapSignals.install(tap: controller.tap)
        let statusItem = StatusItemController(permission: permission)
        self.statusItem = statusItem
        let controller = controller
        AppStatus.shared.onChange = {
            statusItem.update()
            controller.statusChanged()
        }
        permission.start()
        controller.statusChanged()
    }

    /// Quit from the menu comes through here too. The tap goes off, then any owed ⌘ release is
    /// posted.
    func applicationWillTerminate(_ notification: Notification) {
        controller.tap.stop()
    }
}
