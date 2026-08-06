import Foundation
import os

/// Lightweight cold-start timing for Console / Instruments (point 3).
/// Never blocks the UI; records phase durations only.
enum LaunchProfiler {
    private static let logger = Logger(
        subsystem: "com.asignaciondelcielo.espada37swift",
        category: "ColdStart"
    )

    private static var t0: CFAbsoluteTime?
    private static var last: CFAbsoluteTime?
    private static var marks: [(String, Double)] = []
    private static let lock = NSLock()

    /// Call once at the very start of the launch task.
    static func begin() {
        lock.lock()
        let now = CFAbsoluteTimeGetCurrent()
        t0 = now
        last = now
        marks = []
        lock.unlock()
        logger.info("ColdStart begin")
    }

    /// Record a named phase (ms since previous mark and since start).
    static func mark(_ name: String) {
        lock.lock()
        let now = CFAbsoluteTimeGetCurrent()
        let fromStartMs = ((t0.map { now - $0 }) ?? 0) * 1000
        let fromLastMs = ((last.map { now - $0 }) ?? 0) * 1000
        last = now
        marks.append((name, fromStartMs))
        lock.unlock()
        logger.info("Phase \(name, privacy: .public) +\(Int(fromLastMs))ms (total \(Int(fromStartMs))ms)")
        #if DEBUG
        print("[ColdStart] \(name) +\(Int(fromLastMs))ms (total \(Int(fromStartMs))ms)")
        #endif
    }

    static func end() {
        mark("ready")
        lock.lock()
        let summary = marks.map { "\($0.0)=\(Int($0.1))ms" }.joined(separator: " · ")
        lock.unlock()
        logger.info("ColdStart summary: \(summary, privacy: .public)")
        #if DEBUG
        print("[ColdStart] DONE \(summary)")
        #endif
    }

    /// Snapshot for tests / debug UI.
    static var phaseMilliseconds: [(String, Double)] {
        lock.lock(); defer { lock.unlock() }
        return marks
    }
}
