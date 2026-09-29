import ApplicationServices
import os

/// The private and Swift-unavailable functions the focuser needs.
///
/// `_AXUIElementGetWindow` is linked directly: HIServices exports it in the SDK stub, and every
/// window tool relies on it. The rest are looked up at runtime so a future macOS that drops one
/// makes focusing fall back instead of stopping BetterTab from launching. The target doesn't
/// link SkyLight, so its symbols have to be looked up anyway.
nonisolated enum FocusSymbols {
    /// `kCPSUserGenerated` (yabai's value): marks the switch as the user's own doing.
    static let userGenerated: UInt32 = 0x200

    typealias GetProcessForPID = @convention(c) (
        pid_t, UnsafeMutablePointer<ProcessSerialNumber>
    ) -> OSStatus
    typealias SetFrontProcessWithOptions = @convention(c) (
        UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32
    ) -> CGError
    typealias PostEventRecordTo = @convention(c) (
        UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>
    ) -> CGError

    private static let skyLight = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
    private static let hiServices =
        "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/Versions/A/HIServices"

    /// Deprecated since macOS 10.9, so Swift marks it unavailable, but HIServices still exports
    /// it and nothing public maps a pid to the PSN that SkyLight wants.
    static let getProcessForPID = resolve("GetProcessForPID", in: hiServices, as: GetProcessForPID.self)
    static let setFrontProcessWithOptions = resolve(
        "_SLPSSetFrontProcessWithOptions", in: skyLight, as: SetFrontProcessWithOptions.self)
    static let postEventRecordTo = resolve("SLPSPostEventRecordTo", in: skyLight, as: PostEventRecordTo.self)

    /// The window server's id for an AX window, or nil if the app doesn't answer.
    static func windowID(of window: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        let error = axUIElementGetWindow(window, &id)
        return error == .success && id != 0 ? id : nil
    }

    private static func resolve<Function>(_ name: String, in path: String, as _: Function.Type) -> Function? {
        // Both images are already loaded by AppKit, so this only returns a handle to them.
        guard let handle = dlopen(path, RTLD_LAZY), let address = dlsym(handle, name) else {
            Logger(subsystem: "com.luksanss.BetterTab", category: "focus")
                .error("private symbol \(name, privacy: .public) is missing")
            return nil
        }
        return unsafeBitCast(address, to: Function.self)
    }
}

@_silgen_name("_AXUIElementGetWindow")
private nonisolated func axUIElementGetWindow(
    _ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>
) -> AXError
