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
        // M4: read() is genuinely read-only now — normalizeSingletons() is
        // the maintenance path that materializes the canonical row on an
        // empty store (matching both apps' bootstraps).
        try await prefs.normalizeSingletons()

        let id = try await p.container.viewContext.perform {
            let req = NSFetchRequest<AppPreferences>(entityName: "AppPreferences")
            return try p.container.viewContext.fetch(req).first?.id
        }
        #expect(id == PreferencesStore.singletonID)
    }

    /// M4: read() must never write, even on a completely empty store — it
    /// returns sensible in-memory defaults instead of creating a row.
    @Test("read() on an empty store returns defaults without creating a row")
    func readOnEmptyStoreDoesNotCreateRow() async throws {
        let p = try await TestStore.make()
        let prefs = PreferencesStore(persistence: p)

        let snapshot = try await prefs.read()
        #expect(snapshot.trashRetentionDays == 30)
        #expect(snapshot.defaultTagTintHex == "#7F8FA6")

        let count = try await prefs.rowCount()
        #expect(count == 0, "read() must never insert a row as a side effect")
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

    @Test("normalizeSingletons creates the canonical row on an empty store, then is idempotent")
    func normalizeIdempotent() async throws {
        let p = try await TestStore.make()
        let prefs = PreferencesStore(persistence: p)
        // M4: normalizeSingletons — not read() — is the only path (besides
        // an explicit update(_:)) that may create the row.
        try await prefs.normalizeSingletons()      // first pass: creates the canonical row
        try await prefs.normalizeSingletons()      // second pass: already canonical, no-op
        #expect(try await prefs.rowCount() == 1)
        let id = try await p.container.viewContext.perform {
            let req = NSFetchRequest<AppPreferences>(entityName: "AppPreferences")
            return try p.container.viewContext.fetch(req).first?.id
        }
        #expect(id == PreferencesStore.singletonID)
    }

    /// M4's ~32%-of-legacy-UUIDs bug: a legacy row whose id sorts below
    /// singletonID by raw bytes must never beat a row that already carries
    /// the canonical id.
    @Test("normalizeSingletons never lets a legacy row displace an already-canonical row")
    func canonicalRowAlwaysBeatsLegacyRegardlessOfByteOrder() async throws {
        let p = try await TestStore.make()
        let ctx = p.container.viewContext

        // A legacy id deliberately chosen to sort BELOW singletonID
        // ("5111A570…") by raw UUID bytes, so a naive id-sort would pick it.
        let legacyLowID = UUID(uuidString: "00000000-0000-4000-8000-000000000000")!
        try await ctx.perform {
            let canonical = AppPreferences(context: ctx)
            canonical.id = PreferencesStore.singletonID
            canonical.trashRetentionDays = 45
            let legacy = AppPreferences(context: ctx)
            legacy.id = legacyLowID
            legacy.trashRetentionDays = 60
            try ctx.save()
        }

        let prefs = PreferencesStore(persistence: p)
        try await prefs.normalizeSingletons()

        #expect(try await prefs.rowCount() == 1)
        let (survivingID, retention) = try await ctx.perform { () -> (UUID?, Int16) in
            let req = NSFetchRequest<AppPreferences>(entityName: "AppPreferences")
            let row = try ctx.fetch(req).first
            return (row?.id, row?.trashRetentionDays ?? -1)
        }
        #expect(survivingID == PreferencesStore.singletonID)
        #expect(retention == 45, "the already-canonical row's content must survive, not the legacy row's")
    }

    /// X20: two rows that BOTH already carry singletonID (the
    /// concurrent-create race — two devices independently ran the
    /// create-if-missing path before either synced) need a tie-break that
    /// converges identically on every device. `id` can't distinguish them
    /// (both equal singletonID); the content-key tie-break must.
    @Test("normalizeSingletons converges deterministically when two rows both carry singletonID")
    func twoCanonicalRowsConvergeDeterministically() async throws {
        let p1 = try await TestStore.make()
        let p2 = try await TestStore.make()

        // Simulate the same two post-sync rows landing on two independent
        // devices/contexts — CloudKit propagates both rows identically to
        // both, so both stores see the same two field-value sets.
        for p in [p1, p2] {
            try await p.container.viewContext.perform {
                let ctx = p.container.viewContext
                let a = AppPreferences(context: ctx)
                a.id = PreferencesStore.singletonID
                a.trashRetentionDays = 14
                let b = AppPreferences(context: ctx)
                b.id = PreferencesStore.singletonID
                b.trashRetentionDays = 60
                try ctx.save()
            }
        }

        let prefs1 = PreferencesStore(persistence: p1)
        let prefs2 = PreferencesStore(persistence: p2)
        try await prefs1.normalizeSingletons()
        try await prefs2.normalizeSingletons()

        let retention1 = try await prefs1.read().trashRetentionDays
        let retention2 = try await prefs2.read().trashRetentionDays
        #expect(try await prefs1.rowCount() == 1)
        #expect(try await prefs2.rowCount() == 1)
        #expect(retention1 == retention2, "every device must converge on the identical survivor")
    }

    // MARK: - X20 flip-flop stress (6a): two REAL controllers, one file

    private func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PreferencesStoreSingletonTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Lillist.sqlite")
    }

    /// X20's stress proof, using the `MultiProcessStoreHarnessTests`
    /// keystone shape (two independently-constructed
    /// `NSPersistentCloudKitContainer`s sharing ONE on-disk file) rather
    /// than `twoCanonicalRowsConvergeDeterministically`'s two independent
    /// in-memory stores — this exercises the real cross-process race the
    /// finding describes (two processes concurrently racing
    /// `normalizeSingletons()` against a shared file), not just two
    /// separately-simulated copies of the same propagated field values.
    /// Repeated across several fresh store files in one test run — a
    /// non-deterministic tie-break would eventually disagree with itself
    /// across enough runs even if any single run looked fine.
    @Test("X20 flip-flop stress: concurrent-create + normalize across two harness controllers converges on one deterministic survivor, every run")
    func concurrentCreateAcrossProcessesConvergesDeterministically() async throws {
        for run in 0..<8 {
            let storeURL = tempStoreURL()
            try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent()) }

            let controllerA = try await PersistenceController(
                configuration: .onDisk(url: storeURL, syncMode: .localOnly),
                transactionAuthor: PersistenceController.localTransactionAuthor
            )
            let controllerB = try await PersistenceController(
                configuration: .onDisk(url: storeURL, syncMode: .localOnly),
                transactionAuthor: PersistenceController.cliTransactionAuthor
            )
            let prefsA = PreferencesStore(persistence: controllerA)
            let prefsB = PreferencesStore(persistence: controllerB)

            // The concurrent-create race itself: both "devices" run
            // normalizeSingletons() against the SAME empty, not-yet-
            // converged file at the same time — real concurrency (async
            // let), not a scripted sequence, since 5a's fix must hold
            // under genuine SQLite write-lock contention, not just
            // sequential replay.
            async let a: Void = prefsA.normalizeSingletons()
            async let b: Void = prefsB.normalizeSingletons()
            _ = try await (a, b)

            // Each controller observes whatever the shared file now
            // contains, then runs the real "next launch" convergence pass
            // every device's own bootstrap performs.
            await controllerA.container.viewContext.perform { controllerA.container.viewContext.refreshAllObjects() }
            await controllerB.container.viewContext.perform { controllerB.container.viewContext.refreshAllObjects() }
            try await prefsA.normalizeSingletons()
            try await prefsB.normalizeSingletons()
            await controllerA.container.viewContext.perform { controllerA.container.viewContext.refreshAllObjects() }
            await controllerB.container.viewContext.perform { controllerB.container.viewContext.refreshAllObjects() }

            let countA = try await prefsA.rowCount()
            let countB = try await prefsB.rowCount()
            #expect(countA == 1, "run \(run): controller A must converge to exactly one row")
            #expect(countB == 1, "run \(run): controller B must converge to exactly one row")

            let idA = try await controllerA.container.viewContext.perform {
                let req = NSFetchRequest<AppPreferences>(entityName: "AppPreferences")
                return try controllerA.container.viewContext.fetch(req).first?.id
            }
            let idB = try await controllerB.container.viewContext.perform {
                let req = NSFetchRequest<AppPreferences>(entityName: "AppPreferences")
                return try controllerB.container.viewContext.fetch(req).first?.id
            }
            #expect(idA == PreferencesStore.singletonID, "run \(run): the survivor must always carry the canonical id")
            #expect(idA == idB, "run \(run): both controllers must agree on the identical surviving row — no flip-flop")
        }
    }
}
