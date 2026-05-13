import Testing
import CloudKit
@testable import LillistCore

@Suite("iCloudAccountState")
struct iCloudAccountStateTests {
    @Test("Maps CKAccountStatus.available to .available")
    func mapsAvailable() {
        #expect(iCloudAccountState.from(ckAccountStatus: .available) == .available)
    }

    @Test("Maps CKAccountStatus.noAccount to .noAccount")
    func mapsNoAccount() {
        #expect(iCloudAccountState.from(ckAccountStatus: .noAccount) == .noAccount)
    }

    @Test("Maps CKAccountStatus.restricted to .restricted")
    func mapsRestricted() {
        #expect(iCloudAccountState.from(ckAccountStatus: .restricted) == .restricted)
    }

    @Test("Maps CKAccountStatus.couldNotDetermine to .noAccount (safest default)")
    func mapsCouldNotDetermine() {
        #expect(iCloudAccountState.from(ckAccountStatus: .couldNotDetermine) == .noAccount)
    }

    @Test("Maps CKAccountStatus.temporarilyUnavailable to .restricted")
    func mapsTemporarilyUnavailable() {
        #expect(iCloudAccountState.from(ckAccountStatus: .temporarilyUnavailable) == .restricted)
    }

    @Test("All four cases distinct")
    func distinctCases() {
        let all: Set<iCloudAccountState> = [.available, .noAccount, .restricted, .accountChanged]
        #expect(all.count == 4)
    }
}
