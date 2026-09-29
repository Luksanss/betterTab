import Dispatch
import Foundation
import os

/// SIGTERM and SIGINT stop the tap, posting any owed ⌘ release, before BetterTab exits. They're
/// handled on their own queue, so this works even when the main thread is stuck. `kill -9` can't
/// be caught; one more ⌘ press and release recovers from that (acceptance test 14).
nonisolated enum TapSignals {
    static func install(tap: KeyTap) -> [any DispatchSourceSignal] {
        let queue = DispatchQueue(label: "com.luksanss.BetterTab.signals")
        return [SIGTERM, SIGINT].map { number in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler {
                TapLog.logger.notice("Signal \(number, privacy: .public): stopping the key tap")
                tap.stop()
                // Give the posted events and the log line a moment to leave the process.
                Thread.sleep(forTimeInterval: 0.1)
                exit(0)
            }
            source.resume()
            return source
        }
    }
}
