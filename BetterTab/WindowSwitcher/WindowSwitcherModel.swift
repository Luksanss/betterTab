import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// One of the front app's windows, as the ⌘§ switcher needs it.
struct WindowSwitcherItem: Equatable {
    var title: String
    var isMinimized: Bool
    /// The window's frame and the frame of the display it's on, both in the window server's global
    /// coordinates (points, top-left origin, y down). `windowFrame` is `.null` when unknown.
    var windowFrame: CGRect
    var displayFrame: CGRect
}

/// What a key press in the ⌘§ switcher asks the controller to do.
enum WindowSwitcherAction: Equatable {
    /// Open this window. The value indexes the `windows` array given to the model.
    case pick(Int)
    case cancel
    /// The switcher has already moved its highlight.
    case moveHighlight
}

/// The ⌘§ switcher's tiles, the overflow count and the highlight. No UI, so the key tap can drive
/// it directly. Tiles keep the order they're given: the window you're in first, minimized last.
struct WindowSwitcherModel: Equatable {
    struct Tile: Equatable {
        /// Index into the `windows` array the model was built from.
        let windowIndex: Int
        let title: String
        let isMinimized: Bool
        let windowFrame: CGRect
        let displayFrame: CGRect
    }

    static let maxTiles = KeyLabels.keyCodes.count

    private(set) var tiles: [Tile] = []
    /// Windows beyond `maxTiles`, shown as "+N more" and not pickable.
    private(set) var overflowCount = 0
    private(set) var highlight = 0

    init(windows: [WindowSwitcherItem] = [], highlight: Int = 0) {
        setWindows(windows)
        setHighlight(highlight)
    }

    /// Replaces the windows, for when titles arrive or a window goes while the switcher is open.
    /// The highlight keeps its tile number, clamped to the new tiles.
    mutating func setWindows(_ windows: [WindowSwitcherItem]) {
        tiles = windows.prefix(Self.maxTiles).enumerated().map { index, window in
            Tile(windowIndex: index, title: Self.displayTitle(window.title),
                 isMinimized: window.isMinimized, windowFrame: window.windowFrame,
                 displayFrame: window.displayFrame)
        }
        overflowCount = max(0, windows.count - Self.maxTiles)
        highlight = min(highlight, max(tiles.count - 1, 0))
    }

    /// § and ⇧§, and the arrows: the highlight wraps from the last tile to the first, as ⌘⇥ does.
    mutating func step(by delta: Int) {
        guard !tiles.isEmpty else { return }
        highlight = ((highlight + delta) % tiles.count + tiles.count) % tiles.count
    }

    /// Clamps, for the pointer and for the start.
    mutating func setHighlight(_ tile: Int) {
        highlight = min(max(tile, 0), max(tiles.count - 1, 0))
    }

    /// The window the highlight is on, as an index into `windows`.
    var highlightedWindow: Int? {
        tiles.indices.contains(highlight) ? tiles[highlight].windowIndex : nil
    }

    /// Letters and Return pick, Esc cancels, arrows move the highlight (applied when this returns).
    /// Any other key gives nil.
    mutating func handle(keyCode: UInt16) -> WindowSwitcherAction? {
        switch Int(keyCode) {
        case kVK_Return: return highlightedWindow.map(WindowSwitcherAction.pick)
        case kVK_Escape: return .cancel
        case kVK_UpArrow, kVK_LeftArrow:
            step(by: -1)
            return .moveHighlight
        case kVK_DownArrow, kVK_RightArrow:
            step(by: 1)
            return .moveHighlight
        default:
            // A letter with no tile next to it does nothing.
            guard let tile = KeyLabels.keyCodes.firstIndex(of: keyCode), tile < tiles.count else { return nil }
            return .pick(tiles[tile].windowIndex)
        }
    }

    static func displayTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : title
    }
}
