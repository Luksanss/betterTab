import AppKit
import ApplicationServices
import os

/// Tracks the Accessibility grant and reports it to `AppStatus`. It polls only while the grant is
/// missing; once granted, it waits for the system's trust-changed notification instead.
final class AccessibilityPermission: NSObject {
    /// Spec constant: permission re-check while missing.
    static let recheckInterval: TimeInterval = 2

    private var timer: Timer?
    private var pendingCheck: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.luksanss.BetterTab", category: "permissions")

    func start() {
        // Posted when any app's Accessibility trust changes, including ours. Deliver it even while
        // BetterTab is inactive, which as a menu-bar app it almost always is.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(trustMayHaveChanged),
            name: Notification.Name("com.apple.accessibility.api"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        check()
        logger.info("Accessibility trusted at launch: \(AppStatus.shared.isTrusted, privacy: .public)")
        promptOnFirstLaunch()
    }

    /// Opens Privacy & Security → Accessibility, without the system prompt: that only put a second
    /// dialog in front of the same switch.
    func requestAccess() {
        logger.info("Opening Accessibility settings")
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// A menu-bar item alone is easy to miss (the notch can hide it), so the very first launch
    /// without the permission shows the system prompt once. After that, the menu offers it.
    private func promptOnFirstLaunch() {
        let key = "promptedForAccessibility"
        guard !AppStatus.shared.isTrusted, !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        logger.info("First launch without Accessibility: showing the system prompt")
        showSystemPrompt()
    }

    private func showSystemPrompt() {
        // The string key avoids the global kAXTrustedCheckOptionPrompt, which Swift 6 rejects as
        // not concurrency-safe.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    private func check() {
        let trusted = AXIsProcessTrusted()
        if trusted {
            timer?.invalidate()
            timer = nil
        } else if timer == nil {
            let timer = Timer(
                timeInterval: Self.recheckInterval, target: self, selector: #selector(timerFired),
                userInfo: nil, repeats: true
            )
            timer.tolerance = 0.5
            // Common modes, so a grant is still noticed while the menu is open.
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        AppStatus.shared.setTrusted(trusted)
    }

    @objc private func timerFired() {
        check()
    }

    @objc private func trustMayHaveChanged() {
        // AXIsProcessTrusted() lags the notification, so look again shortly after, and once more
        // in case the first look was still too early.
        pendingCheck?.cancel()
        pendingCheck = Task {
            for delay in [0.5, 2.0] {
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { return }
                check()
            }
        }
    }
}
