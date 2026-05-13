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
}
