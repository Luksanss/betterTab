import Carbon.HIToolbox
import Foundation

/// One of the app's windows, as the list needs it.
struct WindowListItem: Equatable {
    var title: String
    var isMinimized: Bool
}

/// What a key press in the list asks the controller to do.
enum WindowListAction: Equatable {
    /// Open this window. The value indexes the `windows` array given to the list, not the rows,
    /// because rows are reordered (minimized windows go last).
    case pick(Int)
    case cancel
    /// -1 is up, +1 is down. The list has already moved its highlight.
    case moveHighlight(by: Int)
}

/// The rows, the overflow count and the highlight. No UI, so the key tap can drive it directly.
struct WindowListModel: Equatable {
    struct Row: Equatable {
        /// Index into the `windows` array the model was built from.
        let windowIndex: Int
        let title: String
        let isMinimized: Bool
    }

    static let maxRows = KeyLabels.keyCodes.count

    private(set) var rows: [Row] = []
    /// Windows beyond `maxRows`, shown as "+N more" and not pickable.
    private(set) var overflowCount = 0
    private(set) var highlight = 0

    init(windows: [WindowListItem]) {
        setWindows(windows)
    }

    /// Replaces the windows, for when the app loses some while the list is open. Windows have no
    /// identity here, so the highlight keeps its row number, clamped to the new rows.
    mutating func setWindows(_ windows: [WindowListItem]) {
        // Front-to-back as given, with minimized windows moved after the rest, keeping their order.
        let ordered = windows.indices.filter { !windows[$0].isMinimized }
            + windows.indices.filter { windows[$0].isMinimized }
        rows = ordered.prefix(Self.maxRows).map { index in
            Row(windowIndex: index,
                title: Self.displayTitle(windows[index].title),
                isMinimized: windows[index].isMinimized)
        }
        overflowCount = max(0, windows.count - Self.maxRows)
        highlight = min(highlight, max(rows.count - 1, 0))
    }

    /// Maps a virtual key code to what it does. Pure: moving the highlight is left to `handle`.
    func action(forKeyCode keyCode: UInt16) -> WindowListAction? {
        switch Int(keyCode) {
        case kVK_Return: return rows.isEmpty ? nil : .pick(rows[highlight].windowIndex)
        case kVK_Escape: return .cancel
        case kVK_UpArrow: return .moveHighlight(by: -1)
        case kVK_DownArrow: return .moveHighlight(by: 1)
        default:
            // A letter with no row next to it does nothing.
            guard let row = KeyLabels.keyCodes.firstIndex(of: keyCode), row < rows.count else { return nil }
            return .pick(rows[row].windowIndex)
        }
    }

    /// `action(forKeyCode:)`, with an arrow's move applied.
    mutating func handle(keyCode: UInt16) -> WindowListAction? {
        let action = action(forKeyCode: keyCode)
        if case .moveHighlight(let delta) = action {
            setHighlight(highlight + delta)
        }
        return action
    }

    /// Clamps at the ends; the highlight doesn't wrap.
    mutating func setHighlight(_ row: Int) {
        highlight = min(max(row, 0), max(rows.count - 1, 0))
    }

    static func displayTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : title
    }
}
