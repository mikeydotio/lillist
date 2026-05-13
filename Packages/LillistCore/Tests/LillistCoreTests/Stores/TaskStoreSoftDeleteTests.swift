import Testing
import Foundation
@testable import LillistCore

@Suite("TaskStore soft delete")
struct TaskStoreSoftDeleteTests {
    @Test("Soft delete sets deletedAt and excludes from children listing")
    func softDelete() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "doomed")
        try await store.softDelete(id: id)
        let roots = try await store.children(of: nil)
        #expect(roots.isEmpty)
        let trashed = try await store.trashed()
        #expect(trashed.count == 1)
        #expect(trashed.first?.id == id)
    }

    @Test("Soft delete cascades to children")
    func cascadeSoftDelete() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parent = try await store.create(title: "Parent")
        let child = try await store.create(title: "Child", parent: parent)
        try await store.softDelete(id: parent)
        let parentRecord = try await store.fetch(id: parent)
        let childRecord = try await store.fetch(id: child)
        #expect(parentRecord.deletedAt != nil)
        #expect(childRecord.deletedAt != nil)
    }

    @Test("Restore clears deletedAt")
    func restore() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "T")
        try await store.softDelete(id: id)
        try await store.restore(id: id)
        let record = try await store.fetch(id: id)
        #expect(record.deletedAt == nil)
    }

    @Test("Restore cascades to children whose deletedAt matches the parent's")
    func restoreCascade() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parent = try await store.create(title: "Parent")
        let child = try await store.create(title: "Child", parent: parent)
        try await store.softDelete(id: parent)
        try await store.restore(id: parent)
        let parentRecord = try await store.fetch(id: parent)
        let childRecord = try await store.fetch(id: child)
        #expect(parentRecord.deletedAt == nil)
        #expect(childRecord.deletedAt == nil)
    }

    @Test("Soft-deleted task is excluded from default fetches but accessible via fetch(id:)")
    func directFetchStillWorks() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "T")
        try await store.softDelete(id: id)
        let record = try await store.fetch(id: id)
        #expect(record.deletedAt != nil)
    }
}
