import Sparkle

/// Check for Updates… (docs/spec.md § Updates). Sparkle starts the first time it's chosen, and
/// never checks by itself: Info.plist turns its automatic checks off.
final class Updater {
    private var controller: SPUStandardUpdaterController?

    /// Shows Sparkle's window: up to date, a newer version to install, or what went wrong.
    func checkForUpdates() {
        let controller = controller ?? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        controller.checkForUpdates(nil)
    }
}
