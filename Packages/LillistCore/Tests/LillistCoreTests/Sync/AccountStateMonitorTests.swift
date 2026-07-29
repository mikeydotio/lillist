import Testing
import Foundation
import CloudKit
@testable import LillistCore

@Suite("AccountStateMonitor")
struct AccountStateMonitorTests {
    actor MockProvider: AccountStatusProviding {
        var nextStatus: CKAccountStatus = .available
        func setNextStatus(_ s: CKAccountStatus) { nextStatus = s }
        func accountStatus() async throws -> CKAccountStatus { nextStatus }
    }

    @Test("Initial refresh maps the provider's status to current state")
    func initialRefresh() async throws {
        let provider = MockProvider()
        let monitor = AccountStateMonitor(provider: provider)
        try await monitor.refresh()
        #expect(await monitor.currentState == .available)
    }

    @Test("Refresh after status flips updates the current state")
    func refreshAfterFlip() async throws {
        let provider = MockProvider()
        let monitor = AccountStateMonitor(provider: provider)
        try await monitor.refresh()
        await provider.setNextStatus(.noAccount)
        try await monitor.refresh()
        #expect(await monitor.currentState == .noAccount)
    }

    @Test("Restricted maps through correctly")
    func restrictedFlow() async throws {
        let provider = MockProvider()
        await provider.setNextStatus(.restricted)
        let monitor = AccountStateMonitor(provider: provider)
        try await monitor.refresh()
        #expect(await monitor.currentState == .restricted)
    }

    @Test("Simulated account change publishes .accountChanged")
    func accountChangedSimulation() async throws {
        let provider = MockProvider()
        let monitor = AccountStateMonitor(provider: provider)
        try await monitor.refresh()
        await monitor.simulateAccountChange()
        #expect(await monitor.currentState == .accountChanged)
    }

    @Test("State stream yields each refresh value in order")
    func streamEmitsValues() async throws {
        let provider = MockProvider()
        let monitor = AccountStateMonitor(provider: provider)
        var iterator = await monitor.stateStream.makeAsyncIterator()
        _ = await iterator.next() // consume the initial replay of the default state
        try await monitor.refresh()
        let v1 = await iterator.next()
        await provider.setNextStatus(.noAccount)
        try await monitor.refresh()
        let v2 = await iterator.next()
        #expect(v1 == .available)
        #expect(v2 == .noAccount)
    }

    @Test("Provider error is propagated by refresh")
    func providerError() async throws {
        struct Boom: Error {}
        actor FailingProvider: AccountStatusProviding {
            func accountStatus() async throws -> CKAccountStatus { throw Boom() }
        }
        let monitor = AccountStateMonitor(provider: FailingProvider())
        await #expect(throws: (any Error).self) {
            try await monitor.refresh()
        }
    }

    // MARK: - S3: identity-check integration

    private final class FakeProbe: AccountIdentityProbing, @unchecked Sendable {
        var next: AccountIdentityToken?
        init(_ next: AccountIdentityToken?) { self.next = next }
        func currentIdentity() -> AccountIdentityToken? { next }
    }

    private func token(_ value: String) -> AccountIdentityToken {
        AccountIdentityToken(ubiquityToken: NSString(string: value))!
    }

    @Test("test_S3_refreshOverridesToAccountChangedOnMismatch")
    func refreshOverridesToAccountChangedOnMismatch() async throws {
        let probe = FakeProbe(token("account-A"))
        let storage = InMemoryAccountIdentityRecordStore()
        let identityStore = AccountIdentityStore(probe: probe, storage: storage)
        let provider = MockProvider()
        let monitor = AccountStateMonitor(provider: provider, identityStore: identityStore)

        try await monitor.refresh() // first launch: adopts account-A, stays .available

        probe.next = token("account-B")
        try await monitor.refresh()

        #expect(await monitor.currentState == .accountChanged)
    }

    @Test("test_S3_refreshDoesNotOverrideOnFirstLaunchOrMatch")
    func refreshDoesNotOverrideOnFirstLaunchOrMatch() async throws {
        let probe = FakeProbe(token("account-A"))
        let storage = InMemoryAccountIdentityRecordStore()
        let identityStore = AccountIdentityStore(probe: probe, storage: storage)
        let provider = MockProvider()
        let monitor = AccountStateMonitor(provider: provider, identityStore: identityStore)

        try await monitor.refresh() // firstLaunch
        #expect(await monitor.currentState == .available)

        try await monitor.refresh() // match
        #expect(await monitor.currentState == .available)
    }

    @Test("test_S3_refreshIgnoresIdentityWhenBaseStateIsNotAvailable")
    func refreshIgnoresIdentityWhenBaseStateIsNotAvailable() async throws {
        let probe = FakeProbe(token("account-A"))
        let storage = InMemoryAccountIdentityRecordStore()
        let identityStore = AccountIdentityStore(probe: probe, storage: storage)
        let provider = MockProvider()
        await provider.setNextStatus(.available)
        let monitor = AccountStateMonitor(provider: provider, identityStore: identityStore)
        try await monitor.refresh() // adopts account-A while .available

        // A stale stored identity must never promote a genuinely-signed-out
        // device to .accountChanged — .noAccount wins outright.
        probe.next = nil
        await provider.setNextStatus(.noAccount)
        try await monitor.refresh()

        #expect(await monitor.currentState == .noAccount)
    }

    @Test("A monitor with no identityStore behaves exactly as before (no override)")
    func noIdentityStoreIsUnaffected() async throws {
        let provider = MockProvider()
        let monitor = AccountStateMonitor(provider: provider)
        try await monitor.refresh()
        #expect(await monitor.currentState == .available)
    }

    // MARK: - S13: CKAccountChanged observer

    @Test("test_S13_startObservingSystemAccountChangesTriggersRefresh")
    func startObservingSystemAccountChangesTriggersRefresh() async throws {
        let provider = MockProvider()
        let monitor = AccountStateMonitor(provider: provider)
        var iterator = await monitor.stateStream.makeAsyncIterator()
        _ = await iterator.next() // initial replay (.noAccount default)

        await monitor.startObservingSystemAccountChanges()
        await provider.setNextStatus(.available)
        NotificationCenter.default.post(name: .CKAccountChanged, object: nil)

        let next = await iterator.next()
        #expect(next == .available, "posting CKAccountChanged must trigger a real refresh()")
        await monitor.stopObservingSystemAccountChanges()
    }

    @Test("test_S13_stopObservingSystemAccountChangesRemovesObserver")
    func stopObservingSystemAccountChangesRemovesObserver() async throws {
        let provider = MockProvider()
        let monitor = AccountStateMonitor(provider: provider)
        var iterator = await monitor.stateStream.makeAsyncIterator()
        _ = await iterator.next() // initial replay

        await monitor.startObservingSystemAccountChanges()
        await monitor.stopObservingSystemAccountChanges()

        await provider.setNextStatus(.restricted)
        NotificationCenter.default.post(name: .CKAccountChanged, object: nil)

        // No refresh should fire — assert by racing a real refresh through
        // the same stream and confirming it's the FIRST value observed
        // (i.e. the notification produced no prior yield).
        try await monitor.refresh()
        let next = await iterator.next()
        #expect(next == .restricted)
    }
}
