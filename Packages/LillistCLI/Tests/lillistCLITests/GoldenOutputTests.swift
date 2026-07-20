import Testing
import Foundation
@testable import LillistCore
@testable import lillist_cli

@Suite("Golden output snapshots")
struct GoldenOutputTests {
    // Fixed inputs so structured-output goldens are byte-stable.
    private static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14T22:13:20Z
    private static let id1 = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let id2 = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    private func snapshotData(named: String) throws -> String {
        let url = Bundle.module.url(forResource: named, withExtension: "txt", subdirectory: "snapshots")
            ?? Bundle.module.url(forResource: named, withExtension: "txt")
        guard let url else {
            throw NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "missing snapshot \(named)"])
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func record(_ title: String, parentID: UUID? = nil, position: Double = 1.0, status: Status = .todo) -> TaskStore.TaskRecord {
        TaskStore.TaskRecord(
            id: UUID(), title: title, notes: "", status: status,
            start: nil, startHasTime: false, deadline: nil, deadlineHasTime: false,
            position: position, isPinned: false, parentID: parentID,
            createdAt: nil, modifiedAt: nil, closedAt: nil, deletedAt: nil
        )
    }

    // Fixed-input task records used by the structured-output goldens.
    private func goldenTasks() -> [TaskStore.TaskRecord] {
        [
            TaskStore.TaskRecord(
                id: Self.id1, title: "Buy\tmilk", notes: "", status: .todo,
                start: Self.fixedDate, startHasTime: true, deadline: nil, deadlineHasTime: false,
                position: 1.0, isPinned: false, parentID: nil,
                createdAt: Self.fixedDate, modifiedAt: Self.fixedDate, closedAt: nil, deletedAt: nil
            ),
            TaskStore.TaskRecord(
                id: Self.id2, title: "Plain", notes: "", status: .closed,
                start: nil, startHasTime: false, deadline: nil, deadlineHasTime: false,
                position: 2.0, isPinned: true, parentID: Self.id1,
                createdAt: Self.fixedDate, modifiedAt: Self.fixedDate, closedAt: Self.fixedDate, deletedAt: nil
            )
        ]
    }

    private func goldenTags() -> [TagStore.TagRecord] {
        [
            TagStore.TagRecord(id: Self.id1, name: "Wo\trk", tintColor: "#FF0000", parentID: nil, position: 1.0),
            TagStore.TagRecord(id: Self.id2, name: "Email", tintColor: nil, parentID: Self.id1, position: 2.0)
        ]
    }

    private func goldenJournal() -> [JournalStore.JournalRecord] {
        [
            JournalStore.JournalRecord(
                id: Self.id1, taskID: Self.id2, kind: .note, body: "first note",
                payload: nil, createdAt: Self.fixedDate, editedAt: nil
            )
        ]
    }

    // MARK: - Pretty tree (existing, normalized)

    @Test("Flat ls matches snapshot")
    func lsFlat() throws {
        let records = [
            record("Alpha", position: 1),
            record("Beta", position: 2),
            record("Gamma", position: 3)
        ]
        let rendered = CLIBridge.TaskRenderer.prettyTree(records, color: false)
        #expect(normalize(rendered) == normalize(try snapshotData(named: "ls-flat")))
    }

    @Test("Nested ls matches snapshot")
    func lsNested() throws {
        let parent = record("Project", position: 1)
        let s1 = record("Step 1", parentID: parent.id, position: 1)
        let s2 = record("Step 2", parentID: parent.id, position: 2, status: .started)
        let rendered = CLIBridge.TaskRenderer.prettyTree([parent, s1, s2], color: false)
        #expect(normalize(rendered) == normalize(try snapshotData(named: "ls-nested")))
    }

    @Test("Tags tree matches snapshot")
    func tagsTree() throws {
        let work = TagStore.TagRecord(id: UUID(), name: "Work", tintColor: nil, parentID: nil, position: 1)
        let email = TagStore.TagRecord(id: UUID(), name: "Email", tintColor: nil, parentID: work.id, position: 1)
        let home = TagStore.TagRecord(id: UUID(), name: "Home", tintColor: nil, parentID: nil, position: 2)
        let rendered = CLIBridge.TagRenderer.prettyTree([work, email, home], color: false)
        #expect(normalize(rendered) == normalize(try snapshotData(named: "tags-tree")))
    }

    // MARK: - Structured output (new, byte-exact)

    @Test("Task JSON is byte-exact")
    func taskJSON() throws {
        let rendered = try CLIBridge.TaskRenderer.jsonString(goldenTasks())
        #expect(rendered == (try snapshotData(named: "task-json")))
    }

    @Test("Task NDJSON is byte-exact")
    func taskNDJSON() throws {
        let rendered = try CLIBridge.TaskRenderer.ndjson(goldenTasks())
        #expect(rendered == (try snapshotData(named: "task-ndjson")))
    }

    @Test("Task TSV is byte-exact, incl. header and embedded-tab title")
    func taskTSV() throws {
        let rendered = try CLIBridge.TaskRenderer.tsv(goldenTasks())
        #expect(rendered == (try snapshotData(named: "task-tsv")))
    }

    @Test("Tag JSON is byte-exact")
    func tagJSON() throws {
        let data = try CLIBridge.TagRenderer.json(goldenTags())
        let rendered = String(data: data, encoding: .utf8) ?? ""
        #expect(rendered == (try snapshotData(named: "tag-json")))
    }

    @Test("Tag NDJSON is byte-exact")
    func tagNDJSON() throws {
        let rendered = try CLIBridge.TagRenderer.ndjson(goldenTags())
        #expect(rendered == (try snapshotData(named: "tag-ndjson")))
    }

    @Test("Tag TSV is byte-exact, incl. header and embedded-tab name")
    func tagTSV() throws {
        let rendered = CLIBridge.TagRenderer.tsv(goldenTags())
        #expect(rendered == (try snapshotData(named: "tag-tsv")))
    }

    @Test("Journal JSON is byte-exact")
    func journalJSON() throws {
        let data = try CLIBridge.JournalRenderer.json(goldenJournal())
        let rendered = String(data: data, encoding: .utf8) ?? ""
        #expect(rendered == (try snapshotData(named: "journal-json")))
    }
}
