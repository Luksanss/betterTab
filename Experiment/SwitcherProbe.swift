import ApplicationServices
import CoreGraphics
import Dispatch
import Foundation
import os

nonisolated struct SwitcherItem: Sendable {
    let title: String
    let frame: CGRect?
}

nonisolated struct SwitcherReading: Sendable {
    let listFrame: CGRect?
    let selected: String?
    let items: [SwitcherItem]
}

nonisolated struct DockWindow: Sendable {
    let number: Int
    let layer: Int
    let bounds: CGRect
    let alpha: Double
}

nonisolated func describe(_ rect: CGRect?) -> String {
    guard let r = rect else { return "unknown" }
    return "(\(Int(r.minX)), \(Int(r.minY)), \(Int(r.width))×\(Int(r.height)))"
}

/// Reads the Dock's native switcher through Accessibility, on its own queue, never on the tap
/// thread. App names only, never window titles.
nonisolated final class SwitcherProbe: Sendable {
    private let queue = DispatchQueue(label: "com.luksanss.BetterTab.Experiment.ax", qos: .userInitiated)
    private let machine: HoldMachine
    private let onLayer: @Sendable (Int) -> Void

    init(machine: HoldMachine, onLayer: @escaping @Sendable (Int) -> Void) {
        self.machine = machine
        self.onLayer = onLayer
        queue.async {
            // Global default for this process; each Dock element also gets it below.
            AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Timing.axMessagingTimeout)
        }
    }

    /// Called on every phase change.
    func phaseEntered(_ snapshot: Snapshot, dockPid: pid_t?) {
        guard snapshot.phase != .idle else { return }
        guard let dockPid else {
            Log.ax.error("AX the Dock isn't running; nothing to probe")
            return
        }
        queue.async { [self] in
            if snapshot.phase == .holding { logHoldStartContext(dockPid: dockPid) }
            poll(snapshot, dockPid: dockPid, attempt: 1)
        }
    }

    /// Re-checks every 50 ms for up to 1 s, so a quick tap (test 0i) shows when the switcher draws.
    private func poll(_ snapshot: Snapshot, dockPid: pid_t, attempt: Int) {
        let phase = snapshot.phase.rawValue
        let elapsed = uptimeNanos() &- snapshot.enteredAt
        let ms = Int(elapsed / 1_000_000)
        guard machine.isCurrent(snapshot.generation) else {
            Log.ax.notice("AX \(phase, privacy: .public) ended \(ms, privacy: .public) ms in, before the switcher was found")
            return
        }
        if let reading = readSwitcher(dockPid: dockPid, depth: 0) {
            Log.ax.notice("""
                AX switcher FOUND (\(phase, privacy: .public)) \(ms, privacy: .public) ms after entering, check #\(attempt, privacy: .public): \
                \(reading.items.count, privacy: .public) apps, selected=\(reading.selected ?? "none", privacy: .public), \
                list frame=\(describe(reading.listFrame), privacy: .public)
                """)
            for (index, item) in reading.items.enumerated() {
                Log.ax.notice("AX   item \(index, privacy: .public): \(item.title, privacy: .public) frame=\(describe(item.frame), privacy: .public)")
            }
            if let listFrame = reading.listFrame { reportLayer(around: listFrame, dockPid: dockPid) }
            if snapshot.phase == .holding { scheduleHeartbeat(snapshot, dockPid: dockPid) }
            return
        }
        if elapsed >= Timing.appearancePollWindow {
            let deeper = readSwitcher(dockPid: dockPid, depth: 2)
            Log.ax.notice("""
                AX switcher NOT FOUND (\(phase, privacy: .public)) within 1 s (\(attempt, privacy: .public) checks); \
                a deeper search found it=\(deeper != nil, privacy: .public)
                """)
            if snapshot.phase == .holding { scheduleHeartbeat(snapshot, dockPid: dockPid) }
            return
        }
        queue.asyncAfter(deadline: .now() + .milliseconds(Timing.appearancePollInterval)) { [self] in
            poll(snapshot, dockPid: dockPid, attempt: attempt + 1)
        }
    }

    /// Evidence for test 0h: did the Tab we passed during the hold move the native highlight?
    func logSelectionAfterTab(generation: UInt64, dockPid: pid_t?) {
        guard let dockPid else { return }
        queue.asyncAfter(deadline: .now() + .milliseconds(Timing.selectionCheckDelay)) { [self] in
            guard machine.isCurrent(generation) else { return }
            let reading = readSwitcher(dockPid: dockPid, depth: 0)
            Log.ax.notice("""
                AX after Tab during hold: switcher on screen=\(reading != nil, privacy: .public), \
                selected=\(reading?.selected ?? "none", privacy: .public)
                """)
        }
    }

    /// Evidence for test 0a: the switcher is still on screen while the hold lasts.
    private func scheduleHeartbeat(_ snapshot: Snapshot, dockPid: pid_t) {
        queue.asyncAfter(deadline: .now() + Timing.heartbeatInterval) { [self] in
            guard machine.isCurrent(snapshot.generation) else { return }
            let held = seconds(uptimeNanos() &- snapshot.enteredAt)
            let reading = readSwitcher(dockPid: dockPid, depth: 0)
            Log.ax.notice("""
                AX heartbeat: holding \(held, format: .fixed(precision: 1), privacy: .public) s, \
                switcher on screen=\(reading != nil, privacy: .public), selected=\(reading?.selected ?? "none", privacy: .public)
                """)
            scheduleHeartbeat(snapshot, dockPid: dockPid)
        }
    }

    // MARK: Hold-start context

    private func logHoldStartContext(dockPid: pid_t) {
        let session = CGEventSource.flagsState(.combinedSessionState)
        let hid = CGEventSource.flagsState(.hidSystemState)
        Log.win.notice("""
            FLAGS at hold start: session ⌘ down=\(session.contains(.maskCommand), privacy: .public) (\(hex(session.rawValue), privacy: .public)), \
            HID ⌘ down=\(hid.contains(.maskCommand), privacy: .public) (\(hex(hid.rawValue), privacy: .public))
            """)
        let windows = dockWindows(dockPid: dockPid)
        Log.win.notice("WIN \(windows.count, privacy: .public) on-screen windows owned by the Dock (pid \(dockPid, privacy: .public)):")
        for w in windows {
            Log.win.notice("""
                WIN   #\(w.number, privacy: .public) layer=\(w.layer, privacy: .public) \
                bounds=\(describe(w.bounds), privacy: .public) alpha=\(w.alpha, format: .fixed(precision: 2), privacy: .public)
                """)
        }
    }

    /// The switcher's window is taken to be the smallest Dock window around the AX list.
    private func reportLayer(around listFrame: CGRect, dockPid: pid_t) {
        let centre = CGPoint(x: listFrame.midX, y: listFrame.midY)
        let match = dockWindows(dockPid: dockPid)
            .filter { $0.bounds.contains(centre) }
            .min { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
        guard let match else {
            Log.win.notice("WIN no on-screen Dock window contains the switcher list")
            return
        }
        Log.win.notice("""
            WIN switcher window is probably #\(match.number, privacy: .public) at layer \(match.layer, privacy: .public), \
            bounds=\(describe(match.bounds), privacy: .public)
            """)
        onLayer(match.layer)
    }

    private func dockWindows(dockPid: pid_t) -> [DockWindow] {
        guard let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], CGWindowID(0)) as? [[String: Any]]
        else { return [] }
        return infos.compactMap { info in
            // Names would need Screen Recording, so only numbers are read.
            guard (info[kCGWindowOwnerPID as String] as? Int32) == dockPid,
                let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary)
            else { return nil }
            return DockWindow(
                number: info[kCGWindowNumber as String] as? Int ?? -1,
                layer: info[kCGWindowLayer as String] as? Int ?? 0,
                bounds: bounds,
                alpha: info[kCGWindowAlpha as String] as? Double ?? 1)
        }
    }

    // MARK: Accessibility

    private func readSwitcher(dockPid: pid_t, depth: Int) -> SwitcherReading? {
        let dock = AXUIElementCreateApplication(dockPid)
        AXUIElementSetMessagingTimeout(dock, Timing.axMessagingTimeout)
        guard let list = findList(in: dock, depth: depth) else { return nil }
        let items = children(of: list).map { SwitcherItem(title: string(of: $0, "AXTitle") ?? "?", frame: frame(of: $0)) }
        let selected = (value(of: list, "AXSelectedChildren") as? [AXUIElement])?.first
            .flatMap { string(of: $0, "AXTitle") }
        return SwitcherReading(listFrame: frame(of: list), selected: selected, items: items)
    }

    private func findList(in element: AXUIElement, depth: Int) -> AXUIElement? {
        let kids = children(of: element)
        if let list = kids.first(where: { string(of: $0, "AXSubrole") == "AXProcessSwitcherList" }) {
            return list
        }
        guard depth > 0 else { return nil }
        for kid in kids {
            if let list = findList(in: kid, depth: depth - 1) { return list }
        }
        return nil
    }

    private func value(of element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        value(of: element, "AXChildren") as? [AXUIElement] ?? []
    }

    private func string(of element: AXUIElement, _ attribute: String) -> String? {
        value(of: element, attribute) as? String
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let position = value(of: element, "AXPosition"), CFGetTypeID(position) == AXValueGetTypeID(),
            let size = value(of: element, "AXSize"), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
            AXValueGetValue(size as! AXValue, .cgSize, &extent)
        else { return nil }
        return CGRect(origin: point, size: extent)
    }
}
