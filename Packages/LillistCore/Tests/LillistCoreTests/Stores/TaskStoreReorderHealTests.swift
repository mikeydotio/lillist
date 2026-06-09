import Testing
import CoreData
import Foundation
@testable import LillistCore

/// Red tests for the "heal-then-recheck" fix (Step 7).
///
/// When two siblings have equal `position` values a third drag into the gap
/// currently throws "anchors out of order" before `recompactSiblings` can fix
/// the tie.  After the fix, `reorder` will:
///   1. Detect equal anchors (tie, not inversion).
///   2. Recompact siblings in canonical `SiblingOrder` (position asc, then
///      `id.uuidString` asc on ties) to widen the gap.
///   3. Re-fetch anchors from the now-updated objects.
///   4. Re-check — if anchors are now ordered, compute position and save.
///      If still inverted (genuine bad data), throw as before.
///
/// Tests T4, T6, T10, T15 are regression guards that should pass both before
/// and after the fix.  Tests T2, T3, T7, T8, T16 are expected to **fail today**
/// (throw when they should heal) and **pass after** the fix.
@Suite("TaskStore reorder heal", .serialized)
struct TaskStoreReorderHealTests {

    // MARK: - Helpers

    /// Force `position` on a task identified by `id` directly via the
    /// `viewContext`, bypassing the store's public API.  Must be called
    /// outside of any existing `perform` block.
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

    // MARK: - T2: Equal-position tail pair heals

    /// **Expected RED today, GREEN after fix.**
    ///
    /// Two siblings share the same position (a tie produced by, e.g., two
    /// independent `max + 1` computations).  Dragging a third task into the
    /// gap between them should heal silently — not throw.
    @Test("Equal-position tail pair: reorder into the gap heals and lands in intended slot")
    func healsEqualTailPair() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)

        // A=1.0, B=2.0, C=3.0 initially.
        let parentID = try await store.create(title: "P")
        let a = try await store.create(title: "A", parent: parentID)
        let b = try await store.create(title: "B", parent: parentID)
        let c = try await store.create(title: "C", parent: parentID)

        // Force a tie: set B.position = 3.0 so B and C are both at 3.0.
        let ctx = p.container.viewContext
        try await forcePosition(3.0, forTaskID: b, in: ctx)

        // State: A=1.0, B=3.0, C=3.0 (B and C are tied).
        // Drag A into the gap between tied B and C.
        // Post-fix: must NOT throw.  A must land after B and before C.
        try await store.reorder(id: a, after: b, before: c)

        let children = try await store.children(of: parentID)
        let positions = children.map(\.position)

        // Strictly increasing — the tie must be healed.
        for i in 1..<positions.count {
            #expect(positions[i] > positions[i - 1], "positions should be strictly increasing after heal")
        }

        // A must appear after B.
        let bIdx = try #require(children.firstIndex(where: { $0.id == b }))
        let aIdx = try #require(children.firstIndex(where: { $0.id == a }))
        #expect(aIdx > bIdx, "A should land after B")
    }

    // MARK: - T3: Two-context tie (brick repro)

    /// **Expected RED today, GREEN after fix.**
    ///
    /// Deterministic reproduction of the production scenario: two independent
    /// `NSManagedObjectContext`s each compute `max(position) + 1.0` concurrently
    /// and both pick 2.0 — producing a tie.  A third drag into that gap should
    /// heal post-fix.
    @Test("Two-context position tie: reorder into the gap heals post-fix (bricks today)")
    func brickRepro() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)

        // Create parent and an initial child so the next position is 2.0.
        let parentID = try await store.create(title: "P")
        let a = try await store.create(title: "A", parent: parentID)
        _ = a  // A is the third task we'll drag.

        let ctxA = p.container.viewContext
        let ctxB = p.container.newBackgroundContext()
        ctxB.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)

        // Both ctxA and ctxB independently observe max(position)=1.0 and
        // assign position=2.0 to their new task — the non-atomic race window.
        let xID = UUID()
        let yID = UUID()

        // ctxA inserts X at position 2.0.
        try await ctxA.perform {
            let parentReq = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            parentReq.predicate = NSPredicate(format: "id == %@", parentID as CVarArg)
            parentReq.fetchLimit = 1
            let parentObj = try ctxA.fetch(parentReq).first

            let x = LillistTask(context: ctxA)
            x.id = xID
            x.title = "X"
            x.status = .todo
            x.position = 2.0
            x.startHasTime = false
            x.deadlineHasTime = false
            x.isPinned = false
            x.createdAt = Date()
            x.modifiedAt = x.createdAt
            x.parent = parentObj
            try ctxA.save()
        }

        // ctxB inserts Y at the same position 2.0 (stale snapshot).
        try await ctxB.perform {
            let parentReq = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            parentReq.predicate = NSPredicate(format: "id == %@", parentID as CVarArg)
            parentReq.fetchLimit = 1
            let parentObj = try ctxB.fetch(parentReq).first

            let y = LillistTask(context: ctxB)
            y.id = yID
            y.title = "Y"
            y.status = .todo
            y.position = 2.0
            y.startHasTime = false
            y.deadlineHasTime = false
            y.isPinned = false
            y.createdAt = Date()
            y.modifiedAt = y.createdAt
            y.parent = parentObj
            try ctxB.save()
        }

        // Merge ctxB's changes into the viewContext so the store sees them.
        await ctxA.perform {
            ctxA.refreshAllObjects()
        }

        // A=1.0, X=2.0, Y=2.0 — X and Y are tied.
        // Drag A into the gap between X and Y.
        // Post-fix: should NOT throw; A lands between X and Y.
        try await store.reorder(id: a, after: xID, before: yID)

        let children = try await store.children(of: parentID)
        let positions = children.map(\.position)

        // Strictly increasing.
        for i in 1..<positions.count {
            #expect(positions[i] > positions[i - 1], "positions must be strictly increasing after heal")
        }

        // A must appear between X and Y.
        let xIdx = try #require(children.firstIndex(where: { $0.id == xID }))
        let aIdx = try #require(children.firstIndex(where: { $0.id == a }))
        let yIdx = try #require(children.firstIndex(where: { $0.id == yID }))
        #expect(aIdx > xIdx, "A should be after X")
        #expect(aIdx < yIdx, "A should be before Y")
    }

    // MARK: - T4: Genuine inversion still throws (regression guard)

    /// **Should pass BOTH before and after the fix.**
    ///
    /// When anchors are genuinely inverted (after.position > before.position)
    /// the reorder must still throw `LillistError` — the heal path must not
    /// mask a real data-integrity violation.
    @Test("Regression: genuinely inverted anchors (a > b) still throw after restructure")
    func invertedAnchorStillThrows() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)

        let parent = try await store.create(title: "P")
        let a = try await store.create(title: "A", parent: parent)
        let b = try await store.create(title: "B", parent: parent)
        let c = try await store.create(title: "C", parent: parent)

        // Ask to drop C with after=B (pos≈2.0), before=A (pos≈1.0) — inverted.
        await #expect(throws: LillistError.self) {
            try await store.reorder(id: c, after: b, before: a)
        }
    }

    // MARK: - T6: Stale inversion (mutated between snapshot and drop) still throws

    /// **Should pass BOTH before and after the fix.**
    ///
    /// An anchor was mutated externally so that after.position > before.position
    /// (a genuine inversion, not a tie).  The store must throw, not heal.
    @Test("Anchors mutated to a>b between snapshot and reorder: throws (not heals)")
    func staleInversionThrows() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)

        let parent = try await store.create(title: "P")
        let a = try await store.create(title: "A", parent: parent)
        let b = try await store.create(title: "B", parent: parent)
        let c = try await store.create(title: "C", parent: parent)

        // Force A to a position much higher than B — creating a genuine inversion.
        let ctx = p.container.viewContext
        try await forcePosition(5.0, forTaskID: a, in: ctx)

        // Now A.position=5.0, B.position≈2.0 → a > b, a genuine inversion.
        await #expect(throws: LillistError.self) {
            try await store.reorder(id: c, after: a, before: b)
        }
    }

    // MARK: - T7: Soft-deleted sibling between tied anchors heals

    /// **Expected RED today, GREEN after fix.**
    ///
    /// A soft-deleted sibling sits between the two tied anchors in the full
    /// sibling set.  The heal path must operate only on visible (non-trashed)
    /// siblings, and must not throw.
    @Test("Hidden sibling between anchors: heals when anchors are tied")
    func filteredSiblingBetweenTiedAnchors() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)

        // A=1.0, B=2.0, C=3.0, D=4.0
        let parentID = try await store.create(title: "P")
        let a = try await store.create(title: "A", parent: parentID)
        let b = try await store.create(title: "B", parent: parentID)
        let c = try await store.create(title: "C", parent: parentID)
        let d = try await store.create(title: "D", parent: parentID)

        // Force a tie: B and C both at position 3.0.
        let ctx = p.container.viewContext
        try await forcePosition(3.0, forTaskID: b, in: ctx)

        // Soft-delete D — it now sits between the tied siblings in the full set
        // (by original position) but is excluded from the visible sibling list.
        try await store.softDelete(id: d)

        // Visible siblings: A=1.0, B=3.0, C=3.0 (D is hidden).
        // Drag A into the gap between tied B and C.
        // Post-fix: should heal and NOT throw.
        try await store.reorder(id: a, after: b, before: c)

        let children = try await store.children(of: parentID)
        let positions = children.map(\.position)

        // Strictly increasing.
        for i in 1..<positions.count {
            #expect(positions[i] > positions[i - 1], "positions must be strictly increasing after heal")
        }

        // A must appear after B.
        let bIdx = try #require(children.firstIndex(where: { $0.id == b }))
        let aIdx = try #require(children.firstIndex(where: { $0.id == a }))
        #expect(aIdx > bIdx, "A should land after B")
    }

    // MARK: - T8: N≥3 ties heal

    /// **Expected RED today, GREEN after fix.**
    ///
    /// Three siblings share the same position.  Dragging into the gap between
    /// two of them should heal the entire group and not throw.
    @Test("N≥3 tied siblings: reorder into the group heals")
    func threeWayTieHeals() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)

        // A=1.0, B=2.0, C=2.0, D=2.0 (B, C, D are tied at 2.0 after creation).
        let parentID = try await store.create(title: "P")
        let a = try await store.create(title: "A", parent: parentID)
        let b = try await store.create(title: "B", parent: parentID)
        let c = try await store.create(title: "C", parent: parentID)
        let d = try await store.create(title: "D", parent: parentID)

        // Force B, C, D all to 5.0 — a three-way tie.
        let ctx = p.container.viewContext
        try await forcePosition(5.0, forTaskID: b, in: ctx)
        try await forcePosition(5.0, forTaskID: c, in: ctx)
        try await forcePosition(5.0, forTaskID: d, in: ctx)

        // Drag A into the gap between tied B and C.
        // Post-fix: should NOT throw; all positions strictly increasing.
        try await store.reorder(id: a, after: b, before: c)

        let children = try await store.children(of: parentID)
        let positions = children.map(\.position)

        // Strictly increasing.
        for i in 1..<positions.count {
            #expect(positions[i] > positions[i - 1], "positions must be strictly increasing after heal")
        }

        // A must appear after B and before (or at) C.
        let bIdx = try #require(children.firstIndex(where: { $0.id == b }))
        let aIdx = try #require(children.firstIndex(where: { $0.id == a }))
        #expect(aIdx > bIdx, "A should land after B")
    }

    // MARK: - T9: Tie-break uses id.uuidString, not createdAt

    /// **May pass or fail today; must pass after fix.**
    ///
    /// After a recompaction triggered by a tie, sibling order within the tie
    /// group is broken by `id.uuidString` ascending — NOT by `createdAt`.
    /// This test creates two tasks where createdAt order is the REVERSE of
    /// id.uuidString order, then verifies post-heal positions match id order.
    @Test("Tie-break uses id.uuidString order, not createdAt order")
    func tieBreakByIdNotCreatedAt() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)

        // loID sorts before hiID in uuidString lexical order.
        let loID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let hiID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!

        let parentID = try await store.create(title: "P")

        let ctx = p.container.viewContext
        // Insert hiID FIRST (earlier createdAt) then loID (later createdAt)
        // so that createdAt order is [hi, lo] but id.uuidString order is [lo, hi].
        try await ctx.perform {
            let parentReq = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            parentReq.predicate = NSPredicate(format: "id == %@", parentID as CVarArg)
            parentReq.fetchLimit = 1
            let parentObj = try ctx.fetch(parentReq).first

            // Y(hi) — earlier createdAt, later in uuidString sort.
            let yTask = LillistTask(context: ctx)
            yTask.id = hiID
            yTask.title = "Y(hi)"
            yTask.status = .todo
            yTask.position = 5.0
            yTask.startHasTime = false
            yTask.deadlineHasTime = false
            yTask.isPinned = false
            yTask.createdAt = Date(timeIntervalSinceReferenceDate: 1000)
            yTask.modifiedAt = yTask.createdAt
            yTask.parent = parentObj

            // X(lo) — later createdAt, earlier in uuidString sort.
            let xTask = LillistTask(context: ctx)
            xTask.id = loID
            xTask.title = "X(lo)"
            xTask.status = .todo
            xTask.position = 5.0
            xTask.startHasTime = false
            xTask.deadlineHasTime = false
            xTask.isPinned = false
            xTask.createdAt = Date(timeIntervalSinceReferenceDate: 2000)
            xTask.modifiedAt = xTask.createdAt
            xTask.parent = parentObj

            try ctx.save()
        }

        // W is a "normal" fourth task with a lower position — the drag subject.
        let wID = try await store.create(title: "W", parent: parentID)
        // Force W to position 1.0 so it's clearly below the tied pair.
        try await forcePosition(1.0, forTaskID: wID, in: ctx)

        // Drag W into the gap between X(lo) and Y(hi): both at 5.0 → triggers heal.
        // Post-heal, X(loID) must have a lower position than Y(hiID).
        try await store.reorder(id: wID, after: loID, before: hiID)

        let children = try await store.children(of: parentID)
        let xRec = try #require(children.first(where: { $0.id == loID }))
        let yRec = try #require(children.first(where: { $0.id == hiID }))
        #expect(xRec.position < yRec.position,
                "After tie-break heal, loID should have a lower position than hiID")
    }

    // MARK: - T10: Soft-deleted anchor throws notFound (regression guard)

    /// **Should pass BOTH before and after the fix.**
    ///
    /// Using a soft-deleted task as an anchor in `reorder` must throw `LillistError`
    /// (either `.notFound` or `.validationFailed`) — the store must not silently
    /// place into a gap defined by a trashed task.
    @Test("Soft-deleted anchor throws notFound before heal attempt")
    func softDeletedAnchorThrowsNotFound() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)

        let parent = try await store.create(title: "P")
        let a = try await store.create(title: "A", parent: parent)
        let b = try await store.create(title: "B", parent: parent)
        let c = try await store.create(title: "C", parent: parent)

        // Soft-delete B — it is now in the Trash.
        try await store.softDelete(id: b)

        // Reorder C using deleted B as the `before` anchor.
        // Must throw a LillistError (not succeed silently).
        await #expect(throws: LillistError.self) {
            try await store.reorder(id: c, after: a, before: b)
        }
    }

    // MARK: - T15: Nil-anchor (head / tail) reorders never throw

    /// **Should pass BOTH before and after the fix.**
    ///
    /// Head and tail reorders (one nil anchor) on a healthy list should never
    /// trigger the anchor-order guard or the heal path.
    @Test("Head and tail reorders with nil anchors do not throw")
    func headTailNilAnchorsDoNotThrow() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)

        let parentID = try await store.create(title: "P")
        let a = try await store.create(title: "A", parent: parentID)
        let b = try await store.create(title: "B", parent: parentID)

        // Move A to the tail (after B, before nil).
        try await store.reorder(id: a, after: b, before: nil)

        // Move B back to the head (after nil, before A).
        try await store.reorder(id: b, after: nil, before: a)

        // If we reached here without throwing, the test passes.
        let titles = (try await store.children(of: parentID)).map(\.title)
        #expect(titles == ["B", "A"])
    }

    // MARK: - T16: CloudKit merge mid-session heals

    /// **Expected RED today, GREEN after fix.**
    ///
    /// Frames the two-context tie (T3) as the CloudKit merge scenario:
    /// the viewContext has a task loaded, then a background CloudKit merge
    /// delivers a new task with the same position.  A subsequent drag into
    /// that gap should heal post-fix.
    @Test("CloudKit merge: remote tie merged between load and drop is healed on reorder")
    func cloudKitMergeHealed() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)

        // Create parent P and task A (gets position 1.0).
        let parentID = try await store.create(title: "P")
        let a = try await store.create(title: "A", parent: parentID)

        // Create a "local" task X at position 2.0 via the store's normal path.
        let xID = UUID()
        let ctx = p.container.viewContext
        try await ctx.perform {
            let parentReq = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            parentReq.predicate = NSPredicate(format: "id == %@", parentID as CVarArg)
            parentReq.fetchLimit = 1
            let parentObj = try ctx.fetch(parentReq).first

            let x = LillistTask(context: ctx)
            x.id = xID
            x.title = "X"
            x.status = .todo
            x.position = 2.0
            x.startHasTime = false
            x.deadlineHasTime = false
            x.isPinned = false
            x.createdAt = Date()
            x.modifiedAt = x.createdAt
            x.parent = parentObj
            try ctx.save()
        }

        // Simulate a CloudKit merge: a background context (as if CloudKit pushed
        // a record) inserts a second task Y with the same position 2.0.
        let yID = UUID()
        let ctxB = p.container.newBackgroundContext()
        ctxB.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        try await ctxB.perform {
            let parentReq = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            parentReq.predicate = NSPredicate(format: "id == %@", parentID as CVarArg)
            parentReq.fetchLimit = 1
            let parentObj = try ctxB.fetch(parentReq).first

            let y = LillistTask(context: ctxB)
            y.id = yID
            y.title = "Y (CloudKit)"
            y.status = .todo
            y.position = 2.0   // same position as X — the tie the merge produces
            y.startHasTime = false
            y.deadlineHasTime = false
            y.isPinned = false
            y.createdAt = Date()
            y.modifiedAt = y.createdAt
            y.parent = parentObj
            try ctxB.save()
        }

        // Refresh the viewContext so it sees the merged object.
        await ctx.perform { ctx.refreshAllObjects() }

        // A=1.0, X=2.0, Y=2.0 (X and Y tied — exactly as after a real CK push).
        // Drag A into the gap between X and Y.
        // Post-fix: should heal and NOT throw; positions strictly increasing.
        try await store.reorder(id: a, after: xID, before: yID)

        let children = try await store.children(of: parentID)
        let positions = children.map(\.position)

        // Strictly increasing.
        for i in 1..<positions.count {
            #expect(positions[i] > positions[i - 1], "positions must be strictly increasing after CloudKit-merge heal")
        }

        // A must appear between X and Y.
        let xIdx = try #require(children.firstIndex(where: { $0.id == xID }))
        let aIdx = try #require(children.firstIndex(where: { $0.id == a }))
        let yIdx = try #require(children.firstIndex(where: { $0.id == yID }))
        #expect(aIdx > xIdx, "A should be after X")
        #expect(aIdx < yIdx, "A should be before Y")
    }
}
