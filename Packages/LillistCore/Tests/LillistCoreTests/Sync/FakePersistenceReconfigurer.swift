import Foundation
@testable import LillistCore

/// In-memory `PersistenceReconfiguring` fake. Records the ordered
/// sequence of modes it was reconfigured to so executing tests can
/// assert phase ordering without a live `NSPersistentCloudKitContainer`.
/// Optionally throws on the Nth `reconfigure` to inject a failed swap.
actor FakePersistenceReconfigurer: PersistenceReconfiguring {
    private(set) var mode: SyncMode
    private(set) var reconfigureCalls: [SyncMode] = []
    private var failOnCall: Int?

    init(initialMode: SyncMode) {
        self.mode = initialMode
    }

    var currentMode: SyncMode { mode }

    /// Arm a throw on the Nth (1-based) `reconfigure` call.
    func failOnReconfigure(call n: Int) {
        failOnCall = n
    }

    func reconfigure(to newMode: SyncMode) async throws {
        reconfigureCalls.append(newMode)
        if let failOnCall, reconfigureCalls.count == failOnCall {
            throw LillistError.storeUnavailable(reason: "fake reconfigure failure on call \(failOnCall)")
        }
        mode = newMode
    }
}
