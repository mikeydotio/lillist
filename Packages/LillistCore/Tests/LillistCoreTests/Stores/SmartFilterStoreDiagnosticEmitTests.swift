import XCTest
import CoreData
@testable import LillistCore

final class SmartFilterStoreDiagnosticEmitTests: XCTestCase {
    private func makeStore() async throws -> (SmartFilterStore, SpyDiagnosticSink, PersistenceController) {
        let p = try await PersistenceController(configuration: .inMemory)
        let spy = SpyDiagnosticSink()
        let store = SmartFilterStore(persistence: p)
        store.diagnosticLog = spy
        return (store, spy, p)
    }

    private func makeFilter(_ store: SmartFilterStore, _ name: String) async throws -> UUID {
        try await store.create(name: name, group: PredicateGroup(combinator: .all, predicates: []))
    }

    func test_successful_reorder_emits_filter_reorder_with_threwError_false() async throws {
        let (store, spy, _) = try await makeStore()
        let a = try await makeFilter(store, "a")
        let b = try await makeFilter(store, "b")
        let c = try await makeFilter(store, "c")
        try await store.reorder(id: c, after: a, before: b)
        let events = await spy.events
        let reorder = try XCTUnwrap(events.last { $0.name == "filter.reorder" })
        XCTAssertEqual(reorder.payload["filterID"], .string(c.uuidString))
        XCTAssertEqual(reorder.payload["threwError"], .bool(false))
        XCTAssertNotNil(reorder.payload["computedPosition"])
    }

    func test_healing_reorder_emits_filter_reorder_with_threwError_false() async throws {
        let (store, spy, p) = try await makeStore()
        let a = try await makeFilter(store, "a")
        let b = try await makeFilter(store, "b")
        let c = try await makeFilter(store, "c")
        // Equal-anchor pairs now HEAL (recompact → re-check passes). The emit
        // fires on the success path with threwError:false, but the pre-heal
        // anchor positions (5.0 / 5.0) are still recorded — they were captured
        // before recompaction mutated them.
        let ctx = p.container.viewContext
        try await ctx.perform {
            for id in [a, b] {
                let req = NSFetchRequest<SmartFilter>(entityName: "SmartFilter")
                req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                try ctx.fetch(req).first!.position = 5.0
            }
            try ctx.save()
        }
        try await store.reorder(id: c, after: a, before: b)
        let events = await spy.events
        let reorder = try XCTUnwrap(events.last { $0.name == "filter.reorder" })
        XCTAssertEqual(reorder.payload["threwError"], .bool(false))
        XCTAssertEqual(reorder.payload["afterPosition"], .double(5.0))
        XCTAssertEqual(reorder.payload["beforePosition"], .double(5.0))
    }
}
