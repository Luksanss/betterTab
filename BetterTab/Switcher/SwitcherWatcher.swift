import AppKit
import ApplicationServices
import os

/// One app icon in the native ⌘⇥ switcher. `frame` is AppKit global coordinates (bottom-left
/// origin), already converted from AX's top-left ones.
struct SwitcherItem: Equatable, Sendable {
    /// nil when the icon couldn't be matched to a running app.
    let pid: pid_t?
    let name: String
    let frame: CGRect
}

/// What the native switcher shows right now.
struct SwitcherSnapshot: Equatable, Sendable {
    /// The switcher's own frame (the `AXProcessSwitcherList` element), AppKit global coordinates.
    let frame: CGRect
    let items: [SwitcherItem]
    let selectedIndex: Int?

    var selected: SwitcherItem? { selectedIndex.flatMap { items.indices.contains($0) ? items[$0] : nil } }
}

/// Watches the Dock's `AXProcessSwitcherList` while ⌘⇥ is up. All callbacks arrive on the main
/// actor; AX work happens off it.
final class SwitcherWatcher {
    /// The switcher was found, its highlight moved, or its items changed.
    var onChange: ((SwitcherSnapshot) -> Void)?
    /// The switcher went away: switched, cancelled, or closed by a click.
    var onClose: (() -> Void)?
    /// One lookup finished, found or not. Feeds `AppStatus.switcherLookup(succeeded:)`.
    var onLookupFinished: ((_ found: Bool) -> Void)?

    private(set) var current: SwitcherSnapshot?

    private var thread: AXObserverThread?
    /// Bumped whenever a session ends, so its late deliveries are dropped.
    private var generation: UInt64 = 0

    /// Starts looking for the switcher. Call on ⌘⇥. Does nothing if already running.
    // A session ends by itself once the switcher closes or isn't found. An `end()` during the
    // lookup reports nothing, so a quick tap never counts as a failed lookup.
    func begin() {
        guard thread == nil else { return }
        generation &+= 1
        let generation = generation
        let deliver: @Sendable (SwitcherEvent) -> Void = { [weak self] event in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.receive(event, generation: generation) }
            }
        }
        let thread = AXObserverThread()
        self.thread = thread
        thread.start(name: "BetterTab.SwitcherWatcher", qos: .userInteractive) { thread in
            SwitcherSession.make(thread: thread, deliver: deliver)
        }
    }

    /// Stops observing and forgets the snapshot. Idempotent.
    func end() {
        generation &+= 1
        thread?.stop()
        thread = nil
        current = nil
    }

    private func receive(_ event: SwitcherEvent, generation: UInt64) {
        guard generation == self.generation else { return }
        switch event {
        case .found(let raw):
            let snapshot = Self.appKitSnapshot(raw)
            current = snapshot
            onLookupFinished?(true)
            // The callback may have ended this session.
            guard generation == self.generation else { return }
            onChange?(snapshot)
        case .changed(let raw):
            let snapshot = Self.appKitSnapshot(raw)
            current = snapshot
            onChange?(snapshot)
        case .notFound:
            // The session has already stopped itself; `end()` clears what's left.
            end()
            onLookupFinished?(false)
        case .closed:
            end()
            onClose?()
        }
    }

    /// AX frames are top-left global; AppKit's are bottom-left, measured from the primary screen.
    private static func appKitSnapshot(_ raw: RawSwitcherSnapshot) -> SwitcherSnapshot {
        let screens = NSScreen.screens
        let primaryHeight = (screens.first { $0.frame.origin == .zero } ?? screens.first)?.frame.height ?? 0
        func flip(_ rect: CGRect?) -> CGRect {
            guard let rect else { return .zero }
            return CGRect(x: rect.minX, y: primaryHeight - rect.minY - rect.height, width: rect.width, height: rect.height)
        }
        return SwitcherSnapshot(
            frame: flip(raw.frame),
            items: raw.items.map { SwitcherItem(pid: $0.pid, name: $0.name, frame: flip($0.frame)) },
            selectedIndex: raw.selectedIndex)
    }
}

// MARK: - The session, on its own thread

nonisolated private let switcherLog = Logger(subsystem: "com.luksanss.BetterTab", category: "switcher")

nonisolated private enum SwitcherTiming {
    static let lookupInterval: CFTimeInterval = 0.05
    static let lookupWindowMs = 1000
    /// Safety net for a missed destroyed notification: a click closes the switcher, and until the
    /// controller hears of it, the held ⌘ release stays swallowed.
    static let livenessInterval: CFTimeInterval = 0.1
    /// Consecutive failed reads (timeouts) before the switcher is taken to be gone.
    static let failureLimit = 3
}

/// Frames are still AX top-left; the main actor converts them.
nonisolated private struct RawSwitcherItem: Equatable, Sendable {
    let pid: pid_t?
    let name: String
    let frame: CGRect?
}

nonisolated private struct RawSwitcherSnapshot: Equatable, Sendable {
    let frame: CGRect?
    let items: [RawSwitcherItem]
    let selectedIndex: Int?
}

nonisolated private enum SwitcherEvent: Sendable {
    case found(RawSwitcherSnapshot)
    case changed(RawSwitcherSnapshot)
    case notFound
    case closed
}

nonisolated private func switcherObserverCallback(
    _ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    Unmanaged<SwitcherSession>.fromOpaque(refcon).takeUnretainedValue().notified(notification as String)
}

nonisolated private func switcherTimerCallback(_ timer: CFRunLoopTimer?, _ info: UnsafeMutableRawPointer?) {
    guard let info else { return }
    Unmanaged<SwitcherSession>.fromOpaque(info).takeUnretainedValue().timerFired()
}

/// One ⌘⇥ session: find the list, then follow it until it goes away. Lives on its thread only.
nonisolated private final class SwitcherSession: AXObserverWorker {
    private enum Phase { case looking, watching, done }

    private let thread: AXObserverThread
    private let deliver: @Sendable (SwitcherEvent) -> Void
    private let dock: AXUIElement
    private let startedAt = DispatchTime.now().uptimeNanoseconds
    private var observer: AXObserver?
    private var timer: CFRunLoopTimer?
    private var phase = Phase.looking
    private var checks = 0

    private var list: AXUIElement?
    private var children: [AXUIElement] = []
    private var items: [RawSwitcherItem] = []
    private var listFrame: CGRect?
    private var last: RawSwitcherSnapshot?
    private var failures = 0
    /// Whether CFEqual recognises the list among the Dock's children, checked once when found.
    private var canCheckMembership = false
    private var foundAt: UInt64 = 0
    /// How the last item read matched icons to pids; counts only.
    private var mapping = ""

    static func make(thread: AXObserverThread, deliver: @escaping @Sendable (SwitcherEvent) -> Void) -> SwitcherSession? {
        guard let dockPid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?.processIdentifier
        else {
            switcherLog.error("the Dock isn't running; switcher not found")
            deliver(.notFound)
            return nil
        }
        return SwitcherSession(dockPid: dockPid, thread: thread, deliver: deliver)
    }

    private init(dockPid: pid_t, thread: AXObserverThread, deliver: @escaping @Sendable (SwitcherEvent) -> Void) {
        self.thread = thread
        self.deliver = deliver
        dock = AXCall.application(dockPid)

        var created: AXObserver?
        let result = AXObserverCreate(dockPid, switcherObserverCallback, &created)
        if result == .success, let created {
            observer = created
            CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(created), .defaultMode)
        } else {
            // Polling alone still follows the switcher, just up to 100 ms late.
            switcherLog.error("AXObserverCreate on the Dock failed (\(result.rawValue, privacy: .public)); polling only")
        }
        schedule(every: SwitcherTiming.lookupInterval)
    }

    func tearDown() {
        cancelTimer()
        if let observer {
            if let list {
                AXObserverRemoveNotification(observer, list, kAXSelectedChildrenChangedNotification as CFString)
                AXObserverRemoveNotification(observer, list, kAXUIElementDestroyedNotification as CFString)
            }
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        list = nil
    }

    // MARK: Timer and notifications

    fileprivate func timerFired() {
        guard !thread.isStopRequested else { return }
        switch phase {
        case .looking: lookUp()
        case .watching: checkLiveness()
        case .done: break
        }
    }

    fileprivate func notified(_ notification: String) {
        guard phase == .watching, !thread.isStopRequested else { return }
        switch notification {
        case kAXUIElementDestroyedNotification: close(reason: "destroyed")
        case kAXSelectedChildrenChangedNotification: refresh()
        default: break
        }
    }

    private func schedule(every interval: CFTimeInterval) {
        cancelTimer()
        var context = CFRunLoopTimerContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let timer = CFRunLoopTimerCreate(
            kCFAllocatorDefault, CFAbsoluteTimeGetCurrent(), interval, 0, 0, switcherTimerCallback, &context)
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .defaultMode)
        self.timer = timer
    }

    private func cancelTimer() {
        if let timer { CFRunLoopTimerInvalidate(timer) }
        timer = nil
    }

    // MARK: Lookup

    private func lookUp() {
        checks += 1
        if let list = findList(in: dock, depth: 0), attach(list) { return }
        guard elapsedMs(since: startedAt) >= SwitcherTiming.lookupWindowMs else { return }
        // Once, as a last resort, in case the Dock ever nests the list.
        if let list = findList(in: dock, depth: 2), attach(list) {
            switcherLog.notice("switcher found only by the deeper search")
            return
        }
        switcherLog.notice("switcher NOT found within 1 s (\(self.checks, privacy: .public) checks, deeper search too)")
        finish(.notFound)
    }

    private func findList(in element: AXUIElement, depth: Int) -> AXUIElement? {
        let kids = AXCall.children(element).elements
        if let list = kids.first(where: { AXCall.string($0, kAXSubroleAttribute).string == "AXProcessSwitcherList" }) {
            return list
        }
        guard depth > 0 else { return nil }
        for kid in kids {
            if let list = findList(in: kid, depth: depth - 1) { return list }
        }
        return nil
    }

    /// False if the list is already gone, so the lookup keeps polling.
    private func attach(_ list: AXUIElement) -> Bool {
        if let observer {
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            let destroyed = AXObserverAddNotification(observer, list, kAXUIElementDestroyedNotification as CFString, refcon)
            if destroyed == .invalidUIElement { return false }
            let selection = AXObserverAddNotification(
                observer, list, kAXSelectedChildrenChangedNotification as CFString, refcon)
            if !Self.usable(destroyed) || !Self.usable(selection) {
                switcherLog.error("""
                    switcher notifications not all registered (destroyed \(destroyed.rawValue, privacy: .public), \
                    selection \(selection.rawValue, privacy: .public)); polling covers them
                    """)
            }
        }
        self.list = list
        guard let snapshot = readSnapshot() else {
            detach()
            return false
        }
        let (dockKids, dockError) = AXCall.children(dock)
        canCheckMembership = dockKids.contains { CFEqual($0, list) }
        if !canCheckMembership {
            switcherLog.error("""
                the list isn't recognised among the Dock's children (read \(dockError.rawValue, privacy: .public)); \
                closing is left to the destroyed notification and invalid reads
                """)
        }
        phase = .watching
        foundAt = DispatchTime.now().uptimeNanoseconds
        last = snapshot
        switcherLog.notice("""
            switcher found \(self.elapsedMs(since: self.startedAt), privacy: .public) ms after ⌘⇥, \
            check #\(self.checks, privacy: .public): \(snapshot.items.count, privacy: .public) apps, \
            selected index \(snapshot.selectedIndex ?? -1, privacy: .public), \(self.mapping, privacy: .public)
            """)
        deliver(.found(snapshot))
        schedule(every: SwitcherTiming.livenessInterval)
        return true
    }

    private func detach() {
        if let observer, let list {
            AXObserverRemoveNotification(observer, list, kAXSelectedChildrenChangedNotification as CFString)
            AXObserverRemoveNotification(observer, list, kAXUIElementDestroyedNotification as CFString)
        }
        list = nil
        children = []
        items = []
    }

    private static func usable(_ result: AXError) -> Bool {
        result == .success || result == .notificationAlreadyRegistered
    }

    // MARK: Following the list

    private func checkLiveness() {
        if canCheckMembership, let list {
            let (kids, error) = AXCall.children(dock)
            switch error {
            case .success:
                failures = 0
                if !kids.contains(where: { CFEqual($0, list) }) { return close(reason: "no longer among the Dock's children") }
            case .invalidUIElement:
                return close(reason: "the Dock went away")
            default:
                if countFailure() { return }
            }
        }
        refresh()
    }

    /// Re-reads what can change. Children rarely change while the switcher is up (an app quits),
    /// so they're compared first and the items reused when they match.
    private func refresh() {
        guard let snapshot = readSnapshot() else { return }
        guard snapshot != last else { return }
        last = snapshot
        deliver(.changed(snapshot))
    }

    /// nil when the read failed; closes the session if the list is gone.
    private func readSnapshot() -> RawSwitcherSnapshot? {
        guard let list else { return nil }
        let (kids, error) = AXCall.children(list)
        switch error {
        case .success, .noValue:
            failures = 0
        case .invalidUIElement:
            if phase == .watching { close(reason: "invalid element") }
            return nil
        default:
            if phase == .watching { _ = countFailure() }
            return nil
        }
        if !AXCall.sameElements(kids, children) || last == nil {
            let (fresh, complete) = readItems(kids)
            // An incomplete read (a timeout) is used once, then retried rather than cached.
            children = complete ? kids : []
            listFrame = AXCall.frame(list)
            items = fresh
        }
        guard let selection = selection(in: list, among: kids) else {
            if phase == .watching { _ = countFailure() }
            return nil
        }
        return RawSwitcherSnapshot(frame: listFrame, items: items, selectedIndex: selection.index)
    }

    /// True once the switcher has been declared gone.
    private func countFailure() -> Bool {
        failures += 1
        guard failures >= SwitcherTiming.failureLimit else { return false }
        close(reason: "\(failures) failed reads in a row")
        return true
    }

    private struct Selection { let index: Int? }

    /// nil when the read failed, so a timeout can't pass for "nothing highlighted".
    private func selection(in list: AXUIElement, among kids: [AXUIElement]) -> Selection? {
        let (selected, error) = AXCall.elements(list, kAXSelectedChildrenAttribute)
        guard error == .success || error == .noValue else { return nil }
        guard let first = selected.first else { return Selection(index: nil) }
        let index = kids.firstIndex { CFEqual($0, first) }
            ?? AXCall.string(first, kAXTitleAttribute).string.flatMap { title in items.firstIndex { $0.name == title } }
        return Selection(index: index)
    }

    private func readItems(_ kids: [AXUIElement]) -> (items: [RawSwitcherItem], complete: Bool) {
        let apps = SwitcherRunningApp.all()
        var byURL = 0
        var byName = 0
        var complete = true
        let items = kids.map { kid -> RawSwitcherItem in
            let (title, error) = AXCall.string(kid, kAXTitleAttribute)
            let frame = AXCall.frame(kid)
            if error != .success || frame == nil { complete = false }
            let name = title ?? ""
            let url = AXCall.fileURL(kid, kAXURLAttribute)
            var pid = url.flatMap { SwitcherRunningApp.match(url: $0, in: apps) }
            if pid != nil {
                byURL += 1
            } else {
                pid = SwitcherRunningApp.match(name: name, in: apps)
                if pid != nil { byName += 1 }
            }
            return RawSwitcherItem(pid: pid, name: name, frame: frame)
        }
        mapping = "pid by URL \(byURL), by name \(byName), unmatched \(items.count - byURL - byName)"
        switcherLog.debug("switcher items read: \(self.mapping, privacy: .public), complete \(complete, privacy: .public)")
        return (items, complete)
    }

    // MARK: Ending

    private func close(reason: String) {
        guard phase == .watching else { return }
        switcherLog.notice("""
            switcher closed (\(reason, privacy: .public)) after \(self.elapsedMs(since: self.foundAt), privacy: .public) ms
            """)
        finish(.closed)
    }

    private func finish(_ event: SwitcherEvent) {
        guard phase != .done else { return }
        phase = .done
        cancelTimer()
        deliver(event)
        thread.stop()
    }

    private func elapsedMs(since start: UInt64) -> Int {
        Int((DispatchTime.now().uptimeNanoseconds &- start) / 1_000_000)
    }
}

/// Running apps as the pid matcher needs them, read fresh for each item read.
nonisolated private struct SwitcherRunningApp: Sendable {
    let pid: pid_t
    let name: String?
    let bundleURL: URL?
    let isRegular: Bool

    /// Regular apps first, since those are what the switcher shows.
    static func all() -> [SwitcherRunningApp] {
        NSWorkspace.shared.runningApplications
            .map { app in
                SwitcherRunningApp(
                    pid: app.processIdentifier, name: app.localizedName, bundleURL: app.bundleURL,
                    isRegular: app.activationPolicy == .regular)
            }
            .sorted { $0.isRegular && !$1.isRegular }
    }

    static func match(url: URL, in apps: [SwitcherRunningApp]) -> pid_t? {
        let path = normalizedPath(url)
        return apps.first { $0.bundleURL.map(normalizedPath) == path }?.pid
    }

    static func match(name: String, in apps: [SwitcherRunningApp]) -> pid_t? {
        guard !name.isEmpty else { return nil }
        if let exact = apps.first(where: { $0.name == name }) { return exact.pid }
        return apps.first { $0.name?.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }?.pid
    }

    /// No file-system access, so it's cheap enough to run per app.
    private static func normalizedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
