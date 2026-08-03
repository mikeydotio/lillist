import Testing
import Foundation
@testable import LillistCore

/// `LIL-95`: ``TaskStore``'s ``WidgetTaskLookup`` conformance — the batched
/// parent-resolution read ``WidgetSnapshotBuilder`` uses to find a
/// non-matching parent for a matched subtask.
@Suite("TaskStore — WidgetTaskLookup")
struct WidgetTaskLookupTests {
    @Test("looks up multiple tasks by id in one call")
    func looksUpMultipleTasks() async throws {
        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let a = try await tasks.create(title: "A")
        let b = try await tasks.create(title: "B")
        _ = try await tasks.create(title: "C") // not requested

        let found = try await tasks.lookupTasks(ids: [a, b])

        #expect(Set(found.map(\.id)) == [a, b])
        #expect(Set(found.map(\.title)) == ["A", "B"])
    }

    @Test("an id with no matching task is simply absent, not an error")
    func missingIDIsAbsent() async throws {
        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let a = try await tasks.create(title: "A")

        let found = try await tasks.lookupTasks(ids: [a, UUID()])

        #expect(found.map(\.id) == [a])
    }

    @Test("an empty id list returns an empty result without touching the store")
    func emptyIDListReturnsEmpty() async throws {
        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)

        #expect(try await tasks.lookupTasks(ids: []).isEmpty)
    }

    @Test("a trashed task is excluded, matching every other widget read")
    func trashedTaskExcluded() async throws {
        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let a = try await tasks.create(title: "A")
        try await tasks.softDelete(id: a)

        let found = try await tasks.lookupTasks(ids: [a])

        #expect(found.isEmpty)
    }
}
