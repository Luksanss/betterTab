import Dispatch
import os

// Everything here is read from the tap thread, so it has to be nonisolated.

nonisolated enum Log {
    static let subsystem = "com.luksanss.BetterTab.Experiment"
    static let perm = Logger(subsystem: subsystem, category: "perm")
    static let tap = Logger(subsystem: subsystem, category: "tap")
    static let state = Logger(subsystem: subsystem, category: "state")
    static let post = Logger(subsystem: subsystem, category: "post")
    static let ax = Logger(subsystem: subsystem, category: "ax")
    static let win = Logger(subsystem: subsystem, category: "win")
    static let panel = Logger(subsystem: subsystem, category: "panel")
    static let app = Logger(subsystem: subsystem, category: "app")
}

/// Virtual key codes (Carbon `kVK_*`), kept here so the tap never touches Carbon.
nonisolated enum KeyCode {
    static let tab: Int64 = 48
    static let returnKey: Int64 = 36
    static let keypadEnter: Int64 = 76
    static let escape: Int64 = 53
    static let command: Int64 = 55
    static let rightCommand: Int64 = 54
}

nonisolated enum Timing {
    /// Long enough to observe test 0a's 15 s, short enough that a stuck hold ends by itself.
    static let holdSafetyTimeout: Double = 30
    static let axMessagingTimeout: Float = 0.25
    static let appearancePollInterval = 50  // ms
    static let appearancePollWindow: UInt64 = 1_000_000_000  // ns
    static let heartbeatInterval: Double = 5
    static let selectionCheckDelay = 150  // ms after a Tab, to let the Dock move its highlight
}

nonisolated func seconds(_ nanos: UInt64) -> Double { Double(nanos) / 1e9 }
nonisolated func uptimeNanos() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
nonisolated func hex(_ value: UInt64) -> String { "0x" + String(value, radix: 16) }
