import Testing
import Foundation
import CoreData
@testable import LillistCore

/// `TreeIntegrityChecker` is the class-killer for the trash/restore tree
/// state machine — a launch-time self-heal backstop against illegal states
/// only a CloudKit property-level merge can still produce once every local
/// mutation path (M1, H7) guards against them. Every cyclic/corrupted graph
/// here is built by direct context manipulation, bypassing all store-level
/// guards on purpose — the same way a remote merge would.
@Suite("TreeIntegrityChecker")
struct TreeIntegrityCheckerTests {
    private static func makeTask(
        id: UUID = UUID(), title: String, parent: LillistTask? = nil,
        deletedAt: Date? = nil, position: Double = 1.0, in ctx: NSManagedObjectContext
    ) -> LillistTask {
        let t = LillistTask(context: ctx)
        t.id = id
        t.title = title
        t.status = .todo
        t.createdAt = Date()
        t.modifiedAt = Date()
        t.parent = parent
        t.deletedAt = deletedAt
        t.position = position
        return t
    }

    // MARK: - Clean tree

    @Test("scan reports no violations on a clean tree")
    func scanCleanTree() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parent = try await store.create(title: "parent")
        _ = try await store.create(title: "child", parent: parent)
        _ = try await store.create(title: "sibling")

        let ctx = p.container.viewContext
        let violations = try await ctx.perform { try TreeIntegrityChecker.scan(in: ctx) }
        #expect(violations.isEmpty)
    }

    // MARK: - Parent cycles

    @Test("scan detects a 2-node mutual parent cycle")
    func scanDetectsMutualCycle() async throws {
        let p = try await TestStore.make()
        let ctx = p.container.viewContext
        try await ctx.perform {
            let a = Self.makeTask(title: "A", in: ctx)
            let b = Self.makeTask(title: "B", in: ctx)
            a.parent = b
            b.parent = a
            try ctx.save()
        }

        let violations = try await ctx.perform { try TreeIntegrityChecker.scan(in: ctx) }
        let cycles = violations.compactMap { v -> [UUID]? in
            if case .parentCycle(let ids) = v { return ids }
            return nil
        }
        #expect(cycles.count == 1)
        #expect(cycles.first?.count == 2)
    }

    @Test("repair breaks a 2-node cycle by promoting the lexicographically-greatest id to root")
    func repairBreaksMutualCycle() async throws {
        let p = try await TestStore.make()
        let ctx = p.container.viewContext
        // Deterministic winner: force ids so their ordering is known.
        let lowID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let highID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        try await ctx.perform {
            let a = Self.makeTask(id: lowID, title: "A", in: ctx)
            let b = Self.makeTask(id: highID, title: "B", in: ctx)
            a.parent = b
            b.parent = a
            try ctx.save()
        }

        try await ctx.perform {
            let violations = try TreeIntegrityChecker.repair(in: ctx)
            #expect(violations.contains { if case .parentCycle = $0 { return true }; return false })
            try ctx.save()
        }

        let (aParent, bParent): (UUID?, UUID?) = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            let all = try ctx.fetch(req)
            let a = all.first { $0.id == lowID }!
            let b = all.first { $0.id == highID }!
            return (a.parent?.id, b.parent?.id)
        }
        // highID is lexicographically greatest, so it's severed (promoted to root).
        #expect(bParent == nil, "the lexicographically-greatest id must be promoted to root")
        #expect(aParent == highID, "the other member's link is untouched")

        // Idempotent: a second repair pass finds nothing left to fix.
        let followUp = try await ctx.perform { try TreeIntegrityChecker.scan(in: ctx) }
        #expect(followUp.isEmpty)
    }

    @Test("repair breaks a 3-node cycle")
    func repairBreaksLongerCycle() async throws {
        let p = try await TestStore.make()
        let ctx = p.container.viewContext
        try await ctx.perform {
            let a = Self.makeTask(title: "A", in: ctx)
            let b = Self.makeTask(title: "B", in: ctx)
            let c = Self.makeTask(title: "C", in: ctx)
            a.parent = b
            b.parent = c
            c.parent = a
            try ctx.save()
        }

        try await ctx.perform {
            _ = try TreeIntegrityChecker.repair(in: ctx)
            try ctx.save()
        }

        let violations = try await ctx.perform { try TreeIntegrityChecker.scan(in: ctx) }
        #expect(violations.isEmpty, "the 3-node cycle must be fully resolved after one repair pass")
    }

    @Test("repair does not guess when two cycle members share one id — skips and leaves the cycle for a future pass")
    func repairSkipsAmbiguousIDTie() async throws {
        let p = try await TestStore.make()
        let ctx = p.container.viewContext
        let sharedID = UUID()
        try await ctx.perform {
            // Two DISTINCT rows sharing one `id` (issue-#66 shape), both
            // part of the cycle.
            let a = Self.makeTask(id: sharedID, title: "A", in: ctx)
            let b = Self.makeTask(id: sharedID, title: "B (dup id)", in: ctx)
            a.parent = b
            b.parent = a
            try ctx.save()
        }

        try await ctx.perform {
            _ = try TreeIntegrityChecker.repair(in: ctx)
            try ctx.save()
        }

        // The cycle must still be there — repair must not have guessed.
        let stillCyclic = try await ctx.perform { try TreeIntegrityChecker.scan(in: ctx) }
        #expect(stillCyclic.contains { if case .parentCycle = $0 { return true }; return false })
    }

    // MARK: - Live-under-trashed

    @Test("scan and repair detect and promote a live task under a trashed parent")
    func liveUnderTrashedPromotedToRoot() async throws {
        let p = try await TestStore.make()
        let ctx = p.container.viewContext
        let childID = UUID()
        try await ctx.perform {
            let parent = Self.makeTask(title: "parent", deletedAt: Date(), in: ctx)
            let child = Self.makeTask(id: childID, title: "child", parent: parent, deletedAt: nil, in: ctx)
            _ = child
            try ctx.save()
        }

        let scanned = try await ctx.perform { try TreeIntegrityChecker.scan(in: ctx) }
        #expect(scanned.contains { if case .liveUnderTrashedAncestor(let taskID, _) = $0 { return taskID == childID }; return false })

        try await ctx.perform {
            _ = try TreeIntegrityChecker.repair(in: ctx)
            try ctx.save()
        }

        let childParent: UUID? = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", childID as CVarArg)
            return try ctx.fetch(req).first?.parent?.id
        }
        #expect(childParent == nil, "the live child must be promoted to root")
    }

    // MARK: - Position ties

    @Test("scan and repair detect and heal a live-sibling position tie")
    func positionTieHealed() async throws {
        let p = try await TestStore.make()
        let ctx = p.container.viewContext
        try await ctx.perform {
            _ = Self.makeTask(title: "A", position: 1.0, in: ctx)
            _ = Self.makeTask(title: "B", position: 1.0, in: ctx) // tied with A
            _ = Self.makeTask(title: "C", position: 2.0, in: ctx)
            try ctx.save()
        }

        let scanned = try await ctx.perform { try TreeIntegrityChecker.scan(in: ctx) }
        #expect(scanned.contains { if case .positionTie = $0 { return true }; return false })

        try await ctx.perform {
            _ = try TreeIntegrityChecker.repair(in: ctx)
            try ctx.save()
        }

        let positions: [Double] = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            return try ctx.fetch(req).map(\.position)
        }
        #expect(Set(positions).count == positions.count, "no two roots may share a position after repair")
    }

    // MARK: - Staged interaction: promotion can create a NEW tie the same repair pass must also catch

    @Test("a promotion-created position tie is healed in the same repair pass")
    func promotionCreatedTieIsAlsoHealed() async throws {
        let p = try await TestStore.make()
        let ctx = p.container.viewContext
        let childID = UUID()
        try await ctx.perform {
            // An existing root task at position 1.0...
            _ = Self.makeTask(title: "existing root", position: 1.0, in: ctx)
            // ...and a live child of a trashed parent that will be promoted
            // to root at that SAME position — a tie that only exists AFTER
            // promotion, which staging must still catch in one pass.
            let parent = Self.makeTask(title: "parent", deletedAt: Date(), in: ctx)
            let child = Self.makeTask(id: childID, title: "child", parent: parent, deletedAt: nil, position: 1.0, in: ctx)
            _ = child
            try ctx.save()
        }

        try await ctx.perform {
            _ = try TreeIntegrityChecker.repair(in: ctx)
            try ctx.save()
        }

        let violations = try await ctx.perform { try TreeIntegrityChecker.scan(in: ctx) }
        #expect(violations.isEmpty, "the promotion-created tie must be healed in the same repair pass")
    }
}
