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
    /// Ordered modes `attachStore(at:)` was called with (S2/S7's
    /// tearDown-then-attach path, distinct from `reconfigureCalls`).
    private(set) var attachCalls: [SyncMode] = []
    private var failOnAttachCall: Int?

    /// Ordered reset steps received, e.g. `["tearDown", "rebuild"]`.
    private(set) var resetSteps: [String] = []
    /// Quarantine descriptor `tearDownStore` should return (default nil,
    /// or a real copy when `storeURL` is set — see `setStoreURL`).
    private var backupToReturn: QuarantineManager.QuarantinedBackup?
    private var failRebuild = false
    /// Real on-disk URL this fake pretends to guard. When set (and a
    /// quarantine manager is passed to `tearDownStore`), `tearDownStore`
    /// performs a REAL `quarantine.copyStore(at:)` against it — mirroring
    /// `PersistenceHost`'s real closed-store-copy behavior — so S2/S7
    /// tests can prove the quarantine mechanics end-to-end without a live
    /// Core Data container.
    private var storeURL: URL?

    init(initialMode: SyncMode) {
        self.mode = initialMode
    }

    var currentMode: SyncMode { mode }

    /// Arm a throw on the Nth (1-based) `reconfigure` call.
    func failOnReconfigure(call n: Int) {
        failOnCall = n
    }

    /// Arm a throw on the Nth (1-based) `attachStore(at:)` call.
    func failOnAttachStore(call n: Int) {
        failOnAttachCall = n
    }

    /// Point this fake at a real on-disk file so `tearDownStore` can take
    /// a real quarantine copy of it (see `storeURL`'s doc comment).
    func setStoreURL(_ url: URL) {
        storeURL = url
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
        if let quarantine, let storeURL, FileManager.default.fileExists(atPath: storeURL.path) {
            return try quarantine.copyStore(at: storeURL)
        }
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

    func attachStore(at newMode: SyncMode) async throws {
        attachCalls.append(newMode)
        if let failOnAttachCall, attachCalls.count == failOnAttachCall {
            throw LillistError.storeUnavailable(reason: "fake attachStore failure on call \(failOnAttachCall)")
        }
        mode = newMode
    }
}
