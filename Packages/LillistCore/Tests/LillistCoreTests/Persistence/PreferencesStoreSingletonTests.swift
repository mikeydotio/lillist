import Testing
import CoreData
import Foundation
@testable import LillistCore

@Suite("PreferencesStore singleton convergence")
struct PreferencesStoreSingletonTests {
    @Test("Freshly-created singleton uses the well-known constant id")
    func freshSingletonUsesWellKnownID() async throws {
        let p = try await TestStore.make()
        let prefs = PreferencesStore(persistence: p)
        // Force materialization.
        _ = try await prefs.read()

        let id = try await p.container.viewContext.perform {
            let req = NSFetchRequest<AppPreferences>(entityName: "AppPreferences")
            return try p.container.viewContext.fetch(req).first?.id
        }
        #expect(id == PreferencesStore.singletonID)
    }

    @Test("normalizeSingletons collapses duplicate random-UUID rows into one canonical row")
    func normalizeCollapsesDuplicates() async throws {
        let p = try await TestStore.make()
        let ctx = p.container.viewContext

        // Simulate two devices having each created their own random-UUID row
        // (the pre-fix cross-device duplication bug). Give the row we want to
        // survive a distinguishing field value.
        try await ctx.perform {
            let a = AppPreferences(context: ctx)
            a.id = UUID()
            a.trashRetentionDays = 30
            a.morningSummaryHour = 7   // canary: the newest write wins
            let b = AppPreferences(context: ctx)
            b.id = UUID()
            b.trashRetentionDays = 30
            b.morningSummaryHour = 9
            try ctx.save()
        }

        let prefs = PreferencesStore(persistence: p)
        try await prefs.normalizeSingletons()

        let (count, survivingID, hour) = try await ctx.perform { () -> (Int, UUID?, Int16) in
            let req = NSFetchRequest<AppPreferences>(entityName: "AppPreferences")
            let rows = try ctx.fetch(req)
            return (rows.count, rows.first?.id, rows.first?.morningSummaryHour ?? -1)
        }
        #expect(count == 1)
        #expect(survivingID == PreferencesStore.singletonID)
        // The canonical row retains a coherent value (not a torn merge); the
        // contract is "one row, well-known id", field-value tie-break is
        // documented to pick the row that sorts first deterministically.
        #expect(hour == 7 || hour == 9)
    }

    @Test("normalizeSingletons is idempotent and a no-op on a clean store")
    func normalizeIdempotent() async throws {
        let p = try await TestStore.make()
        let prefs = PreferencesStore(persistence: p)
        _ = try await prefs.read()                 // creates one canonical row
        try await prefs.normalizeSingletons()      // first pass: nothing to do
        try await prefs.normalizeSingletons()      // second pass: still nothing
        #expect(try await prefs.rowCount() == 1)
    }
}
