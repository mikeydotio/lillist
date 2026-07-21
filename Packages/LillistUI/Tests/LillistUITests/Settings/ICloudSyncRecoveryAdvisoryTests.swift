import XCTest
@testable import LillistUI
import LillistCore

/// Pins `ICloudSyncSettingsSection.recoveryAdvisory(mode:status:localCount:mirroredCount:)`
/// — the issue #66 guidance-toward-recovery guard. Unlike `divergenceWarning`
/// (issue #54), this fires for *any* confirmed local/mirrored gap (not only
/// the exact `mirrored == 0` shape) and does not go silent once `status` has
/// escalated to `.error` — that's exactly when recovery guidance is most
/// useful. Exercises the full truth table.
final class ICloudSyncRecoveryAdvisoryTests: XCTestCase {
    private func advisory(
        mode: SyncMode = .iCloudSync,
        status: SyncIndicator,
        local: Int?,
        mirrored: Int?
    ) -> ICloudSyncSettingsSection.RecoveryAdvisory? {
        ICloudSyncSettingsSection.recoveryAdvisory(
            mode: mode, status: status, localCount: local, mirroredCount: mirrored
        )
    }

    // MARK: - Fires: any confirmed gap, idle or errored

    func test_fires_whenIdleWithNothingMirrored() {
        let result = advisory(status: .idle(lastSync: Date()), local: 25, mirrored: 0)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.message.contains("25"))
    }

    func test_fires_whenIdleWithPartialMirroring() {
        // Unlike divergenceWarning, a partial gap is NOT excused as "still
        // catching up" here — recovery guidance is still useful information,
        // just less urgent than the exact-zero case.
        let result = advisory(status: .idle(lastSync: Date()), local: 22, mirrored: 5)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.message.contains("17"), "should report the gap (22-5=17)")
    }

    func test_fires_whenStatusHasEscalatedToError() {
        // This is the SyncStatusMonitor .syncStalled scenario (issue #66):
        // divergenceWarning goes silent here (the badge already speaks for
        // itself), but recovery guidance is exactly what's needed now.
        let result = advisory(
            status: .error(message: "Sync stuck — 3 export attempts in a row failed.", lastSuccess: nil),
            local: 25, mirrored: 0
        )
        XCTAssertNotNil(result)
    }

    // MARK: - Message content: no one-click destructive action, no guessed direction

    func test_message_doesNotClaimASpecificSafeDirection() {
        // The two real #66 devices had the IDENTICAL mirror-count shape
        // (mirrored == 0) despite needing OPPOSITE recovery actions — the
        // function must not silently pick one.
        let result = advisory(status: .idle(lastSync: Date()), local: 25, mirrored: 0)
        XCTAssertNotNil(result)
        let message = result!.message.lowercased()
        XCTAssertTrue(message.contains("back up"), "must recommend backing up first")
        XCTAssertTrue(message.contains("reset") || message.contains("reload"), "must point at the Reset tools")
    }

    // MARK: - Healthy: silent

    func test_silent_whenFullyMirrored() {
        XCTAssertNil(advisory(status: .idle(lastSync: Date()), local: 22, mirrored: 22))
    }

    func test_silent_whenNoLocalTasks() {
        XCTAssertNil(advisory(status: .idle(lastSync: Date()), local: 0, mirrored: 0))
    }

    // MARK: - Pre-first-event window: silent (ambiguous, matches statusLine's doc)

    func test_silent_whenIdleWithNoTimestampYet() {
        XCTAssertNil(advisory(status: .idle(lastSync: nil), local: 25, mirrored: 0))
    }

    // MARK: - Statuses where recovery guidance doesn't apply: silent

    func test_silent_whenInProgress() {
        XCTAssertNil(advisory(status: .inProgress, local: 25, mirrored: 0))
    }

    func test_silent_whenPaused() {
        // A paused (account/network) condition needs its own fix — Reset
        // tools wouldn't help and would be confusing guidance here.
        XCTAssertNil(advisory(status: .paused(reason: .noAccount), local: 25, mirrored: 0))
    }

    // MARK: - Local-only mode: no iCloud gap to recover

    func test_silent_whenLocalOnly() {
        XCTAssertNil(advisory(mode: .localOnly, status: .idle(lastSync: Date()), local: 25, mirrored: 0))
    }

    // MARK: - Counts not yet loaded: silent

    func test_silent_whenCountsNotYetLoaded() {
        XCTAssertNil(advisory(status: .idle(lastSync: Date()), local: nil, mirrored: nil))
    }

    func test_silent_whenOnlyLocalCountLoaded() {
        XCTAssertNil(advisory(status: .idle(lastSync: Date()), local: 25, mirrored: nil))
    }

    func test_silent_whenOnlyMirroredCountLoaded() {
        XCTAssertNil(advisory(status: .idle(lastSync: Date()), local: nil, mirrored: 0))
    }
}
