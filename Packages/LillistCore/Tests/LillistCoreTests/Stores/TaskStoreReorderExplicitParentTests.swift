import Testing
import CoreData
import Foundation
@testable import LillistCore

/// Tests for the explicit-parent `reorder` path (`ReparentTarget.explicit`).
///
/// The drag system resolves an authoritative target parent (including `nil` for
/// top level) and must thread it to the store instead of letting `reorder`
/// re-infer the parent from the anchors. The old inference
/// (`afterParent ?? beforeParent ?? m.parent`) cannot represent "top level"
/// distinctly from "no anchor info", so de-parenting a child to the root was
/// silently lost. These tests pin the explicit behavior; the existing
/// `TaskStoreReorder*` suites pin that `.infer` (the default) is unchanged.
@Suite("TaskStore reorder explicit parent", .serialized)
struct TaskStoreReorderExplicitParentTests {

    /// Issue 1: dragging child B above top-level parent A de-parents B to the
    /// root and places it *before* A.
    @Test("explicit(nil) de-parents a child to top level, before its old parent")
    func deparentsBeforeOldParent() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)

        let a = try await store.create(title: "A")             // top-level
        let b = try await store.create(title: "B", parent: a)  // child of A

        try await store.reorder(id: b, after: nil, before: a, parent: .explicit(nil))

        let roots = try await store.children(of: nil)
        #expect(roots.map(\.title) == ["B", "A"])
        let bRec = try #require(roots.first(where: { $0.title == "B" }))
        #expect(bRec.parentID == nil)
        let aKids = try await store.children(of: a)
        #expect(aKids.isEmpty)
    }

    /// Issue 2: B (A's only child) dropped as a top-level sibling *after* A.
    @Test("explicit(nil) de-parents a child to top level, after its old parent")
    func deparentsAfterOldParent() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)

        let a = try await store.create(title: "A")
        let b = try await store.create(title: "B", parent: a)

        try await store.reorder(id: b, after: a, before: nil, parent: .explicit(nil))

        let roots = try await store.children(of: nil)
        #expect(roots.map(\.title) == ["A", "B"])
        let bRec = try #require(roots.first(where: { $0.title == "B" }))
        #expect(bRec.parentID == nil)
    }

    /// `explicit(pid)`: nest a top-level task under a parent as the first child.
    @Test("explicit(parent) nests a top-level task under a parent")
    func nestsUnderExplicitParent() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)

        let a = try await store.create(title: "A")
        let c = try await store.create(title: "C", parent: a)  // existing child of A
        let b = try await store.create(title: "B")             // top-level sibling of A

        // Place B as A's first child, before C.
        try await store.reorder(id: b, after: nil, before: c, parent: .explicit(a))

        let aKids = try await store.children(of: a)
        #expect(aKids.map(\.title) == ["B", "C"])
        let bRec = try #require(aKids.first(where: { $0.title == "B" }))
        #expect(bRec.parentID == a)
        let roots = try await store.children(of: nil)
        #expect(roots.map(\.title) == ["A"])
    }

    /// The default `.infer` path (no `parent:` argument) must keep its existing
    /// same-parent reorder behavior.
    @Test("default infer reorder keeps existing same-parent behavior")
    func inferDefaultUnchanged() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)

        let parentID = try await store.create(title: "P")
        let a = try await store.create(title: "A", parent: parentID)
        let b = try await store.create(title: "B", parent: parentID)

        try await store.reorder(id: b, after: nil, before: a)   // no parent arg

        let kids = try await store.children(of: parentID)
        #expect(kids.map(\.title) == ["B", "A"])
    }

    /// An explicit de-parent into a tight gap must recompact the *destination*
    /// (top-level) sibling group and still land the row between its anchors.
    @Test("explicit de-parent into a tight gap recompacts the destination siblings")
    func explicitDeparentCompacts() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)

        let a = try await store.create(title: "A")          // top-level
        let b = try await store.create(title: "B")          // top-level
        let parent = try await store.create(title: "P")     // top-level
        let child = try await store.create(title: "C", parent: parent)

        // Force a sub-ULP gap between A and B so inserting between them needs
        // compaction.
        let ctx = p.container.viewContext
        try await forcePosition(10.0, forTaskID: a, in: ctx)
        try await forcePosition(10.0.nextUp, forTaskID: b, in: ctx)

        // De-parent C to the root, between A and B.
        try await store.reorder(id: child, after: a, before: b, parent: .explicit(nil))

        let roots = try await store.children(of: nil)
        let positions = roots.map(\.position)
        for i in 1..<positions.count {
            #expect(positions[i] > positions[i - 1], "top-level positions must be strictly increasing after compaction")
        }
        let order = roots.map(\.title)
        let ai = try #require(order.firstIndex(of: "A"))
        let ci = try #require(order.firstIndex(of: "C"))
        let bi = try #require(order.firstIndex(of: "B"))
        #expect(ai < ci && ci < bi, "C should land between A and B")
        let childRec = try #require(roots.first(where: { $0.title == "C" }))
        #expect(childRec.parentID == nil)
    }

    // MARK: - Helpers

    /// Force `position` on a task directly via the `viewContext`, bypassing the
    /// store's public API. Mirrors the helper in `TaskStoreReorderHealTests`.
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
