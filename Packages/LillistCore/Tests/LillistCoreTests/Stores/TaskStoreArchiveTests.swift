import Testing
import Foundation
@testable import LillistCore

@Suite("TaskStore archive")
struct TaskStoreArchiveTests {
    @Test("archive(ids:) sets archivedAt on closed tasks")
    func archiveSetsArchivedAt() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "Done")
        try await store.transition(id: id, to: .closed)

        let affected = try await store.archive(ids: [id])

        let record = try await store.fetch(id: id)
        #expect(record.archivedAt != nil)
        #expect(affected == [id])
    }

    @Test("archive(ids:) is idempotent — already-archived rows aren't re-touched")
    func archiveIdempotent() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "Done")
        try await store.transition(id: id, to: .closed)
        _ = try await store.archive(ids: [id])
        let firstArchivedAt = try #require(try await store.fetch(id: id).archivedAt)

        try await Task.sleep(nanoseconds: 10_000_000)
        let secondAffected = try await store.archive(ids: [id])

        #expect(secondAffected.isEmpty)
        let stillSame = try await store.fetch(id: id).archivedAt
        #expect(stillSame == firstArchivedAt)
    }

    @Test("archive(ids:) on a non-closed task still flips archivedAt — callers gate by status")
    func archiveDoesNotRequireClosedStatus() async throws {
        // The store doesn't enforce "must be closed" — that's a UI invariant.
        // Verifying the behavior keeps the contract explicit.
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "Open")

        let affected = try await store.archive(ids: [id])

        #expect(affected == [id])
        let record = try await store.fetch(id: id)
        #expect(record.archivedAt != nil)
        #expect(record.status == .todo)
    }

    @Test("unarchive(ids:) clears archivedAt")
    func unarchiveClears() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "Done")
        try await store.transition(id: id, to: .closed)
        _ = try await store.archive(ids: [id])

        try await store.unarchive(ids: [id])

        let record = try await store.fetch(id: id)
        #expect(record.archivedAt == nil)
    }

    @Test("archive(ids:) accepts a batch and returns only the actually-affected IDs")
    func archiveBatchPartial() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "A")
        let b = try await store.create(title: "B")
        let c = try await store.create(title: "C")
        try await store.transition(id: a, to: .closed)
        try await store.transition(id: b, to: .closed)
        try await store.transition(id: c, to: .closed)
        // Pre-archive `a` so it should be excluded from the next batch result.
        _ = try await store.archive(ids: [a])

        let affected = try await store.archive(ids: [a, b, c])

        #expect(Set(affected) == Set([b, c]))
    }

    @Test("Reopening an archived closed task auto-clears archivedAt")
    func reopenAutoUnarchives() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "T")
        try await store.transition(id: id, to: .closed)
        _ = try await store.archive(ids: [id])

        try await store.transition(id: id, to: .todo)

        let record = try await store.fetch(id: id)
        #expect(record.status == .todo)
        #expect(record.archivedAt == nil)
    }

    @Test("Closing a task does not auto-archive it")
    func closingDoesNotArchive() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "T")

        try await store.transition(id: id, to: .closed)

        let record = try await store.fetch(id: id)
        #expect(record.status == .closed)
        #expect(record.closedAt != nil)
        #expect(record.archivedAt == nil)
    }
}
