import XCTest
@testable import LillistUI
import LillistCore

/// Pins `ICloudSyncSettingsSection.divergenceWarning(mode:status:localCount:mirroredCount:)`
/// — the issue #54 guard for "sync claims to be active, but nothing is
/// actually mirrored." Exercises the full truth table: the warning must fire
/// for exactly one tuple shape and stay silent for every neighboring state
/// (paused, error, in-progress, pre-first-event, local-only, no local tasks,
/// partial mirroring, counts not yet loaded).
final class ICloudSyncDivergenceTests: XCTestCase {
    private func warning(
        mode: SyncMode = .iCloudSync,
        status: SyncIndicator,
        local: Int?,
        mirrored: Int?
    ) -> ICloudSyncSettingsSection.DivergenceWarning? {
        ICloudSyncSettingsSection.divergenceWarning(
            mode: mode, status: status, localCount: local, mirroredCount: mirrored
        )
    }

    // MARK: - The exact bug: fires

    func test_fires_whenActiveWithCompletedEvent_andNothingMirrored() {
        let result = warning(status: .idle(lastSync: Date()), local: 22, mirrored: 0)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.message.contains("22"))
        XCTAssertTrue(result!.message.lowercased().contains("environment"))
    }

    // MARK: - Healthy / partial: silent

    func test_silent_whenFullyMirrored() {
        XCTAssertNil(warning(status: .idle(lastSync: Date()), local: 22, mirrored: 22))
    }

    func test_silent_whenPartiallyMirrored_stillCatchingUp() {
        XCTAssertNil(warning(status: .idle(lastSync: Date()), local: 22, mirrored: 5))
    }

    func test_silent_whenNoLocalTasks() {
        XCTAssertNil(warning(status: .idle(lastSync: Date()), local: 0, mirrored: 0))
    }

    // MARK: - Pre-first-event window: silent (ambiguous, see statusLine doc)

    func test_silent_whenIdleWithNoTimestampYet() {
        XCTAssertNil(warning(status: .idle(lastSync: nil), local: 22, mirrored: 0))
    }

    // MARK: - Other statuses already surface their own signal: silent

    func test_silent_whenInProgress() {
        XCTAssertNil(warning(status: .inProgress, local: 22, mirrored: 0))
    }

    func test_silent_whenPaused() {
        XCTAssertNil(warning(status: .paused(reason: .noAccount), local: 22, mirrored: 0))
    }

    func test_silent_whenError() {
        XCTAssertNil(warning(status: .error(message: "boom", lastSuccess: nil), local: 22, mirrored: 0))
    }

    // MARK: - Local-only mode: 0 mirrored is expected, not an anomaly

    func test_silent_whenLocalOnly() {
        XCTAssertNil(warning(mode: .localOnly, status: .idle(lastSync: Date()), local: 22, mirrored: 0))
    }

    func test_silent_whenLocalOnly_evenWithActiveLookingStatus() {
        // A leaked/stale iCloud-mode status shouldn't matter once mode is local-only.
        XCTAssertNil(warning(mode: .localOnly, status: .idle(lastSync: Date()), local: 22, mirrored: 0))
    }

    // MARK: - Counts not yet loaded: silent (nothing to report yet)

    func test_silent_whenCountsNotYetLoaded() {
        XCTAssertNil(warning(status: .idle(lastSync: Date()), local: nil, mirrored: nil))
    }

    func test_silent_whenOnlyLocalCountLoaded() {
        XCTAssertNil(warning(status: .idle(lastSync: Date()), local: 22, mirrored: nil))
    }

    func test_silent_whenOnlyMirroredCountLoaded() {
        XCTAssertNil(warning(status: .idle(lastSync: Date()), local: nil, mirrored: 0))
    }
}
