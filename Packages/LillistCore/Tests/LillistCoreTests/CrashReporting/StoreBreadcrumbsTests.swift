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
}
