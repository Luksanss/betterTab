import AppKit

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

    /// Starts looking for the switcher. Call on ⌘⇥. Does nothing if already running.
    func begin() {}
    /// Stops observing and forgets the snapshot. Idempotent.
    func end() {}
}
