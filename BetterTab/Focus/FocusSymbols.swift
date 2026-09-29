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
    typealias GetFrontProcess = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    typealias PostEventRecordTo = @convention(c) (
        UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>
    ) -> CGError
    typealias MainConnectionID = @convention(c) () -> Int32
    typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    typealias GetActiveSpace = @convention(c) (Int32) -> UInt64
    typealias SpaceSetFrontPSN = @convention(c) (Int32, UInt64, ProcessSerialNumber) -> CGError

    private static let skyLight = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
    private static let hiServices =
        "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/Versions/A/HIServices"

    /// Deprecated since macOS 10.9, so Swift marks it unavailable, but HIServices still exports
    /// it and nothing public maps a pid to the PSN that SkyLight wants.
    static let getProcessForPID = resolve("GetProcessForPID", in: hiServices, as: GetProcessForPID.self)
    static let setFrontProcessWithOptions = resolve(
        "_SLPSSetFrontProcessWithOptions", in: skyLight, as: SetFrontProcessWithOptions.self)
    static let getFrontProcess = resolve("_SLPSGetFrontProcess", in: skyLight, as: GetFrontProcess.self)
    static let postEventRecordTo = resolve("SLPSPostEventRecordTo", in: skyLight, as: PostEventRecordTo.self)
    private static let mainConnectionID = resolve("SLSMainConnectionID", in: skyLight, as: MainConnectionID.self)
    private static let copyManagedDisplaySpaces = resolve(
        "SLSCopyManagedDisplaySpaces", in: skyLight, as: CopyManagedDisplaySpaces.self)
    private static let copySpacesForWindows = resolve(
        "SLSCopySpacesForWindows", in: skyLight, as: CopySpacesForWindows.self)
    private static let getActiveSpace = resolve("SLSGetActiveSpace", in: skyLight, as: GetActiveSpace.self)
    private static let spaceSetFrontPSN = resolve("SLSSpaceSetFrontPSN", in: skyLight, as: SpaceSetFrontPSN.self)

    /// This process's own window-server connection, which AppKit opened at launch.
    private static let connection: Int32? = mainConnectionID.map { $0() }

    /// The window server's id for an AX window, or nil if the app doesn't answer.
    static func windowID(of window: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        let error = axUIElementGetWindow(window, &id)
        return error == .success && id != 0 ? id : nil
    }

    // MARK: - Spaces
    //
    // None of these need a permission. Verified on macOS 27 with neither Accessibility nor Screen
    // Recording.

    /// A display and its Spaces, in `SLSCopyManagedDisplaySpaces` order.
    struct Display {
        let identifier: String
        let currentSpace: UInt64
        let spaces: [UInt64]
    }

    /// Every display's Spaces, or nil if SkyLight doesn't answer. About 0.4 ms once warm.
    static func displays() -> [Display]? {
        guard let connection, let copyManagedDisplaySpaces,
              let raw = copyManagedDisplaySpaces(connection)?.takeRetainedValue() as? [[String: Any]]
        else { return nil }
        func spaceID(_ space: Any?) -> UInt64? {
            ((space as? [String: Any])?["ManagedSpaceID"] as? NSNumber)?.uint64Value
        }
        return raw.compactMap { display in
            guard let identifier = display["Display Identifier"] as? String,
                  let current = spaceID(display["Current Space"])
            else { return nil }
            let spaces = (display["Spaces"] as? [Any] ?? []).compactMap(spaceID)
            return Display(identifier: identifier, currentSpace: current, spaces: spaces)
        }
    }

    /// The Spaces a window is on: one for most windows, several for a window on all Spaces, and
    /// none when SkyLight doesn't know. Selector 0x7 is every kind of Space (yabai's value).
    static func spaces(of windowID: CGWindowID) -> [UInt64] {
        guard let connection, let copySpacesForWindows,
              let spaces = copySpacesForWindows(connection, 0x7, [NSNumber(value: windowID)] as CFArray)?
                  .takeRetainedValue() as? [NSNumber]
        else { return [] }
        return spaces.map(\.uint64Value)
    }

    /// The Space the user is working in, the one that holds the front app. Nil if unknown.
    static func activeSpace() -> UInt64? {
        guard let connection, let getActiveSpace else { return nil }
        let space = getActiveSpace(connection)
        return space != 0 ? space : nil
    }

    /// Makes `psn` the app a Space shows in front when the user next returns to it. Returns false
    /// if the function is missing or fails.
    static func setFrontProcess(_ psn: ProcessSerialNumber, ofSpace space: UInt64) -> Bool {
        guard let connection, let spaceSetFrontPSN else { return false }
        return spaceSetFrontPSN(connection, space, psn) == .success
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
