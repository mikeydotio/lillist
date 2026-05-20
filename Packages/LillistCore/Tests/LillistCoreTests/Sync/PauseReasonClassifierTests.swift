import Testing
import Foundation
import CloudKit
@testable import LillistCore

@Suite("PauseReasonClassifier")
struct PauseReasonClassifierTests {
    private final class FakeAccountStatusProvider: AccountStatusProviding, @unchecked Sendable {
        var status: CKAccountStatus
        init(_ status: CKAccountStatus) { self.status = status }
        func accountStatus() async throws -> CKAccountStatus { status }
    }

    /// Builds a classifier with a primed `AccountStateMonitor` that
    /// reflects the given target state, plus a constant network
    /// reachability provider.
    private func makeClassifier(
        accountState: iCloudAccountState,
        reachable: Bool
    ) async -> PauseReasonClassifier {
        let ckStatus: CKAccountStatus
        switch accountState {
        case .available: ckStatus = .available
        case .noAccount: ckStatus = .noAccount
        case .restricted: ckStatus = .restricted
        case .accountChanged: ckStatus = .couldNotDetermine
        }
        let monitor = AccountStateMonitor(provider: FakeAccountStatusProvider(ckStatus))
        if accountState == .accountChanged {
            await monitor.simulateAccountChange()
        } else {
            try? await monitor.refresh()
        }
        return PauseReasonClassifier(
            accountMonitor: monitor,
            networkMonitor: ConstantNetworkReachability(reachable: reachable)
        )
    }

    @Test("Available + reachable → nil (active)")
    func availableActive() async {
        let c = await makeClassifier(accountState: .available, reachable: true)
        #expect(await c.currentReason() == nil)
    }

    @Test("Available + no network → .noNetwork")
    func availableOffline() async {
        let c = await makeClassifier(accountState: .available, reachable: false)
        #expect(await c.currentReason() == .noNetwork)
    }

    @Test("No account → .noAccount, regardless of network")
    func noAccount() async {
        for reachable in [true, false] {
            let c = await makeClassifier(accountState: .noAccount, reachable: reachable)
            #expect(await c.currentReason() == .noAccount)
        }
    }

    @Test("Restricted account → .restricted, regardless of network")
    func restricted() async {
        for reachable in [true, false] {
            let c = await makeClassifier(accountState: .restricted, reachable: reachable)
            #expect(await c.currentReason() == .restricted)
        }
    }

    @Test("Account changed → .accountChanged dominates everything else")
    func accountChangedWins() async {
        let c = await makeClassifier(accountState: .accountChanged, reachable: true)
        #expect(await c.currentReason() == .accountChanged)
    }

    @Test("iCloud Drive disabled wins over noNetwork but not over accountChanged")
    func iCloudDrivePriority() async {
        let withICloudOff = await makeClassifier(accountState: .available, reachable: false)
        await withICloudOff.setICloudDriveDisabled(true)
        #expect(await withICloudOff.currentReason() == .iCloudDriveDisabled)

        let withAccountChange = await makeClassifier(accountState: .accountChanged, reachable: false)
        await withAccountChange.setICloudDriveDisabled(true)
        #expect(await withAccountChange.currentReason() == .accountChanged)
    }
}
