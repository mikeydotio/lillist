import Testing
import CoreData
import Foundation
@testable import LillistCore

/// Data-sync-hardening `X11`.
@Suite("HistoryWatermarks")
struct HistoryWatermarksTests {
    private static func freshSuiteName() -> String {
        let suite = "HistoryWatermarksTests-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        return suite
    }

    /// A real Core Data history token — `PersistentHistoryTokenStore.lastToken`
    /// only accepts genuine `NSPersistentHistoryToken`s (archived via
    /// `NSKeyedArchiver`), so a placeholder value can't stand in for one.
    private func realToken() async throws -> NSPersistentHistoryToken {
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
        return try #require(token)
    }

    @Test("clearAll nils every one of the three PersistentHistoryTokenStore watermarks")
    func clearAllClearsAllThree() async throws {
        let suite = Self.freshSuiteName()
        let reconciler = PersistentHistoryTokenStore(suiteName: suite, key: PersistentHistoryTokenStore.defaultKey)
        let diagnostics = PersistentHistoryTokenStore(suiteName: suite, key: PersistentHistoryTokenStore.diagnosticsKey)
        let backup = PersistentHistoryTokenStore(suiteName: suite, key: PersistentHistoryTokenStore.backupKey)
        let token = try await realToken()
        reconciler.lastToken = token
        diagnostics.lastToken = token
        backup.lastToken = token
        let defaults = try #require(UserDefaults(suiteName: suite))

        let watermarks = HistoryWatermarks(
            reconciler: reconciler, diagnostics: diagnostics, backup: backup, prunerDefaults: defaults
        )
        watermarks.clearAll()

        #expect(reconciler.lastToken == nil)
        #expect(diagnostics.lastToken == nil)
        #expect(backup.lastToken == nil)
    }

    @Test("clearAll removes HistoryPruner's own bookkeeping key too")
    func clearAllRemovesPrunerKey() async throws {
        let suite = Self.freshSuiteName()
        let defaults = try #require(UserDefaults(suiteName: suite))
        let token = try await realToken()
        let archived = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        defaults.set(archived, forKey: HistoryPruner.tokenDefaultsKey)

        let watermarks = HistoryWatermarks(
            reconciler: PersistentHistoryTokenStore(suiteName: suite, key: PersistentHistoryTokenStore.defaultKey),
            diagnostics: PersistentHistoryTokenStore(suiteName: suite, key: PersistentHistoryTokenStore.diagnosticsKey),
            backup: PersistentHistoryTokenStore(suiteName: suite, key: PersistentHistoryTokenStore.backupKey),
            prunerDefaults: defaults
        )
        watermarks.clearAll()

        #expect(defaults.data(forKey: HistoryPruner.tokenDefaultsKey) == nil)
    }

    @Test("clearAll on already-empty watermarks is a harmless no-op")
    func clearAllOnEmptyIsNoop() throws {
        let suite = Self.freshSuiteName()
        let defaults = try #require(UserDefaults(suiteName: suite))
        let watermarks = HistoryWatermarks(
            reconciler: PersistentHistoryTokenStore(suiteName: suite, key: PersistentHistoryTokenStore.defaultKey),
            diagnostics: PersistentHistoryTokenStore(suiteName: suite, key: PersistentHistoryTokenStore.diagnosticsKey),
            backup: PersistentHistoryTokenStore(suiteName: suite, key: PersistentHistoryTokenStore.backupKey),
            prunerDefaults: defaults
        )

        watermarks.clearAll()

        #expect(defaults.data(forKey: HistoryPruner.tokenDefaultsKey) == nil)
    }
}
