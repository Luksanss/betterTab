#if DEBUG
import ApplicationServices
import CoreGraphics
import Foundation
import Synchronization
import os

// What the self-test reads and posts, callable from any thread. Kept separate from the product's
// readers, which other work is rewriting, so the test observes the system independently.

nonisolated let selfTestLog = Logger(subsystem: "com.luksanss.BetterTab", category: "selftest")

/// Runs `work` on a global queue, so AX calls never block the main actor the controller runs on.
nonisolated func selfTestOffMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: work()) }
    }
}

// MARK: - SkyLight: windows and Spaces, no permission needed

nonisolated struct SelfTestWindow: Sendable, Equatable {
    let id: UInt32
    let pid: Int32
    let minimized: Bool
    let fullScreen: Bool
}

nonisolated enum SelfTestSkyLight {
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias CopyWindowsWithOptionsAndTags = @convention(c) (
        Int32, UInt32, CFArray, UInt32, UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>
    ) -> Unmanaged<CFArray>?
    private typealias QueryWindows = @convention(c) (Int32, CFArray, Int32) -> UnsafeMutableRawPointer?
    private typealias QueryResultCopyWindows = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
    private typealias IteratorAdvance = @convention(c) (UnsafeMutableRawPointer) -> Bool
    private typealias IteratorUInt32 = @convention(c) (UnsafeMutableRawPointer) -> UInt32
    private typealias IteratorInt32 = @convention(c) (UnsafeMutableRawPointer) -> Int32
    private typealias IteratorUInt64 = @convention(c) (UnsafeMutableRawPointer) -> UInt64

    private static let path = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"

    /// AppKit has loaded SkyLight already, so this only returns a handle to it.
    private static func resolve<T>(_ name: String, _: T.Type) -> T? {
        guard let handle = dlopen(path, RTLD_LAZY), let address = dlsym(handle, name) else { return nil }
        return unsafeBitCast(address, to: T.self)
    }

    private static let mainConnectionID = resolve("SLSMainConnectionID", MainConnectionID.self)
    private static let copyManagedDisplaySpaces = resolve("SLSCopyManagedDisplaySpaces", CopyManagedDisplaySpaces.self)
    private static let copySpacesForWindows = resolve("SLSCopySpacesForWindows", CopySpacesForWindows.self)
    private static let copyWindows = resolve("SLSCopyWindowsWithOptionsAndTags", CopyWindowsWithOptionsAndTags.self)
    private static let queryWindows = resolve("SLSWindowQueryWindows", QueryWindows.self)
    private static let queryResultCopyWindows = resolve("SLSWindowQueryResultCopyWindows", QueryResultCopyWindows.self)
    private static let advance = resolve("SLSWindowIteratorAdvance", IteratorAdvance.self)
    private static let windowID = resolve("SLSWindowIteratorGetWindowID", IteratorUInt32.self)
    private static let parentID = resolve("SLSWindowIteratorGetParentID", IteratorUInt32.self)
    private static let pid = resolve("SLSWindowIteratorGetPID", IteratorInt32.self)
    private static let level = resolve("SLSWindowIteratorGetLevel", IteratorInt32.self)
    private static let tags = resolve("SLSWindowIteratorGetTags", IteratorUInt64.self)
    private static let attributes = resolve("SLSWindowIteratorGetAttributes", IteratorUInt64.self)

    static var isAvailable: Bool {
        mainConnectionID != nil && copyManagedDisplaySpaces != nil && copySpacesForWindows != nil
            && copyWindows != nil && queryWindows != nil && queryResultCopyWindows != nil && advance != nil
            && windowID != nil && parentID != nil && pid != nil && level != nil && tags != nil && attributes != nil
    }

    private static var connection: Int32 { mainConnectionID?() ?? 0 }

    private static func displays() -> [[String: Any]] {
        copyManagedDisplaySpaces?(connection)?.takeRetainedValue() as? [[String: Any]] ?? []
    }

    private static func spaceID(_ space: Any?) -> UInt64? {
        guard let space = space as? [String: Any] else { return nil }
        return ((space["ManagedSpaceID"] ?? space["id64"]) as? NSNumber)?.uint64Value
    }

    /// Each display's current Space.
    static func currentSpaces() -> [UInt64] {
        displays().compactMap { spaceID($0["Current Space"]) }
    }

    static func allSpaces() -> [UInt64] {
        displays().flatMap { ($0["Spaces"] as? [Any] ?? []).compactMap(spaceID) }
    }

    static func spaces(of window: UInt32) -> [UInt64] {
        guard let copySpacesForWindows else { return [] }
        let result = copySpacesForWindows(connection, 0x7, [NSNumber(value: window)] as CFArray)?.takeRetainedValue()
        return (result as? [NSNumber] ?? []).map(\.uint64Value)
    }

    /// Every real window of `pids` on every Space, in SkyLight's order (current Space first).
    static func realWindows(of pids: Set<Int32>) -> [SelfTestWindow] {
        guard isAvailable, let copyWindows, let queryWindows, let queryResultCopyWindows, let advance,
              let windowID, let parentID, let pid, let level, let tags, let attributes
        else { return [] }
        let cid = connection
        var setTags: UInt64 = 0
        var clearTags: UInt64 = 0
        let spaces = allSpaces().map { NSNumber(value: $0) } as CFArray
        guard let ids = copyWindows(cid, 0, spaces, 0x7, &setTags, &clearTags)?.takeRetainedValue() else { return [] }
        let count = CFArrayGetCount(ids)
        guard count > 0, let query = queryWindows(cid, ids, Int32(count)) else { return [] }
        defer { Unmanaged<AnyObject>.fromOpaque(query).release() }
        guard let iterator = queryResultCopyWindows(query) else { return [] }
        defer { Unmanaged<AnyObject>.fromOpaque(iterator).release() }

        var windows: [SelfTestWindow] = []
        while advance(iterator) {
            let owner = pid(iterator)
            guard pids.contains(owner) else { continue }
            let rowTags = tags(iterator)
            guard SelfTestPlan.isRealWindow(parent: parentID(iterator), level: level(iterator), tags: rowTags,
                                            attributes: attributes(iterator))
            else { continue }
            windows.append(SelfTestWindow(
                id: windowID(iterator), pid: owner,
                minimized: rowTags & SelfTestPlan.minimizedTag != 0,
                fullScreen: rowTags & SelfTestPlan.fullScreenTag != 0))
        }
        return windows
    }
}

// MARK: - Accessibility: the Dock's switcher and apps' windows

/// One icon in the native switcher. `frame` is AX top-left global.
nonisolated struct SelfTestDockItem: Sendable, Equatable {
    let pid: Int32?
    let frame: CGRect?
}

nonisolated struct SelfTestSwitcher: Sendable, Equatable {
    let frame: CGRect?
    let count: Int
    /// Empty for a light read, which only follows the highlight.
    let items: [SelfTestDockItem]
    let selected: Int?
}

/// Running apps by bundle path and by name, read on the main actor and handed to AX readers.
nonisolated struct SelfTestAppMatch: Sendable {
    var byPath: [String: Int32] = [:]
    var byName: [String: Int32] = [:]

    func pid(url: URL?, name: String?) -> Int32? {
        if let url, let pid = byPath[Self.normalized(url)] { return pid }
        if let name, !name.isEmpty { return byName[name] }
        return nil
    }

    static func normalized(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}

nonisolated enum SelfTestAX {
    static let timeout: Float = 0.25

    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> AXError
    private static let getWindow: GetWindow? = {
        let path = "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/Versions/A/HIServices"
        guard let handle = dlopen(path, RTLD_LAZY), let address = dlsym(handle, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(address, to: GetWindow.self)
    }()

    static func application(_ pid: Int32) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, timeout)
        return element
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    private static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success || error == .noValue else { return nil }
        let elements = value as? [AXUIElement] ?? []
        for element in elements { AXUIElementSetMessagingTimeout(element, timeout) }
        return elements
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let result = value as! AXUIElement
        AXUIElementSetMessagingTimeout(result, timeout)
        return result
    }

    private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = value(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = value(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &extent)
        else { return nil }
        return CGRect(origin: point, size: extent)
    }

    private static func url(_ element: AXUIElement) -> URL? {
        let value = value(element, kAXURLAttribute)
        if let url = value as? URL { return url }
        guard let string = value as? String, !string.isEmpty else { return nil }
        if let url = URL(string: string), url.isFileURL { return url }
        return string.hasPrefix("/") ? URL(fileURLWithPath: string) : nil
    }

    static func windowID(_ window: AXUIElement) -> UInt32? {
        var id: UInt32 = 0
        guard let getWindow, getWindow(window, &id) == .success, id != 0 else { return nil }
        return id
    }

    /// The Dock's `AXProcessSwitcherList`, or nil when the switcher isn't up.
    static func switcher(dockPid: Int32, match: SelfTestAppMatch, withItems: Bool) -> SelfTestSwitcher? {
        let dock = application(dockPid)
        guard let list = elements(dock, kAXChildrenAttribute)?
            .first(where: { string($0, kAXSubroleAttribute) == "AXProcessSwitcherList" }),
            let kids = elements(list, kAXChildrenAttribute)
        else { return nil }
        var selected: Int?
        if let first = elements(list, kAXSelectedChildrenAttribute)?.first {
            selected = kids.firstIndex { CFEqual($0, first) }
            if selected == nil, let title = string(first, kAXTitleAttribute) {
                selected = kids.firstIndex { string($0, kAXTitleAttribute) == title }
            }
        }
        let items = withItems
            ? kids.map { SelfTestDockItem(pid: match.pid(url: url($0), name: string($0, kAXTitleAttribute)), frame: frame($0)) }
            : []
        return SelfTestSwitcher(frame: withItems ? frame(list) : nil, count: kids.count, items: items, selected: selected)
    }

    /// The window id of the app's focused window, as AX reports it.
    static func focusedWindow(pid: Int32) -> UInt32? {
        element(application(pid), kAXFocusedWindowAttribute).flatMap(windowID)
    }

    /// AX standard windows, which cover the current Space only. nil when the app didn't answer.
    static func standardWindowCount(pid: Int32) -> Int? {
        guard let windows = elements(application(pid), kAXWindowsAttribute) else { return nil }
        return windows.filter { string($0, kAXSubroleAttribute) == kAXStandardWindowSubrole }.count
    }
}

// MARK: - Synthetic keys

/// Untagged keyboard events posted to the HID tap, so BetterTab's own tap treats them as real.
/// Keyboard only, never the mouse. Tracks whether the test is holding ⌘.
nonisolated final class SelfTestKeys: Sendable {
    static let tab: CGKeyCode = 48
    static let escape: CGKeyCode = 53
    static let returnKey: CGKeyCode = 36
    static let command: CGKeyCode = 55
    static let downArrow: CGKeyCode = 125
    static let letterA: CGKeyCode = 0
    static let letterS: CGKeyCode = 1

    /// ⌘ and the left-⌘ device bit, plus non-coalesced: what a real left ⌘ sets while it's down.
    static let commandFlags = CGEventFlags(rawValue: 0x100108)
    static let noFlags = CGEventFlags(rawValue: 0x100)

    private let held = Mutex(false)
    private let location: CGEventTapLocation

    init(location: CGEventTapLocation = .cghidEventTap) {
        self.location = location
    }

    var isCommandHeld: Bool { held.withLock { $0 } }

    func commandDown() {
        post(Self.command, down: true, flags: Self.commandFlags, modifier: true)
        held.withLock { $0 = true }
    }

    func commandUp() {
        post(Self.command, down: false, flags: Self.noFlags, modifier: true)
        held.withLock { $0 = false }
    }

    /// Down, then up `gap` seconds later, with ⌘ in the flags while the test holds it.
    func press(_ key: CGKeyCode, gap: TimeInterval = 0.012) {
        let flags = isCommandHeld ? Self.commandFlags : Self.noFlags
        post(key, down: true, flags: flags, modifier: false)
        Thread.sleep(forTimeInterval: gap)
        post(key, down: false, flags: flags, modifier: false)
    }

    /// ⌘ down, Tab, ⌘ up, spaced `gap` apart. Blocks, so run it off the main actor. Returns the
    /// seconds from ⌘ down to ⌘ up.
    func quickCommandTab(gap: TimeInterval) -> TimeInterval {
        let start = Date()
        commandDown()
        Thread.sleep(forTimeInterval: gap)
        press(Self.tab, gap: gap)
        Thread.sleep(forTimeInterval: gap)
        commandUp()
        return Date().timeIntervalSince(start)
    }

    private func post(_ key: CGKeyCode, down: Bool, flags: CGEventFlags, modifier: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else {
            selfTestLog.error("CGEvent returned nil for a synthetic key")
            return
        }
        if modifier, event.type != .flagsChanged { event.type = .flagsChanged }
        event.flags = flags
        event.post(tap: location)
    }

    /// Whether ⌘ is down, as the HID system and as the session see it.
    static func commandState() -> (hid: Bool, session: Bool) {
        (CGEventSource.flagsState(.hidSystemState).contains(.maskCommand),
         CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand))
    }

    /// Seconds since a real mouse click or a mouse move, whichever the caller asks about.
    static func secondsSinceMouse(clicks: Bool) -> TimeInterval {
        let types: [CGEventType] = clicks ? [.leftMouseDown, .rightMouseDown, .otherMouseDown] : [.mouseMoved]
        return types.map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }.min() ?? .infinity
    }
}

// MARK: - The report on disk

/// Holds the report and writes it after every change, so a crash still leaves the results so far.
nonisolated final class SelfTestRecorder: Sendable {
    let url: URL
    private let report: Mutex<SelfTestReport>
    private let finished = Mutex(false)

    init(url: URL, report: SelfTestReport) {
        self.url = url
        self.report = Mutex(report)
    }

    var isFinished: Bool { finished.withLock { $0 } }

    func update(_ change: (inout SelfTestReport) -> Void) {
        let data = report.withLock { report -> Data? in
            change(&report)
            return try? report.encoded()
        }
        write(data)
    }

    /// The first call wins; later ones, from the watchdog or the run, change nothing.
    @discardableResult
    func finish(result: String?, finding: String?) -> Bool {
        let first = finished.withLock { done -> Bool in
            defer { done = true }
            return !done
        }
        guard first else { return false }
        update { report in
            report.result = result ?? SelfTestReport.overall(report.summary)
            if let finding, report.finding == nil { report.finding = finding }
            report.checkpoint = nil
            report.finishedAt = Date().ISO8601Format()
        }
        let summary = report.withLock { "\($0.result): \($0.summary.passed) passed, \($0.summary.failed) failed, \($0.summary.skipped) skipped" }
        selfTestLog.notice("self-test finished, \(summary, privacy: .public); report at \(self.url.path, privacy: .public)")
        return true
    }

    private func write(_ data: Data?) {
        guard let data else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            selfTestLog.error("couldn't write the self-test report: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - The watchdog

/// Ends a run that has gone on too long, from its own queue, so a stuck main thread can't stop it:
/// lets go of ⌘, cancels whatever the switcher is doing, and writes the report.
nonisolated final class SelfTestWatchdog: Sendable {
    private struct State {
        var deadline: DispatchTime
        var fired = false
        var stopped = false
    }

    private let state: Mutex<State>
    private let queue = DispatchQueue(label: "com.luksanss.BetterTab.selftest.watchdog")
    private let onFire: @Sendable () -> Void

    init(seconds: Double, onFire: @escaping @Sendable () -> Void) {
        state = Mutex(State(deadline: .now() + seconds))
        self.onFire = onFire
    }

    var hasFired: Bool { state.withLock { $0.fired } }

    func start() { check() }

    /// For `--pause`: the time spent holding at a checkpoint doesn't count.
    func extend(by seconds: Double) {
        state.withLock { $0.deadline = $0.deadline + seconds }
    }

    func stop() {
        state.withLock { $0.stopped = true }
    }

    private func check() {
        let fire = state.withLock { state -> Bool? in
            if state.stopped || state.fired { return nil }
            guard DispatchTime.now() >= state.deadline else { return false }
            state.fired = true
            return true
        }
        switch fire {
        case nil: return
        case true?: onFire()
        case false?: queue.asyncAfter(deadline: .now() + 0.5) { [self] in check() }
        }
    }
}

/// Lets go of everything the run may be holding. Any thread; blocks for about half a second.
nonisolated func selfTestEmergencyRelease(keys: SelfTestKeys, dockPid: Int32?) -> [String] {
    var actions: [String] = []
    let switcherUp = { dockPid.map { SelfTestAX.switcher(dockPid: $0, match: SelfTestAppMatch(), withItems: false) != nil } ?? false }
    if keys.isCommandHeld {
        // Cycling with the test's ⌘ down: Esc makes the Dock cancel, then ⌘ goes up.
        if switcherUp() {
            keys.press(SelfTestKeys.escape)
            actions.append("Esc with ⌘")
        }
        Thread.sleep(forTimeInterval: 0.04)
        keys.commandUp()
        actions.append("⌘ up")
        Thread.sleep(forTimeInterval: 0.2)
    }
    if switcherUp() {
        // Held open with ⌘ released: a ⌘ press and release ends Picking in the tap itself.
        keys.commandDown()
        Thread.sleep(forTimeInterval: 0.04)
        keys.commandUp()
        actions.append("⌘ tap")
        Thread.sleep(forTimeInterval: 0.2)
    }
    let state = SelfTestKeys.commandState()
    if state.hid || state.session {
        keys.commandUp()
        actions.append("⌘ up (flags showed ⌘ down)")
    }
    return actions
}
#endif
