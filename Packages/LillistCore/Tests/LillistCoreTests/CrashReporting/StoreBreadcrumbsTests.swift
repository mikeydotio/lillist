import Testing
import Foundation
@testable import LillistCore

@Suite("Store breadcrumbs")
struct StoreBreadcrumbsTests {
    @Test("TaskStore.create records a task.create breadcrumb on success")
    func taskCreate_recordsCrumb() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        _ = try await store.create(title: "test")
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "task.create" && $0.success }))
    }

    @Test("Failed TaskStore.create records a failure breadcrumb")
    func taskCreate_recordsFailure() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        do {
            _ = try await store.create(title: "")
            Issue.record("Expected validation failure")
        } catch {
            // Expected.
        }
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "task.create" && !$0.success }))
    }

    @Test("TagStore.create records a tag.create breadcrumb")
    func tagCreate_recordsCrumb() async throws {
        let persistence = try await TestStore.make()
        let store = TagStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        _ = try await store.create(name: "Work")
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "tag.create" && $0.success }))
    }

    @Test("TaskStore with nil breadcrumbs sink does not throw")
    func nilBuffer_isNoOp() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        // No buffer set.
        _ = try await store.create(title: "no-crumb")
        // Nothing to assert beyond "didn't throw".
    }

    @Test("JournalStore.appendNote records a journal.append success breadcrumb")
    func journalAppend_recordsSuccess() async throws {
        let persistence = try await TestStore.make()
        let tasks = TaskStore(persistence: persistence)
        let journals = JournalStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        journals.breadcrumbs = buffer
        let task = try await tasks.create(title: "T")
        _ = try await journals.appendNote(taskID: task, body: "note")
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "journal.append" && $0.success }))
    }

    @Test("Failed JournalStore.appendNote records a journal.append failure breadcrumb")
    func journalAppend_recordsFailure() async throws {
        let persistence = try await TestStore.make()
        let journals = JournalStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        journals.breadcrumbs = buffer
        do {
            // No such task — fetchTask throws .notFound inside the perform.
            _ = try await journals.appendNote(taskID: UUID(), body: "orphan")
            Issue.record("Expected notFound failure")
        } catch {
            // Expected.
        }
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "journal.append" && !$0.success }))
    }

    @Test("TagStore.rename records a tag.rename success breadcrumb")
    func tagRename_recordsSuccess() async throws {
        let persistence = try await TestStore.make()
        let store = TagStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        let id = try await store.create(name: "Old")
        try await store.rename(id: id, to: "New")
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "tag.rename" && $0.success }))
    }

    @Test("Failed TagStore.rename records a tag.rename failure breadcrumb")
    func tagRename_recordsFailure() async throws {
        let persistence = try await TestStore.make()
        let store = TagStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        do {
            // No such tag — fetchManagedObject throws .notFound inside the perform.
            try await store.rename(id: UUID(), to: "Ghost")
            Issue.record("Expected notFound failure")
        } catch {
            // Expected.
        }
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "tag.rename" && !$0.success }))
    }

    @Test("TagStore.delete records a tag.delete success breadcrumb")
    func tagDelete_recordsSuccess() async throws {
        let persistence = try await TestStore.make()
        let store = TagStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        let id = try await store.create(name: "Doomed")
        try await store.delete(id: id)
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "tag.delete" && $0.success }))
    }

    @Test("Failed TagStore.delete records a tag.delete failure breadcrumb")
    func tagDelete_recordsFailure() async throws {
        let persistence = try await TestStore.make()
        let store = TagStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        do {
            try await store.delete(id: UUID())
            Issue.record("Expected notFound failure")
        } catch {
            // Expected.
        }
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "tag.delete" && !$0.success }))
    }
}
