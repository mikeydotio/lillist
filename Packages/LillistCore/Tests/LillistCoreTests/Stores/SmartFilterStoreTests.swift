import Testing
import Foundation
@testable import LillistCore

@Suite("SmartFilterStore — CRUD")
struct SmartFilterStoreCRUDTests {
    private func sampleGroup() -> PredicateGroup {
        .init(combinator: .all, predicates: [
            .leaf(.init(field: .status, op: .is, value: .statusSet([.todo])))
        ])
    }

    @Test("Create returns an id and the row is fetchable")
    func createAndFetch() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        let id = try await store.create(name: "Today", group: sampleGroup())
        let rec = try await store.fetch(id: id)
        #expect(rec.name == "Today")
        #expect(rec.group.combinator == .all)
        #expect(rec.group.predicates.count == 1)
    }

    @Test("Create rejects empty name")
    func emptyNameRejected() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        await #expect(throws: LillistError.self) {
            _ = try await store.create(name: "  ", group: PredicateGroup(combinator: .all, predicates: []))
        }
    }

    @Test("Fetch unknown id throws notFound")
    func fetchNotFound() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        await #expect(throws: LillistError.notFound) {
            _ = try await store.fetch(id: UUID())
        }
    }

    @Test("List returns rows in position order")
    func listOrder() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        let a = try await store.create(name: "A", group: sampleGroup())
        let b = try await store.create(name: "B", group: sampleGroup())
        let c = try await store.create(name: "C", group: sampleGroup())
        let list = try await store.list()
        #expect(list.map(\.id) == [a, b, c])
    }

    @Test("Update mutates fields")
    func update() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        let id = try await store.create(name: "Today", group: sampleGroup())
        try await store.update(id: id) { draft in
            draft.name = "Today (renamed)"
            draft.tintColor = "#ff8800"
            draft.sortField = .deadline
            draft.sortAscending = false
        }
        let r = try await store.fetch(id: id)
        #expect(r.name == "Today (renamed)")
        #expect(r.tintColor == "#ff8800")
        #expect(r.sortField == .deadline)
        #expect(r.sortAscending == false)
    }

    @Test("Update can replace the predicate group")
    func updateGroup() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        let id = try await store.create(name: "X", group: sampleGroup())
        let newGroup = PredicateGroup(combinator: .any, predicates: [
            .leaf(.init(field: .isPinned, op: .is, value: .bool(true)))
        ])
        try await store.update(id: id) { d in d.group = newGroup }
        let r = try await store.fetch(id: id)
        #expect(r.group.combinator == .any)
    }

    @Test("Delete removes the row")
    func delete() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        let id = try await store.create(name: "X", group: sampleGroup())
        try await store.delete(id: id)
        await #expect(throws: LillistError.notFound) {
            _ = try await store.fetch(id: id)
        }
    }
}

@Suite("SmartFilterStore — pinning and reorder")
struct SmartFilterStorePinReorderTests {
    private func sample() -> PredicateGroup {
        .init(combinator: .all, predicates: [])
    }

    @Test("setPinned toggles isPinned")
    func setPinned() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        let id = try await store.create(name: "X", group: sample())
        try await store.setPinned(id: id, pinned: true)
        #expect(try await store.fetch(id: id).isPinned == true)
        try await store.setPinned(id: id, pinned: false)
        #expect(try await store.fetch(id: id).isPinned == false)
    }

    @Test("reorder moves a row between two siblings")
    func reorder() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        let a = try await store.create(name: "A", group: sample())
        let b = try await store.create(name: "B", group: sample())
        let c = try await store.create(name: "C", group: sample())
        // Move C between A and B → expected order A, C, B
        try await store.reorder(id: c, after: a, before: b)
        let list = try await store.list()
        #expect(list.map(\.id) == [a, c, b])
    }

    @Test("reorder to head and tail")
    func reorderEdges() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        let a = try await store.create(name: "A", group: sample())
        let b = try await store.create(name: "B", group: sample())
        let c = try await store.create(name: "C", group: sample())
        try await store.reorder(id: c, after: nil, before: a)
        #expect(try await store.list().map(\.id) == [c, a, b])
        try await store.reorder(id: c, after: b, before: nil)
        #expect(try await store.list().map(\.id) == [a, b, c])
    }

    @Test("60 successive same-region inserts keep filter positions strictly increasing")
    func repeatedSameGapInsertsCompact() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        let head = try await store.create(name: "head", group: sample())
        let tail = try await store.create(name: "tail", group: sample())

        for i in 0..<60 {
            let row = try await store.create(name: "row\(i)", group: sample())
            let list = try await store.list()
            let afterID = head
            let beforeID = list.first { $0.id != head && $0.id != row }!.id
            try await store.reorder(id: row, after: afterID, before: beforeID)
        }

        let positions = (try await store.list()).map(\.position)
        for i in 1..<positions.count {
            #expect(positions[i] > positions[i - 1])
        }
        #expect(Set(positions).count == positions.count)
        _ = tail
    }
}

@Suite("SmartFilterStore — evaluate and count")
struct SmartFilterStoreEvaluateTests {
    @Test("evaluate returns TaskRecord ids matching the filter")
    func evaluate() async throws {
        let controller = try await TestStore.make()
        let smartStore = SmartFilterStore(persistence: controller)
        let taskStore = TaskStore(persistence: controller)
        let t1 = try await taskStore.create(title: "Design review")
        let t2 = try await taskStore.create(title: "Write spec")
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .title, op: .contains, value: .string("design")))
        ])
        let fid = try await smartStore.create(name: "Design", group: group)
        let results = try await smartStore.evaluate(id: fid)
        let ids = Set(results.map(\.id))
        #expect(ids.contains(t1))
        #expect(!ids.contains(t2))
    }

    @Test("count returns number of matches")
    func count() async throws {
        let controller = try await TestStore.make()
        let smartStore = SmartFilterStore(persistence: controller)
        let taskStore = TaskStore(persistence: controller)
        _ = try await taskStore.create(title: "Design 1")
        _ = try await taskStore.create(title: "Design 2")
        _ = try await taskStore.create(title: "Other")
        let fid = try await smartStore.create(
            name: "Design",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .title, op: .contains, value: .string("Design")))
            ])
        )
        #expect(try await smartStore.count(id: fid) == 2)
    }

    @Test("evaluate respects sort field and direction")
    func evaluateSort() async throws {
        let controller = try await TestStore.make()
        let smartStore = SmartFilterStore(persistence: controller)
        let taskStore = TaskStore(persistence: controller)
        let cal = Calendar.current
        let now = Date()
        let t1 = try await taskStore.create(title: "B")
        let t2 = try await taskStore.create(title: "A")
        try await taskStore.update(id: t1) { d in d.deadline = cal.date(byAdding: .day, value: 1, to: now) }
        try await taskStore.update(id: t2) { d in d.deadline = cal.date(byAdding: .day, value: 2, to: now) }
        let fid = try await smartStore.create(
            name: "Deadline asc",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .deadline, op: .isSet, value: .bool(true)))
            ]),
            sortField: .deadline,
            sortAscending: true
        )
        let results = try await smartStore.evaluate(id: fid)
        #expect(results.map(\.id) == [t1, t2])
    }

    @Test("evaluate(group:limit:) caps the number of returned rows")
    func evaluateRespectsLimit() async throws {
        let controller = try await TestStore.make()
        let smartStore = SmartFilterStore(persistence: controller)
        let taskStore = TaskStore(persistence: controller)
        for i in 0..<25 {
            _ = try await taskStore.create(title: "Open task \(i)")
        }
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .inTrash, op: .is, value: .bool(false)))
        ])
        let capped = try await smartStore.evaluate(group: group, limit: 20)
        #expect(capped.count == 20)
        let uncapped = try await smartStore.evaluate(group: group)
        #expect(uncapped.count == 25)
    }

    @Test("evaluate(group:) excludes archived rows by default")
    func evaluateExcludesArchivedByDefault() async throws {
        let controller = try await TestStore.make()
        let smartStore = SmartFilterStore(persistence: controller)
        let taskStore = TaskStore(persistence: controller)
        let visible = try await taskStore.create(title: "visible")
        let hidden = try await taskStore.create(title: "hidden")
        _ = try await taskStore.archive(ids: [hidden])

        // Match-everything filter.
        let group = PredicateGroup(combinator: .all, predicates: [])
        let ids = Set(try await smartStore.evaluate(group: group).map(\.id))

        #expect(ids.contains(visible))
        #expect(!ids.contains(hidden))
    }

    @Test("evaluate(group: includeArchived: true) returns archived rows")
    func evaluateIncludesArchivedWhenAsked() async throws {
        let controller = try await TestStore.make()
        let smartStore = SmartFilterStore(persistence: controller)
        let taskStore = TaskStore(persistence: controller)
        let active = try await taskStore.create(title: "active")
        let archived = try await taskStore.create(title: "archived")
        _ = try await taskStore.archive(ids: [archived])

        let group = PredicateGroup(combinator: .all, predicates: [])
        let ids = Set(try await smartStore.evaluate(group: group, includeArchived: true).map(\.id))

        #expect(ids.contains(active))
        #expect(ids.contains(archived))
    }

    @Test("evaluate(id:) (persisted filter) always excludes archived rows")
    func persistedFilterExcludesArchived() async throws {
        let controller = try await TestStore.make()
        let smartStore = SmartFilterStore(persistence: controller)
        let taskStore = TaskStore(persistence: controller)
        let visible = try await taskStore.create(title: "visible")
        let hidden = try await taskStore.create(title: "hidden")
        _ = try await taskStore.archive(ids: [hidden])

        let fid = try await smartStore.create(
            name: "All",
            group: PredicateGroup(combinator: .all, predicates: [])
        )
        let ids = Set(try await smartStore.evaluate(id: fid).map(\.id))

        #expect(ids.contains(visible))
        #expect(!ids.contains(hidden))
    }

    @Test("SmartFilter evaluate result surfaces seriesID for recurring tasks")
    func evaluateSurfacesSeriesID() async throws {
        let persistence = try await TestStore.make()
        let tasks = TaskStore(persistence: persistence)
        let series = SeriesStore(persistence: persistence)
        let smart = SmartFilterStore(persistence: persistence)

        let taskID = try await tasks.create(title: "recurring")
        let seriesID = try await series.create(
            fromSeedTask: taskID,
            rule: .calendar(.init(freq: .daily, interval: 1))
        )

        // Match-everything filter.
        let group = PredicateGroup(combinator: .all, predicates: [])
        let filterID = try await smart.create(name: "All", group: group)
        let results = try await smart.evaluate(id: filterID)

        let recurring = results.first { $0.id == taskID }
        #expect(recurring?.seriesID == seriesID)
    }
}
