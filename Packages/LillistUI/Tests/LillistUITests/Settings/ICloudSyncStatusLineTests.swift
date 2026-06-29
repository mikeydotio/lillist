import XCTest
@testable import LillistUI
import LillistCore

/// Pins the iCloud-sync settings row subtitle (`ICloudSyncSettingsSection`).
///
/// Regression guard for the "toggle ON but subtitle says Off" bug: the subtitle
/// is mode-aware, not status-only. `.idle(lastSync: nil)` is ambiguous — it
/// happens both in local-only mode and in iCloud-sync mode before the first
/// CloudKit event of the session lands — so the copy must branch on `mode`.
final class ICloudSyncStatusLineTests: XCTestCase {
    // The exact bug: iCloud sync ON, no sync event observed yet this session.
    // Must NOT claim "Off".
    func test_iCloudSync_idle_noTimestamp_says_on_not_off() {
        let line = ICloudSyncSettingsSection.statusLine(
            mode: .iCloudSync,
            status: .idle(lastSync: nil),
            relativeSync: nil
        )
        XCTAssertEqual(line, "On — sync is active")
        XCTAssertFalse(line.contains("Off"))
    }

    func test_localOnly_idle_noTimestamp_says_off() {
        let line = ICloudSyncSettingsSection.statusLine(
            mode: .localOnly,
            status: .idle(lastSync: nil),
            relativeSync: nil
        )
        XCTAssertEqual(line, "Off — your data stays on this device")
    }

    // Local-only wins regardless of any leaked status — "Off" stays truthful.
    func test_localOnly_ignores_status() {
        for status: SyncIndicator in [.idle(lastSync: Date()), .inProgress, .paused(reason: .unknown)] {
            XCTAssertEqual(
                ICloudSyncSettingsSection.statusLine(mode: .localOnly, status: status, relativeSync: "5 minutes ago"),
                "Off — your data stays on this device"
            )
        }
    }

    func test_iCloudSync_idle_withTimestamp_shows_synced_relative() {
        let line = ICloudSyncSettingsSection.statusLine(
            mode: .iCloudSync,
            status: .idle(lastSync: Date()),
            relativeSync: "2 minutes ago"
        )
        XCTAssertEqual(line, "Synced 2 minutes ago")
    }

    func test_iCloudSync_inProgress() {
        XCTAssertEqual(
            ICloudSyncSettingsSection.statusLine(mode: .iCloudSync, status: .inProgress, relativeSync: nil),
            "Syncing…"
        )
    }

    func test_iCloudSync_error_surfaces_message() {
        let line = ICloudSyncSettingsSection.statusLine(
            mode: .iCloudSync,
            status: .error(message: "boom", lastSuccess: nil),
            relativeSync: nil
        )
        XCTAssertEqual(line, "Sync error: boom")
    }

    func test_iCloudSync_paused() {
        XCTAssertEqual(
            ICloudSyncSettingsSection.statusLine(mode: .iCloudSync, status: .paused(reason: .unknown), relativeSync: nil),
            "Sync paused — iCloud unavailable"
        )
    }
}
