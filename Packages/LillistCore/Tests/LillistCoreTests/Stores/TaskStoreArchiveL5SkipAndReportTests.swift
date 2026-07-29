import Testing
import Foundation
@testable import LillistCore

/// L5: `archive`/`unarchive` used to fail the WHOLE batch the moment one id
/// was missing — `fetchManagedObject`'s `.notFound` throw propagated out of
/// the loop, and (pre-`withMutationRollback`) rolled back everything
/// already flipped earlier in the same loop, since the throw happened
/// before `context.save()`. The fix is skip-and-report: a missing id is
/// skipped, reported back, and every OTHER id in the batch still succeeds.
@Suite("TaskStore archive/unarchive — L5 skip-and-report")
struct TaskStoreArchiveL5SkipAndReportTests {
    @Test("archive(ids:) skips a missing id and still archives the rest, reporting the skip")
    func archiveSkipsMissingIDAndReportsIt() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "A")
        let b = try await store.create(title: "B")
        try await store.transition(id: a, to: .closed)
        try await store.transition(id: b, to: .closed)
        let missing = UUID()

        let outcome = try await store.archive(ids: [a, missing, b])

        #expect(Set(outcome.flipped) == Set([a, b]), "every real id in the batch must still be archived")
        #expect(outcome.skipped == [missing], "the missing id must be reported, not silently dropped")
        let recordA = try await store.fetch(id: a)
        let recordB = try await store.fetch(id: b)
        #expect(recordA.archivedAt != nil)
        #expect(recordB.archivedAt != nil)
    }

    @Test("unarchive(ids:) skips a missing id and still unarchives the rest, reporting the skip")
    func unarchiveSkipsMissingIDAndReportsIt() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "A")
        let b = try await store.create(title: "B")
        try await store.transition(id: a, to: .closed)
        try await store.transition(id: b, to: .closed)
        _ = try await store.archive(ids: [a, b])
        let missing = UUID()

        let outcome = try await store.unarchive(ids: [a, missing, b])

        #expect(Set(outcome.flipped) == Set([a, b]))
        #expect(outcome.skipped == [missing])
        let recordA = try await store.fetch(id: a)
        let recordB = try await store.fetch(id: b)
        #expect(recordA.archivedAt == nil)
        #expect(recordB.archivedAt == nil)
    }

    @Test("archive(ids:) with an all-missing batch skips everything and flips nothing, without throwing")
    func archiveAllMissingSkipsEverything() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let missing1 = UUID()
        let missing2 = UUID()

        let outcome = try await store.archive(ids: [missing1, missing2])

        #expect(outcome.flipped.isEmpty)
        #expect(Set(outcome.skipped) == Set([missing1, missing2]))
    }
}
