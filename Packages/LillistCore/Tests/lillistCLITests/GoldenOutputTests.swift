import Testing
import Foundation
@testable import LillistCore
@testable import lillist_cli

@Suite("Golden output snapshots")
struct GoldenOutputTests {
    private func snapshot(named: String) throws -> String {
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

    @Test("Flat ls matches snapshot")
    func lsFlat() throws {
        let records = [
            record("Alpha", position: 1),
            record("Beta", position: 2),
            record("Gamma", position: 3)
        ]
        let rendered = CLIBridge.TaskRenderer.prettyTree(records, color: false)
        #expect(normalize(rendered) == normalize(try snapshot(named: "ls-flat")))
    }

    @Test("Nested ls matches snapshot")
    func lsNested() throws {
        let parent = record("Project", position: 1)
        let s1 = record("Step 1", parentID: parent.id, position: 1)
        let s2 = record("Step 2", parentID: parent.id, position: 2, status: .started)
        let rendered = CLIBridge.TaskRenderer.prettyTree([parent, s1, s2], color: false)
        #expect(normalize(rendered) == normalize(try snapshot(named: "ls-nested")))
    }

    @Test("Tags tree matches snapshot")
    func tagsTree() throws {
        let work = TagStore.TagRecord(id: UUID(), name: "Work", tintColor: nil, parentID: nil, position: 1)
        let email = TagStore.TagRecord(id: UUID(), name: "Email", tintColor: nil, parentID: work.id, position: 1)
        let home = TagStore.TagRecord(id: UUID(), name: "Home", tintColor: nil, parentID: nil, position: 2)
        let rendered = CLIBridge.TagRenderer.prettyTree([work, email, home], color: false)
        #expect(normalize(rendered) == normalize(try snapshot(named: "tags-tree")))
    }
}
