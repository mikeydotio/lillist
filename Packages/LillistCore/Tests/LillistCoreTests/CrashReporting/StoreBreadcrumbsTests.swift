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

    @Test("AttachmentStore.addImage records an attachment.attach success breadcrumb")
    func attachmentAttach_recordsSuccess() async throws {
        let persistence = try await TestStore.make()
        let tasks = TaskStore(persistence: persistence)
        let store = AttachmentStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        let task = try await tasks.create(title: "T")
        let png = Data([
            0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,
            0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
            0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,
            0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,
            0x89,0x00,0x00,0x00,0x0D,0x49,0x44,0x41,
            0x54,0x78,0x9C,0x63,0x00,0x01,0x00,0x00,
            0x05,0x00,0x01,0x0D,0x0A,0x2D,0xB4,0x00,
            0x00,0x00,0x00,0x49,0x45,0x4E,0x44,0xAE,
            0x42,0x60,0x82
        ])
        _ = try await store.addImage(taskID: task, filename: "snap.png", data: png)
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "attachment.attach" && $0.success }))
    }

    @Test("Failed AttachmentStore.addImage records an attachment.attach failure breadcrumb")
    func attachmentAttach_recordsFailure() async throws {
        let persistence = try await TestStore.make()
        let store = AttachmentStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        do {
            // No such task — fetchTask throws .notFound inside the perform.
            _ = try await store.addImage(taskID: UUID(), filename: "orphan.png", data: Data([0x00]))
            Issue.record("Expected notFound failure")
        } catch {
            // Expected.
        }
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "attachment.attach" && !$0.success }))
    }

    @Test("TaskStore.hardDelete records a task.purge success breadcrumb")
    func taskHardDelete_recordsSuccess() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        let id = try await store.create(title: "T")
        try await store.hardDelete(id: id)
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "task.purge" && $0.success }))
    }

    @Test("Failed TaskStore.hardDelete records a task.purge failure breadcrumb")
    func taskHardDelete_recordsFailure() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        do {
            try await store.hardDelete(id: UUID())
            Issue.record("Expected notFound failure")
        } catch {
            // Expected.
        }
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "task.purge" && !$0.success }))
    }

    @Test("TaskStore.softDelete records a task.delete success breadcrumb")
    func taskSoftDelete_recordsSuccess() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        let id = try await store.create(title: "T")
        try await store.softDelete(id: id)
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "task.delete" && $0.success }))
    }

    @Test("Failed TaskStore.softDelete records a task.delete failure breadcrumb")
    func taskSoftDelete_recordsFailure() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        do {
            try await store.softDelete(id: UUID())
            Issue.record("Expected notFound failure")
        } catch {
            // Expected.
        }
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "task.delete" && !$0.success }))
    }

    @Test("TaskStore.restore records a task.restore success breadcrumb")
    func taskRestore_recordsSuccess() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        let id = try await store.create(title: "T")
        try await store.softDelete(id: id)
        try await store.restore(id: id)
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "task.restore" && $0.success }))
    }

    @Test("Failed TaskStore.restore records a task.restore failure breadcrumb")
    func taskRestore_recordsFailure() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        do {
            try await store.restore(id: UUID())
            Issue.record("Expected notFound failure")
        } catch {
            // Expected.
        }
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "task.restore" && !$0.success }))
    }

    @Test("TaskStore.reparent records a task.move success breadcrumb")
    func taskReparent_recordsSuccess() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        let parent = try await store.create(title: "Parent")
        let child = try await store.create(title: "Child")
        try await store.reparent(id: child, newParent: parent)
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "task.move" && $0.success }))
    }

    @Test("Failed TaskStore.reparent records a task.move failure breadcrumb")
    func taskReparent_recordsFailure() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        do {
            // No such task — fetchManagedObject throws .notFound inside the perform.
            try await store.reparent(id: UUID(), newParent: nil)
            Issue.record("Expected notFound failure")
        } catch {
            // Expected.
        }
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "task.move" && !$0.success }))
    }

    @Test("TaskStore.transition records a task.status.change success breadcrumb")
    func taskTransition_recordsSuccess() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        let id = try await store.create(title: "T")
        try await store.transition(id: id, to: .started)
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "task.status.change" && $0.success }))
    }

    @Test("Failed TaskStore.transition records a task.status.change failure breadcrumb")
    func taskTransition_recordsFailure() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        do {
            try await store.transition(id: UUID(), to: .started)
            Issue.record("Expected notFound failure")
        } catch {
            // Expected.
        }
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "task.status.change" && !$0.success }))
    }
}
