import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let permission = AccessibilityPermission()
    private let controller = SwitchController()
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = StatusItemController(permission: permission)
        self.statusItem = statusItem
        let controller = controller
        AppStatus.shared.onChange = {
            statusItem.update()
            controller.statusChanged()
        }
        permission.start()
        controller.statusChanged()
        #if DEBUG
        statusItem.runSelfTest = { SelfTest.start(.fromMenu) }
        if let options = SelfTestOptions(arguments: CommandLine.arguments) {
            SelfTest.start(options)
        }
        #endif
    }

    /// Quit from the menu comes through here too. The tap goes off, and so does any ⌘§ switcher.
    func applicationWillTerminate(_ notification: Notification) {
        controller.tap.stop()
    }
}
