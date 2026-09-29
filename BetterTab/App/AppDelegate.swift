import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let permission = AccessibilityPermission()
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = StatusItemController(permission: permission)
        self.statusItem = statusItem
        AppStatus.shared.onChange = { statusItem.update() }
        permission.start()
    }
}
