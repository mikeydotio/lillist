import XCTest
import CoreData
@testable import LillistCore

final class TaskStoreDiagnosticEmitTests: XCTestCase {
    private func makeStore() async throws -> (TaskStore, SpyDiagnosticSink, PersistenceController) {
        let p = try await PersistenceController(configuration: .inMemory)
        let spy = SpyDiagnosticSink()
        let store = TaskStore(persistence: p)
        store.diagnosticLog = spy
        return (store, spy, p)
    }

    func test_create_emits_task_create_with_assigned_and_observed_positions() async throws {
        let (store, spy, _) = try await makeStore()
        let id1 = try await store.create(title: "first")
        let events1 = await spy.events
        let first = try XCTUnwrap(events1.first { $0.name == "task.create" })
        XCTAssertEqual(first.payload["taskID"], .string(id1.uuidString))
        XCTAssertEqual(first.payload["parentID"], .null)
        XCTAssertEqual(first.payload["observedMaxPosition"], .null, "empty parent: nothing observed")
        XCTAssertNotNil(first.payload["assignedPosition"])

        let id2 = try await store.create(title: "second")
        let events2 = await spy.events
        let second = try XCTUnwrap(events2.last { $0.payload["taskID"] == .string(id2.uuidString) })
        guard case .double(let observed)? = second.payload["observedMaxPosition"] else {
            return XCTFail("second create must record the observed max position")
        }
        XCTAssertGreaterThan(observed, 0)
    }

    func test_successful_reorder_emits_anchor_pair_with_threwError_false() async throws {
        let (store, spy, _) = try await makeStore()
        let a = try await store.create(title: "a")
        let b = try await store.create(title: "b")
        let c = try await store.create(title: "c")
        // Move c between a and b (valid, ascending anchors).
        try await store.reorder(id: c, after: a, before: b)
        let events = await spy.events
        let reorder = try XCTUnwrap(events.last { $0.name == "task.reorder" })
        XCTAssertEqual(reorder.payload["taskID"], .string(c.uuidString))
        XCTAssertEqual(reorder.payload["afterID"], .string(a.uuidString))
        XCTAssertEqual(reorder.payload["beforeID"], .string(b.uuidString))
        XCTAssertEqual(reorder.payload["threwError"], .bool(false))
        XCTAssertNotNil(reorder.payload["computedPosition"])
    }

    func test_throwing_reorder_emits_threwError_true_with_equal_anchor_pair() async throws {
        let (store, spy, p) = try await makeStore()
        let a = try await store.create(title: "a")
        let b = try await store.create(title: "b")
        let c = try await store.create(title: "c")
        // Force a degenerate tie: a and b at the same position. A reorder of c
        // between them must throw "anchors out of order" — the RCA path — and
        // STILL emit a task.reorder with threwError:true and the equal anchors.
        let ctx = p.container.viewContext
        try await ctx.perform {
            for id in [a, b] {
                let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
                req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                try ctx.fetch(req).first!.position = 5.0
            }
            try ctx.save()
        }
        await XCTAssertThrowsErrorAsync(try await store.reorder(id: c, after: a, before: b))
        let events = await spy.events
        let reorder = try XCTUnwrap(events.last { $0.name == "task.reorder" })
        XCTAssertEqual(reorder.payload["threwError"], .bool(true))
        XCTAssertEqual(reorder.payload["afterPosition"], .double(5.0))
        XCTAssertEqual(reorder.payload["beforePosition"], .double(5.0))
    }

    func test_cycle_throwing_reorder_still_emits_threwError_true() async throws {
        let (store, spy, _) = try await makeStore()
        let parent = try await store.create(title: "parent")
        let child = try await store.create(title: "child")
        try await store.reparent(id: child, newParent: parent)
        // Reorder the parent under its own child → cycle guard throws. The emit
        // must still fire on this non-tie throwing path.
        await XCTAssertThrowsErrorAsync(try await store.reorder(id: parent, after: child, before: nil))
        let events = await spy.events
        let reorder = try XCTUnwrap(events.last { $0.name == "task.reorder" && $0.payload["taskID"] == .string(parent.uuidString) })
        XCTAssertEqual(reorder.payload["threwError"], .bool(true))
    }

    func test_cross_parent_throwing_reorder_still_emits_threwError_true() async throws {
        let (store, spy, _) = try await makeStore()
        let p1 = try await store.create(title: "p1")
        let p2 = try await store.create(title: "p2")
        let a = try await store.create(title: "a"); try await store.reparent(id: a, newParent: p1)
        let b = try await store.create(title: "b"); try await store.reparent(id: b, newParent: p2)
        let mover = try await store.create(title: "mover")
        // Anchors with different parents → "must share the same parent" throws.
        await XCTAssertThrowsErrorAsync(try await store.reorder(id: mover, after: a, before: b))
        let events = await spy.events
        let reorder = try XCTUnwrap(events.last { $0.name == "task.reorder" && $0.payload["taskID"] == .string(mover.uuidString) })
        XCTAssertEqual(reorder.payload["threwError"], .bool(true))
    }

    func test_reparent_emits_task_reparent_with_parents_and_position() async throws {
        let (store, spy, _) = try await makeStore()
        let parent = try await store.create(title: "parent")
        let child = try await store.create(title: "child")
        try await store.reparent(id: child, newParent: parent)
        let events = await spy.events
        let reparent = try XCTUnwrap(events.last { $0.name == "task.reparent" })
        XCTAssertEqual(reparent.payload["taskID"], .string(child.uuidString))
        XCTAssertEqual(reparent.payload["oldParentID"], .null)
        XCTAssertEqual(reparent.payload["newParentID"], .string(parent.uuidString))
        XCTAssertNotNil(reparent.payload["assignedPosition"])
    }
}

/// Small async throwing assertion helper (XCTAssertThrowsError isn't async).
func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("expected an error to be thrown", file: file, line: line)
    } catch {
        // expected
    }
}
