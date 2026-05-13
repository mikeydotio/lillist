import Testing
import Foundation
@testable import LillistCore

@Suite("PreferencesStore")
struct PreferencesStoreTests {
    @Test("Defaults on first read")
    func defaults() async throws {
        let p = try await TestStore.make()
        let store = PreferencesStore(persistence: p)
        let prefs = try await store.read()
        #expect(prefs.trashRetentionDays == 30)
        #expect(prefs.defaultAllDayHour == 9)
        #expect(prefs.defaultAllDayMinute == 0)
        #expect(prefs.morningSummaryEnabled == true)
    }

    @Test("Update persists across reads")
    func updatePersists() async throws {
        let p = try await TestStore.make()
        let store = PreferencesStore(persistence: p)
        try await store.update { $0.trashRetentionDays = 60 }
        let prefs = try await store.read()
        #expect(prefs.trashRetentionDays == 60)
    }

    @Test("Update is idempotent — single singleton row")
    func singletonRow() async throws {
        let p = try await TestStore.make()
        let store = PreferencesStore(persistence: p)
        try await store.update { $0.trashRetentionDays = 60 }
        try await store.update { $0.trashRetentionDays = 90 }
        #expect(try await store.rowCount() == 1)
    }
}
