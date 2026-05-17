import Testing
import LillistCore
import Foundation

/// Plan 19 Task 7: TaskListView resolves SidebarSelection to the actual
/// source name (filter/tag/pinned-task title). The resolver itself is a
/// pure async function on TaskListView that the view's .task hook calls
/// when `anchorIdentity` changes; this suite exercises it directly via
/// the `SidebarSelection`-shape struct co-compiled into the test bundle.
@Suite("TaskListView.sourceTitle resolves actual names")
struct TaskListSourceTitleTests {
    private func make() async throws -> (TaskStore, TagStore, SmartFilterStore) {
        let p = try await PersistenceController(configuration: .inMemory)
        return (TaskStore(persistence: p), TagStore(persistence: p), SmartFilterStore(persistence: p))
    }

    @Test("Pinned task selection resolves to the task's title")
    func pinnedTaskTitle() async throws {
        let (tasks, tags, filters) = try await make()
        let id = try await tasks.create(title: "Buy milk")
        try await tasks.update(id: id) { $0.isPinned = true }
        let title = await SourceTitleResolver.resolve(
            for: .pinnedTask(id), taskStore: tasks, tagStore: tags, smartFilterStore: filters)
        #expect(title == "Buy milk")
    }

    @Test("Tag selection resolves to the tag name")
    func tagName() async throws {
        let (tasks, tags, filters) = try await make()
        let id = try await tags.create(name: "groceries")
        let title = await SourceTitleResolver.resolve(
            for: .tag(id), taskStore: tasks, tagStore: tags, smartFilterStore: filters)
        #expect(title == "groceries")
    }

    @Test("Filter selection resolves to the filter name")
    func filterName() async throws {
        let (tasks, tags, filters) = try await make()
        let group = PredicateGroup(combinator: .all, predicates: [])
        let id = try await filters.create(name: "Today", group: group)
        let title = await SourceTitleResolver.resolve(
            for: .filter(id), taskStore: tasks, tagStore: tags, smartFilterStore: filters)
        #expect(title == "Today")
    }

    @Test("Pinned filter selection resolves to the filter name")
    func pinnedFilterName() async throws {
        let (tasks, tags, filters) = try await make()
        let group = PredicateGroup(combinator: .all, predicates: [])
        let id = try await filters.create(name: "Inbox", group: group)
        let title = await SourceTitleResolver.resolve(
            for: .pinnedFilter(id), taskStore: tasks, tagStore: tags, smartFilterStore: filters)
        #expect(title == "Inbox")
    }

    @Test("Trash returns 'Trash'")
    func trash() async throws {
        let (tasks, tags, filters) = try await make()
        let title = await SourceTitleResolver.resolve(
            for: .trash, taskStore: tasks, tagStore: tags, smartFilterStore: filters)
        #expect(title == "Trash")
    }

    @Test("Missing tag falls back to 'Tag'")
    func tagFallback() async throws {
        let (tasks, tags, filters) = try await make()
        let bogus = UUID()
        let title = await SourceTitleResolver.resolve(
            for: .tag(bogus), taskStore: tasks, tagStore: tags, smartFilterStore: filters)
        #expect(title == "Tag")
    }
}
