import Testing
import Foundation
@testable import LillistCore

@Suite("NotificationSpecStore")
struct NotificationSpecStoreTests {
    @Test("add creates a spec with the given fields")
    func add() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")

        let id = try await specs.add(taskID: taskID, kind: .offsetStart, offsetMinutes: -15, fireDate: nil)
        let record = try await specs.fetch(id: id)
        #expect(record.kind == .offsetStart)
        #expect(record.offsetMinutes == -15)
        #expect(record.taskID == taskID)
    }

    @Test("specs(forTask:) returns all specs for a task, sorted by createdAt")
    func specsForTask() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        _ = try await specs.add(taskID: taskID, kind: .defaultStart, offsetMinutes: nil, fireDate: nil)
        _ = try await specs.add(taskID: taskID, kind: .offsetStart, offsetMinutes: -30, fireDate: nil)
        let all = try await specs.specs(forTask: taskID)
        #expect(all.count == 2)
    }

    @Test("update mutates fields and only saves on commit")
    func update() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let id = try await specs.add(taskID: taskID, kind: .nudge, offsetMinutes: nil, fireDate: Date(timeIntervalSince1970: 1_000_000))

        let newDate = Date(timeIntervalSince1970: 2_000_000)
        try await specs.update(id: id) { draft in
            draft.fireDate = newDate
            draft.snoozedUntil = Date(timeIntervalSince1970: 3_000_000)
        }
        let record = try await specs.fetch(id: id)
        #expect(record.fireDate == newDate)
        #expect(record.snoozedUntil == Date(timeIntervalSince1970: 3_000_000))
    }

    @Test("delete removes the spec")
    func delete() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let id = try await specs.add(taskID: taskID, kind: .nudge, offsetMinutes: nil, fireDate: Date())
        try await specs.delete(id: id)
        await #expect(throws: LillistError.self) {
            _ = try await specs.fetch(id: id)
        }
    }

    @Test("Deleting a task cascades to its specs")
    func cascadeDelete() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let specID = try await specs.add(taskID: taskID, kind: .nudge, offsetMinutes: nil, fireDate: Date())
        try await tasks.hardDelete(id: taskID)
        await #expect(throws: LillistError.self) {
            _ = try await specs.fetch(id: specID)
        }
    }

    @Test("recordLastFired writes lastFiredAt")
    func recordLastFired() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let id = try await specs.add(taskID: taskID, kind: .defaultDeadline, offsetMinutes: nil, fireDate: nil)
        let at = Date(timeIntervalSince1970: 5_000_000)
        try await specs.recordLastFired(id: id, at: at)
        let record = try await specs.fetch(id: id)
        #expect(record.lastFiredAt == at)
    }
}
