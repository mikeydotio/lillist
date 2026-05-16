import Testing
import LillistCore
import Foundation

@Suite("Pinned-anywhere sidebar contract")
struct PinnedSidebarIntegrationTests {
    @Test("Pinned task two levels deep appears in pinned() output")
    func nestedPinnedTaskAppears() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let store = TaskStore(persistence: persistence)

        let root = try await store.create(title: "root")
        let child = try await store.create(title: "child", parent: root)
        let grandchild = try await store.create(title: "grand", parent: child)
        try await store.update(id: grandchild) { $0.isPinned = true }

        let pinned = try await store.pinned()
        #expect(pinned.map(\.id).contains(grandchild))
    }

    @Test("Trashed pinned task does not appear")
    func trashedPinnedExcluded() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let store = TaskStore(persistence: persistence)
        let t = try await store.create(title: "x")
        try await store.update(id: t) { $0.isPinned = true }
        try await store.softDelete(id: t)
        let pinned = try await store.pinned()
        #expect(!pinned.map(\.id).contains(t))
    }
}
