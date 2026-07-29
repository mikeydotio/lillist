import Testing
import CoreData
import Foundation
@testable import LillistCore

/// M6: `reorder`'s both-anchors guard (`afterTask.parent != beforeTask.parent`
/// → throw) only fires when BOTH anchors are present. With a single anchor
/// under `.explicit(parent)`, nothing checked that the anchor actually
/// belongs to the target parent's sibling group — the anchor's `position`
/// (meaningful only within its OWN group) got used to compute a position
/// under a completely different group, which can collide with an existing
/// sibling there or is simply meaningless.
@Suite("TaskStore reorder — M6 explicit-parent single-anchor mismatch", .serialized)
struct TaskStoreM6ExplicitParentAnchorMismatchTests {
    @Test("A single 'after' anchor from a different sibling group throws, not silently computes a colliding position")
    func afterAnchorFromDifferentGroupThrows() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let ctx = p.container.viewContext

        let groupOneParent = try await store.create(title: "Group1")
        let anchor = try await store.create(title: "Anchor", parent: groupOneParent)
        let groupTwoParent = try await store.create(title: "Group2")
        let sibling = try await store.create(title: "Sibling", parent: groupTwoParent)
        let mover = try await store.create(title: "Mover")

        // Force positions so the wrong-group computation would land exactly
        // on an existing Group2 sibling's position if the bug were present:
        // FractionalPosition.position(after: 1.0, before: nil) == 2.0.
        try await forcePosition(1.0, forTaskID: anchor, in: ctx)
        try await forcePosition(2.0, forTaskID: sibling, in: ctx)

        await #expect(throws: LillistError.self) {
            try await store.reorder(id: mover, after: anchor, before: nil, parent: .explicit(groupTwoParent))
        }

        // No collision was created — the sibling group is untouched.
        let group2Kids = try await store.children(of: groupTwoParent)
        #expect(group2Kids.map(\.title) == ["Sibling"])
    }

    @Test("A single 'before' anchor from a different sibling group throws")
    func beforeAnchorFromDifferentGroupThrows() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)

        let groupOneParent = try await store.create(title: "Group1")
        let anchor = try await store.create(title: "Anchor", parent: groupOneParent)
        let groupTwoParent = try await store.create(title: "Group2")
        let mover = try await store.create(title: "Mover")

        await #expect(throws: LillistError.self) {
            try await store.reorder(id: mover, after: nil, before: anchor, parent: .explicit(groupTwoParent))
        }
    }

    @Test("A single anchor that DOES belong to the explicit target parent still succeeds")
    func matchingSingleAnchorStillSucceeds() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)

        let parent = try await store.create(title: "Parent")
        let anchor = try await store.create(title: "Anchor", parent: parent)
        let mover = try await store.create(title: "Mover")

        try await store.reorder(id: mover, after: anchor, before: nil, parent: .explicit(parent))

        let kids = try await store.children(of: parent)
        #expect(kids.map(\.title) == ["Anchor", "Mover"])
    }

    @Test("A single anchor at the top level (explicit(nil)) that belongs to root still succeeds")
    func matchingRootAnchorStillSucceeds() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)

        let anchor = try await store.create(title: "Anchor")
        let mover = try await store.create(title: "Mover")

        try await store.reorder(id: mover, after: anchor, before: nil, parent: .explicit(nil))

        let roots = try await store.children(of: nil)
        #expect(roots.map(\.title) == ["Anchor", "Mover"])
    }

    // MARK: - Helpers

    private func forcePosition(
        _ newPosition: Double,
        forTaskID taskID: UUID,
        in ctx: NSManagedObjectContext
    ) async throws {
        try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", taskID as CVarArg)
            req.fetchLimit = 1
            guard let obj = try ctx.fetch(req).first else {
                throw LillistError.notFound
            }
            obj.position = newPosition
            try ctx.save()
        }
    }
}
