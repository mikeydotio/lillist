import Testing
import Foundation
@testable import LillistCore

@Suite("TaskStore queries (pinned, forTag, breadcrumbs)")
struct TaskStoreQueriesTests {
    // MARK: - pinned()

    @Test("pinned returns empty when nothing is pinned")
    func pinnedEmpty() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        _ = try await store.create(title: "A")
        _ = try await store.create(title: "B")
        let pinned = try await store.pinned()
        #expect(pinned.isEmpty)
    }

    @Test("pinned returns all pinned tasks across the tree, excluding trash")
    func pinnedAcrossTree() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "A")
        let b = try await store.create(title: "B", parent: a)
        let c = try await store.create(title: "C")
        try await store.update(id: a) { $0.isPinned = true }
        try await store.update(id: b) { $0.isPinned = true }
        try await store.softDelete(id: c)
        // c is not pinned anyway, but make sure soft-deleted pinned items would also be filtered:
        try await store.update(id: c) { $0.isPinned = true }

        let pinned = try await store.pinned().map(\.id)
        #expect(Set(pinned) == Set([a, b]))
    }

    // MARK: - syncCounts()

    @Test("syncCounts counts every local row (incl. trashed); mirrored is 0 off-cloud")
    func syncCounts() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)

        // Empty store: nothing local, nothing mirrored.
        #expect(try await store.syncCounts() == .init(local: 0, mirrored: 0))

        _ = try await store.create(title: "A")
        _ = try await store.create(title: "B")
        let c = try await store.create(title: "C")
        // A trashed task is tombstoned but still a synced row — it counts.
        try await store.softDelete(id: c)

        let counts = try await store.syncCounts()
        #expect(counts.local == 3)
        // The in-memory test store is a plain NSPersistentContainer, not an
        // NSPersistentCloudKitContainer, so nothing is mirrored. The mirrored>0
        // path needs a live cloud container (verified on device).
        #expect(counts.mirrored == 0)
    }

    // MARK: - tasks(forTag:)

    @Test("tasks(forTag:) returns only tagged non-trashed tasks")
    func tasksForTag() async throws {
        let p = try await TestStore.make()
        let taskStore = TaskStore(persistence: p)
        let tagStore = TagStore(persistence: p)
        let tagID = try await tagStore.create(name: "work")
        let a = try await taskStore.create(title: "Write report")
        let b = try await taskStore.create(title: "Read paper")
        _ = try await taskStore.create(title: "Unrelated") // no tag
        try await taskStore.assignTag(taskID: a, tagID: tagID)
        try await taskStore.assignTag(taskID: b, tagID: tagID)
        try await taskStore.softDelete(id: b)

        let results = try await taskStore.tasks(forTag: tagID)
        #expect(results.map(\.id) == [a])
    }

    @Test("tasks(forTag:) with includeDescendants includes child-tag tasks and de-duplicates")
    func tasksForTagDescendants() async throws {
        let p = try await TestStore.make()
        let taskStore = TaskStore(persistence: p)
        let tagStore = TagStore(persistence: p)
        let parent = try await tagStore.create(name: "work")
        let child = try await tagStore.create(name: "client-a", parent: parent)
        let a = try await taskStore.create(title: "Plan")
        let b = try await taskStore.create(title: "Onboard")
        try await taskStore.assignTag(taskID: a, tagID: parent)
        try await taskStore.assignTag(taskID: b, tagID: child)
        // double-tag: should appear once
        try await taskStore.assignTag(taskID: b, tagID: parent)

        let withDescendants = try await taskStore.tasks(forTag: parent, includeDescendants: true)
        #expect(Set(withDescendants.map(\.id)) == Set([a, b]))
        #expect(withDescendants.count == 2)

        let withoutDescendants = try await taskStore.tasks(forTag: parent, includeDescendants: false)
        #expect(Set(withoutDescendants.map(\.id)) == Set([a, b])) // b is *also* tagged with parent directly
    }

    @Test("tasks(forTag:) returns empty for unknown tag")
    func tasksForUnknownTag() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let results = try await store.tasks(forTag: UUID())
        #expect(results.isEmpty)
    }

    // MARK: - breadcrumbs(for:)

    @Test("breadcrumbs returns empty trail for root-level tasks")
    func breadcrumbsRoot() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "A")
        let crumbs = try await store.breadcrumbs(for: [a])
        #expect(crumbs[a] == [])
    }

    @Test("breadcrumbs returns top-down parent titles")
    func breadcrumbsNested() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "Work")
        let b = try await store.create(title: "Releases", parent: a)
        let c = try await store.create(title: "v0.2", parent: b)
        let d = try await store.create(title: "Ship", parent: c)
        let crumbs = try await store.breadcrumbs(for: [d])
        #expect(crumbs[d] == ["Work", "Releases", "v0.2"])
    }

    @Test("breadcrumbs handles multiple IDs and unknown IDs gracefully")
    func breadcrumbsBatch() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "Root")
        let b = try await store.create(title: "Child", parent: a)
        let crumbs = try await store.breadcrumbs(for: [a, b, UUID()])
        #expect(crumbs[a] == [])
        #expect(crumbs[b] == ["Root"])
        #expect(crumbs.count == 2) // unknown ID is silently dropped
    }
}
