import ApplicationServices
import CoreGraphics
import os

/// Answers the spec's open question: is Input Monitoring needed besides Accessibility?
nonisolated enum Permissions {
    nonisolated struct Status: Sendable {
        let accessibility: Bool
        let listen: Bool
        let post: Bool
    }

    static func current() -> Status {
        Status(
            accessibility: AXIsProcessTrusted(),
            listen: CGPreflightListenEventAccess(),
            post: CGPreflightPostEventAccess())
    }

    @discardableResult
    static func log(_ context: String) -> Status {
        let s = current()
        Log.perm.notice("""
            PERM \(context, privacy: .public): AXIsProcessTrusted=\(s.accessibility, privacy: .public) \
            CGPreflightListenEventAccess=\(s.listen, privacy: .public) \
            CGPreflightPostEventAccess=\(s.post, privacy: .public)
            """)
        return s
    }

    /// Only from the menu; the harness never prompts on its own.
    static func request() {
        // The string value of kAXTrustedCheckOptionPrompt; the global itself isn't concurrency-safe.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        let listen = CGRequestListenEventAccess()
        Log.perm.notice("""
            PERM requested: AXIsProcessTrustedWithOptions(prompt)=\(trusted, privacy: .public) \
            CGRequestListenEventAccess=\(listen, privacy: .public)
            """)
    }
}
