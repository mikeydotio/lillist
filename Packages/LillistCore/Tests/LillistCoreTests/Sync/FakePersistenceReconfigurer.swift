import Foundation
@testable import LillistCore

/// In-memory `PersistenceReconfiguring` + `PersistenceResetting` fake.
/// Records the ordered sequence of modes it was reconfigured to (and the
/// reset steps it received) so executing tests can assert phase ordering
/// without a live `NSPersistentCloudKitContainer`. Optionally throws on
/// the Nth `reconfigure` to inject a failed swap, or on the next
/// `rebuildEmptyStore` to exercise the reset rollback path.
actor FakePersistenceReconfigurer: PersistenceReconfiguring, PersistenceResetting {
    private(set) var mode: SyncMode
    private(set) var reconfigureCalls: [SyncMode] = []
    private var failOnCall: Int?

    /// Ordered reset steps received, e.g. `["tearDown", "rebuild"]`.
    private(set) var resetSteps: [String] = []
    /// Quarantine descriptor `tearDownStore` should return (default nil).
    private var backupToReturn: QuarantineManager.QuarantinedBackup?
    private var failRebuild = false

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

    // MARK: PersistenceResetting

    /// Arm a throw on the next `rebuildEmptyStore` call.
    func failOnRebuild() { failRebuild = true }

    func tearDownStore(backupVia quarantine: QuarantineManager?) async throws -> QuarantineManager.QuarantinedBackup? {
        resetSteps.append("tearDown")
        return backupToReturn
    }

    func rebuildEmptyStore() async throws {
        resetSteps.append("rebuild")
        if failRebuild {
            throw LillistError.storeUnavailable(reason: "fake rebuild failure")
        }
    }

    func reattachStore() async throws {
        resetSteps.append("reattach")
    }
}
