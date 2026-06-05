import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge destructive batch atomicity")
struct BatchAtomicityTests {
    /// Mirrors DeleteCommand.run's resolve-then-mutate shape with no stdin.
    private func deleteBatch(_ tokens: [String], persistence: PersistenceController) async throws {
        let resolutions = try await CLIBridge.Resolver.resolveAll(
            tokens: tokens,
            scope: .anywhereIncludingClosed,
            destructiveness: .destructive,
            persistence: persistence
        )
        let store = TaskStore(persistence: persistence)
        for r in resolutions {
            try await store.softDelete(id: r.id)
        }
    }

    @Test("A delete batch with one bad token deletes nothing")
    func deleteBatchAtomic() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "Alpha")
        let b = try await store.create(title: "Beta")
        await #expect(throws: LillistError.notFound) {
            try await deleteBatch(
                [a.uuidString, "00000000-0000-0000-0000-0000000000ff", b.uuidString],
                persistence: p
            )
        }
        // Neither task should be trashed: the bad token aborts before mutation.
        let trashed = try await store.trashed()
        #expect(trashed.isEmpty)
    }

    @Test("A purge batch with one bad token purges nothing")
    func purgeBatchAtomic() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "Alpha")
        let b = try await store.create(title: "Beta")
        let resolutionsThrew: Bool
        do {
            let resolutions = try await CLIBridge.Resolver.resolveAll(
                tokens: [a.uuidString, "deadbeef-0000-0000-0000-000000000000", b.uuidString],
                scope: .anywhereIncludingClosed,
                destructiveness: .destructive,
                persistence: p
            )
            for r in resolutions { try await store.hardDelete(id: r.id) }
            resolutionsThrew = false
        } catch {
            resolutionsThrew = true
        }
        #expect(resolutionsThrew)
        // Both tasks still fetchable: nothing was hard-deleted.
        let recA = try await store.fetch(id: a)
        let recB = try await store.fetch(id: b)
        #expect(recA.id == a)
        #expect(recB.id == b)
    }

    @Test("A status->closed batch with one bad token closes nothing")
    func statusClosedBatchAtomic() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "Alpha")
        let b = try await store.create(title: "Beta")
        await #expect(throws: LillistError.notFound) {
            let resolutions = try await CLIBridge.Resolver.resolveAll(
                tokens: [a.uuidString, "00000000-0000-0000-0000-0000000000ff", b.uuidString],
                scope: .anywhereIncludingClosed,
                destructiveness: .destructive,
                persistence: p
            )
            for r in resolutions { try await store.transition(id: r.id, to: .closed) }
        }
        let recA = try await store.fetch(id: a)
        let recB = try await store.fetch(id: b)
        #expect(recA.status != .closed)
        #expect(recB.status != .closed)
    }

    @Test("RestoreHandler.preflight throws on a non-trashed token so a restore batch aborts whole")
    func restorePreflightAtomic() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "Alpha")
        try await store.softDelete(id: a)
        let b = try await store.create(title: "Beta") // never trashed
        let trashed = try await store.trashed()
        // a resolves; b does not -> preflight throws before any restore.
        #expect(throws: LillistError.notFound) {
            try CLIBridge.RestoreHandler.preflight(token: b.uuidString, trashed: trashed)
        }
        // Sanity: a really is restorable.
        try CLIBridge.RestoreHandler.preflight(token: a.uuidString, trashed: trashed)
    }
}
