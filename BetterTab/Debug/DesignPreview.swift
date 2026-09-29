#if DEBUG
import AppKit

/// The v5 design's scenarios, for checking the dots and the window list by eye before the real
/// switcher is wired up. Debug builds only.
enum PreviewScenario: Int, CaseIterable {
    case chrome3, terminal2, notes1, minimized, eleven, untitledAndDuplicates, longTitle

    var title: String {
        switch self {
        case .chrome3: "Chrome ×3"
        case .terminal2: "Terminal ×2"
        case .notes1: "Notes ×1 (no list)"
        case .minimized: "One minimized window"
        case .eleven: "Finder ×11 (+2 more)"
        case .untitledAndDuplicates: "Untitled + duplicate titles"
        case .longTitle: "Very long title"
        }
    }
}

/// Shows the dots and the window list over a stand-in switcher.
final class DesignPreview {
    static let shared = DesignPreview()

    func show(_ scenario: PreviewScenario) {}
    func close() {}
}
#endif
