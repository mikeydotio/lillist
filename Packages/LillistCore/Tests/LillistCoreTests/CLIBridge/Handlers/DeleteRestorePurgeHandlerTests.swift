import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge delete/restore/purge/move")
struct DeleteRestorePurgeHandlerTests {
    @Test("Soft-delete works for UUID token")
    func softDelete() async throws {
        let p = try await TestStore.make()
        let id = try await TaskStore(persistence: p).create(title: "T")
        try await CLIBridge.DeleteHandler.run(token: id.uuidString, persistence: p)
        let trashed = try await TaskStore(persistence: p).trashed()
        #expect(trashed.contains { $0.id == id })
    }

    @Test("Soft-delete refuses partial match")
    func softDeleteRefusesPartial() async throws {
        let p = try await TestStore.make()
        _ = try await TaskStore(persistence: p).create(title: "Buy stuff at the store")
        await #expect(throws: LillistError.self) {
            try await CLIBridge.DeleteHandler.run(token: "stuff", persistence: p)
        }
    }

    @Test("Restore brings back a trashed task")
    func restore() async throws {
        let p = try await TestStore.make()
        let id = try await TaskStore(persistence: p).create(title: "T")
        try await TaskStore(persistence: p).softDelete(id: id)
        try await CLIBridge.RestoreHandler.run(token: id.uuidString, persistence: p)
        let r = try await TaskStore(persistence: p).fetch(id: id)
        #expect(r.deletedAt == nil)
    }

    @Test("Purge hard-deletes a task")
    func purge() async throws {
        let p = try await TestStore.make()
        let id = try await TaskStore(persistence: p).create(title: "T")
        try await CLIBridge.PurgeHandler.run(token: id.uuidString, persistence: p)
        await #expect(throws: LillistError.notFound) {
            _ = try await TaskStore(persistence: p).fetch(id: id)
        }
    }

    @Test("Move reparents a task")
    func move() async throws {
        let p = try await TestStore.make()
        let parent = try await TaskStore(persistence: p).create(title: "Parent")
        let child = try await TaskStore(persistence: p).create(title: "Child")
        try await CLIBridge.MoveHandler.run(
            token: child.uuidString,
            newParentToken: parent.uuidString,
            toRoot: false,
            persistence: p
        )
        let rec = try await TaskStore(persistence: p).fetch(id: child)
        #expect(rec.parentID == parent)
    }

    @Test("Move --root sets parent to nil")
    func moveToRoot() async throws {
        let p = try await TestStore.make()
        let parent = try await TaskStore(persistence: p).create(title: "Parent")
        let child = try await TaskStore(persistence: p).create(title: "Child", parent: parent)
        try await CLIBridge.MoveHandler.run(
            token: child.uuidString,
            newParentToken: nil,
            toRoot: true,
            persistence: p
        )
        let rec = try await TaskStore(persistence: p).fetch(id: child)
        #expect(rec.parentID == nil)
    }
}
