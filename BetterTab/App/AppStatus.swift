import os

/// The state the menu-bar item shows. `AccessibilityPermission` reports the grant into it, and the
/// switcher lookup reports each attempt.
final class AppStatus {
    enum State {
        case active, needsPermission, switcherNotFound
    }

    static let shared = AppStatus()

    /// Spec: "Can't find the ⌘⇥ switcher" appears after this many failed lookups in a row.
    static let failedLookupsBeforeNotFound = 3

    /// Whether macOS trusts BetterTab for Accessibility.
    private(set) var isTrusted = false
    private var failedLookups = 0

    var state: State {
        if !isTrusted { return .needsPermission }
        return failedLookups >= Self.failedLookupsBeforeNotFound ? .switcherNotFound : .active
    }

    /// Called on the main actor after `state` changes.
    var onChange: (() -> Void)?

    private let logger = Logger(subsystem: "com.luksanss.BetterTab", category: "status")

    private init() {}

    func setTrusted(_ trusted: Bool) {
        guard trusted != isTrusted else { return }
        let before = state
        isTrusted = trusted
        // Lookups can't succeed without the permission, so those failures say nothing about the Dock.
        if !trusted { failedLookups = 0 }
        logger.info("Accessibility trusted: \(trusted, privacy: .public)")
        changed(from: before)
    }

    /// Report one attempt to find the native ⌘⇥ switcher.
    func switcherLookup(succeeded: Bool) {
        let before = state
        failedLookups = succeeded ? 0 : failedLookups + 1
        changed(from: before)
    }

    private func changed(from before: State) {
        guard state != before else { return }
        logger.info("State: \(String(describing: self.state), privacy: .public)")
        onChange?()
    }
}
