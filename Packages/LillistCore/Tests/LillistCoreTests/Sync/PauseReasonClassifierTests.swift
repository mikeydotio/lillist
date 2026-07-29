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

    /// `S24`: fake `AccountIdentityProbing` so `currentReason()`'s
    /// `.iCloudDriveDisabled` branch can be driven directly — mirrors the
    /// probe fakes already used in `AccountIdentityStoreTests`/
    /// `AccountStateMonitorTests`.
    private final class FakeIdentityProbe: AccountIdentityProbing, @unchecked Sendable {
        var next: AccountIdentityToken?
        init(_ next: AccountIdentityToken?) { self.next = next }
        func currentIdentity() -> AccountIdentityToken? { next }
    }

    private func someToken() -> AccountIdentityToken {
        AccountIdentityToken(ubiquityToken: NSString(string: "account-A"))!
    }

    /// Builds a classifier with a primed `AccountStateMonitor` that
    /// reflects the given target state, plus a constant network
    /// reachability provider and (by default) a non-nil identity token —
    /// i.e. iCloud Drive access present, matching the common case.
    /// - Parameter identityToken: explicit — pass `someToken()` for "iCloud
    ///   Drive access present" (the common case in tests unrelated to
    ///   `S24`) or `nil` for "disabled." No default: an implicit default
    ///   of `nil` would make it impossible for a caller to distinguish
    ///   "didn't specify" from "explicitly disabled" via `??`, which is
    ///   exactly the bug that shape produced during development of this
    ///   test file — every call site must say what it means.
    private func makeClassifier(
        accountState: iCloudAccountState,
        reachable: Bool,
        identityToken: AccountIdentityToken?
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
            networkMonitor: ConstantNetworkReachability(reachable: reachable),
            identityProbe: FakeIdentityProbe(identityToken)
        )
    }

    @Test("Available + reachable → nil (active)")
    func availableActive() async {
        let c = await makeClassifier(accountState: .available, reachable: true, identityToken: someToken())
        #expect(await c.currentReason() == nil)
    }

    @Test("Available + no network → .noNetwork")
    func availableOffline() async {
        let c = await makeClassifier(accountState: .available, reachable: false, identityToken: someToken())
        #expect(await c.currentReason() == .noNetwork)
    }

    @Test("No account → .noAccount, regardless of network")
    func noAccount() async {
        for reachable in [true, false] {
            let c = await makeClassifier(accountState: .noAccount, reachable: reachable, identityToken: someToken())
            #expect(await c.currentReason() == .noAccount)
        }
    }

    @Test("Restricted account → .restricted, regardless of network")
    func restricted() async {
        for reachable in [true, false] {
            let c = await makeClassifier(accountState: .restricted, reachable: reachable, identityToken: someToken())
            #expect(await c.currentReason() == .restricted)
        }
    }

    @Test("Account changed → .accountChanged dominates everything else")
    func accountChangedWins() async {
        let c = await makeClassifier(accountState: .accountChanged, reachable: true, identityToken: someToken())
        #expect(await c.currentReason() == .accountChanged)
    }

    // MARK: - S24: real iCloud-Drive-disabled signal via AccountIdentityProbing

    @Test("test_S24_iCloudDriveDisabledWhenTokenNilButAccountAvailable")
    func iCloudDriveDisabledWhenTokenNilButAccountAvailable() async {
        let c = await makeClassifier(accountState: .available, reachable: true, identityToken: nil)
        #expect(await c.currentReason() == .iCloudDriveDisabled)
    }

    @Test("test_S24_iCloudDriveEnabledWhenTokenPresent")
    func iCloudDriveEnabledWhenTokenPresent() async {
        let c = await makeClassifier(accountState: .available, reachable: true, identityToken: someToken())
        #expect(await c.currentReason() == nil)
    }

    @Test("iCloud Drive disabled wins over noNetwork but not over accountChanged")
    func iCloudDrivePriority() async {
        let withICloudOff = await makeClassifier(accountState: .available, reachable: false, identityToken: nil)
        #expect(await withICloudOff.currentReason() == .iCloudDriveDisabled)

        let withAccountChange = await makeClassifier(accountState: .accountChanged, reachable: false, identityToken: nil)
        #expect(await withAccountChange.currentReason() == .accountChanged)
    }

    @Test("A nil identity token on a non-available account state is irrelevant — the base state still wins")
    func nilTokenIrrelevantWhenNotAvailable() async {
        let c = await makeClassifier(accountState: .noAccount, reachable: true, identityToken: nil)
        #expect(await c.currentReason() == .noAccount)
    }
}
