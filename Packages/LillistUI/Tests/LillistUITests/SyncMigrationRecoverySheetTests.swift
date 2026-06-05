import Testing
import Foundation
@testable import LillistUI
import LillistCore

@Suite("SyncMigrationRecoverySheet detail copy")
struct SyncMigrationRecoverySheetTests {
    @Test("Detail mentions freeing space when the failure was a disk shortfall")
    func diskShortfallDetail() {
        let journal = MigrationJournal(
            state: .failed,
            operation: .replaceICloudWithLocal,
            previousMode: .localOnly,
            failureReason: "insufficientDiskSpace(neededBytes: 8192, availableBytes: 100)"
        )
        let detail = SyncMigrationRecoverySheet.detailText(for: journal)
        #expect(detail.localizedCaseInsensitiveContains("space"))
    }

    @Test("Detail falls back to the operation narrative for non-disk failures")
    func genericDetail() {
        let journal = MigrationJournal(
            state: .failed,
            operation: .replaceICloudWithLocal,
            previousMode: .localOnly,
            failureReason: "syncFailure(underlying: \"network\")"
        )
        let detail = SyncMigrationRecoverySheet.detailText(for: journal)
        #expect(detail.localizedCaseInsensitiveContains("replacing iCloud"))
    }
}
