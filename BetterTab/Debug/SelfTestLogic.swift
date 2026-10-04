#if DEBUG
import Foundation

// The self-test's pure parts: options, target picking, Tab counting, the window filter and the
// report. Foundation only, so a scratch harness can compile this file on its own.

/// `--self-test [<report.json>] [--pause <seconds>]`.
nonisolated struct SelfTestOptions: Sendable, Equatable {
    static let defaultReportPath = "~/Library/Logs/BetterTab/self-test.json"
    /// Checkpoints can hold with ⌘ down, so they're kept short.
    static let maxPause: Double = 10

    var reportPath: String
    var pauseSeconds: Double = 0
    /// Launched with the argument: quit when done. From the menu: keep running.
    var quitWhenDone = true
    var trigger = "launch argument"

    static let fromMenu = SelfTestOptions(reportPath: defaultReportPath, quitWhenDone: false, trigger: "menu")

    init(reportPath: String, pauseSeconds: Double = 0, quitWhenDone: Bool = true, trigger: String = "launch argument") {
        self.reportPath = reportPath
        self.pauseSeconds = pauseSeconds
        self.quitWhenDone = quitWhenDone
        self.trigger = trigger
    }

    /// nil when `--self-test` is absent. A missing path means the default one.
    init?(arguments: [String]) {
        guard let flag = arguments.firstIndex(of: "--self-test") else { return nil }
        let next = arguments.index(after: flag)
        if next < arguments.endIndex, !arguments[next].hasPrefix("--") {
            reportPath = arguments[next]
        } else {
            reportPath = Self.defaultReportPath
        }
        if let pause = arguments.firstIndex(of: "--pause"), pause + 1 < arguments.endIndex,
           let seconds = Double(arguments[pause + 1]), seconds > 0 {
            pauseSeconds = min(seconds, Self.maxPause)
        }
    }

    /// Absolute, with `~` expanded; a relative path is taken from `directory`.
    func reportURL(relativeTo directory: String) -> URL {
        let expanded = (reportPath as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return URL(fileURLWithPath: expanded) }
        return URL(fileURLWithPath: directory).appendingPathComponent(expanded)
    }
}

/// One regular app, as target picking needs it.
nonisolated struct SelfTestCandidate: Sendable, Equatable {
    let pid: Int32
    let bundleID: String
    /// Real windows on every Space.
    let windows: Int
}

nonisolated struct SelfTestTargets: Sendable, Equatable {
    /// Where every scenario starts, and the app ⌘§ is tested on: the origin app.
    var home: Int32?
    /// Another app with two or more windows, the most of them.
    var multi: Int32?
    /// An app with exactly one window.
    var single: Int32?
    var notes: [String] = []
}

nonisolated enum SelfTestPlan {
    /// `origin` is the app in front when the run starts (nil if it isn't a regular app). It stays
    /// home, since the ⌘§ scenarios need home to have two or more windows and it's the app the
    /// maintainer set up for them.
    static func pickTargets(_ apps: [SelfTestCandidate], origin: Int32?) -> SelfTestTargets {
        let byWindows = apps.sorted { $0.windows != $1.windows ? $0.windows > $1.windows : $0.bundleID < $1.bundleID }
        let multis = byWindows.filter { $0.windows >= 2 }
        let singles = byWindows.filter { $0.windows == 1 }
        var targets = SelfTestTargets()
        var home = origin.flatMap { pid in apps.contains { $0.pid == pid } ? pid : nil }
        if home == nil {
            // Keep one single-window app free for its own scenario.
            home = multis.first?.pid
                ?? (singles.count >= 2 ? singles.last?.pid : nil)
                ?? byWindows.first { $0.windows == 0 }?.pid
                ?? singles.first?.pid
        }
        targets.home = home
        targets.multi = multis.first { $0.pid != home }?.pid
        targets.single = singles.first { $0.pid != home }?.pid
        if let home, let app = apps.first(where: { $0.pid == home }), app.windows < 2 {
            targets.notes.append("home has only \(app.windows) windows, so the ⌘§ scenarios are skipped")
        }
        return targets
    }

    /// Tabs that move the switcher's highlight from `selected` to `target` among `count` icons.
    static func tabs(from selected: Int, to target: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((target - selected) % count + count) % count
    }

    /// Real windows as SkyLight reports them: yabai's filter (src/space.c; MIT, (c) 2019 Åsmund
    /// Vikane), restricted to level 0. Attribute bit 0 needs Screen Recording, so it's ignored.
    static func isRealWindow(parent: UInt32, level: Int32, tags: UInt64, attributes: UInt64) -> Bool {
        guard parent == 0, level == 0 else { return false }
        guard tags & 0x1 != 0 || (tags & 0x2 != 0 && tags & 0x8000_0000 != 0) else { return false }
        return attributes & 0x2 != 0
            || tags & 0x0400_0000_0000_0000 != 0
            || ((attributes == 0 || attributes == 1)
                && (tags & minimizedTag != 0 || tags & 0x0300_0000_0000_0000 != 0))
    }

    static let minimizedTag: UInt64 = 1 << 60
    static let fullScreenTag: UInt64 = 1 << 42

    /// The number an icon's stack edges should show: its window count, with no ceiling, and none
    /// below two windows.
    static func expectedStackEdgeCount(windows: Int) -> Int? {
        windows >= 2 ? windows : nil
    }
}

// MARK: - The report

nonisolated struct SelfTestScenarioResult: Codable, Sendable, Equatable {
    let name: String
    let pass: Bool
    let skipped: Bool
    /// Measurements and reasons, never window titles.
    let detail: String
    /// The scenario's headline latency, when it has one.
    let ms: Int?
    let durationMs: Int
}

nonisolated struct SelfTestInventoryApp: Codable, Sendable, Equatable {
    let bundleID: String
    /// Real windows on every Space, from SkyLight.
    let windows: Int
    let minimized: Int
    let fullScreen: Int
    let offCurrentSpace: Int
    /// AX standard windows (the current Space only); nil when the app gave no answer.
    var axStandardWindows: Int?
}

nonisolated struct SelfTestTargetReport: Codable, Sendable, Equatable {
    let role: String
    let bundleID: String
    let windows: Int
}

nonisolated struct SelfTestReport: Codable, Sendable {
    struct Options: Codable, Sendable {
        var pauseSeconds: Double
        var trigger: String
    }

    struct Summary: Codable, Sendable, Equatable {
        var passed = 0
        var failed = 0
        var skipped = 0
    }

    /// "running", "pass", "fail", "inconclusive", or why the run stopped early.
    var result = "running"
    /// The one thing to read first, when there is one.
    var finding: String?
    var macOS: String
    var startedAt: String
    var finishedAt: String?
    var options: Options
    /// Set while `--pause` holds at a checkpoint.
    var checkpoint: String?
    var inventory: [SelfTestInventoryApp] = []
    var targets: [SelfTestTargetReport] = []
    var notes: [String] = []
    var scenarios: [SelfTestScenarioResult] = []
    var summary = Summary()

    mutating func add(_ scenario: SelfTestScenarioResult) {
        scenarios.append(scenario)
        summary = Self.summarize(scenarios)
    }

    static func summarize(_ scenarios: [SelfTestScenarioResult]) -> Summary {
        var summary = Summary()
        for scenario in scenarios {
            if scenario.skipped {
                summary.skipped += 1
            } else if scenario.pass {
                summary.passed += 1
            } else {
                summary.failed += 1
            }
        }
        return summary
    }

    static func overall(_ summary: Summary) -> String {
        if summary.failed > 0 { return "fail" }
        return summary.passed > 0 ? "pass" : "inconclusive"
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
#endif
