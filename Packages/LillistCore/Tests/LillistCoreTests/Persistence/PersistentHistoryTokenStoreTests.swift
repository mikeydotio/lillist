import Testing
import CoreData
import Foundation
@testable import LillistCore

@Suite("PersistentHistoryTokenStore")
struct PersistentHistoryTokenStoreTests {
    private static func freshSuiteName() -> String {
        let suite = "PersistentHistoryTokenStoreTests-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        return suite
    }

    @Test("No token persisted on a fresh store")
    func freshStoreHasNoToken() {
        let store = PersistentHistoryTokenStore(suiteName: Self.freshSuiteName())
        #expect(store.lastToken == nil)
    }

    @Test("A token round-trips through archive/unarchive")
    func tokenRoundTrips() async throws {
        // Drive a real write so Core Data hands us a genuine history token.
        let p = try await TestStore.make()
        let ctx = p.container.viewContext
        let token: NSPersistentHistoryToken? = try await ctx.perform {
            let t = LillistTask(context: ctx)
            t.id = UUID()
            t.title = "T"
            try ctx.save()
            let req = NSPersistentHistoryChangeRequest.fetchHistory(after: nil as NSPersistentHistoryToken?)
            let result = try ctx.execute(req) as? NSPersistentHistoryResult
            let txns = result?.result as? [NSPersistentHistoryTransaction]
            return txns?.last?.token
        }
        let real = try #require(token)

        let suite = Self.freshSuiteName()
        let a = PersistentHistoryTokenStore(suiteName: suite)
        a.lastToken = real
        let b = PersistentHistoryTokenStore(suiteName: suite)
        #expect(b.lastToken == real)
    }

    @Test("Setting nil clears the persisted token")
    func clearingToken() async throws {
        let p = try await TestStore.make()
        let ctx = p.container.viewContext
        let token: NSPersistentHistoryToken? = try await ctx.perform {
            let t = LillistTask(context: ctx)
            t.id = UUID()
            t.title = "T"
            try ctx.save()
            let req = NSPersistentHistoryChangeRequest.fetchHistory(after: nil as NSPersistentHistoryToken?)
            let result = try ctx.execute(req) as? NSPersistentHistoryResult
            return (result?.result as? [NSPersistentHistoryTransaction])?.last?.token
        }
        let suite = Self.freshSuiteName()
        let store = PersistentHistoryTokenStore(suiteName: suite)
        store.lastToken = token
        store.lastToken = nil
        let reopened = PersistentHistoryTokenStore(suiteName: suite)
        #expect(reopened.lastToken == nil)
    }
}
