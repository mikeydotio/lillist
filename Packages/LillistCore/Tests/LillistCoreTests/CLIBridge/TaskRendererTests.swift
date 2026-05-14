import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge.TaskRenderer")
struct TaskRendererTests {
    private func make(_ title: String, status: Status = .todo, parentID: UUID? = nil, position: Double = 1.0) -> TaskStore.TaskRecord {
        TaskStore.TaskRecord(
            id: UUID(),
            title: title,
            notes: "",
            status: status,
            start: nil,
            startHasTime: false,
            deadline: nil,
            deadlineHasTime: false,
            position: position,
            isPinned: false,
            parentID: parentID,
            createdAt: Date(),
            modifiedAt: Date(),
            closedAt: nil,
            deletedAt: nil
        )
    }

    @Test("JSON encoding emits stable shape")
    func jsonShape() throws {
        let r = make("Buy milk")
        let data = try CLIBridge.TaskRenderer.json([r])
        let obj = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        #expect(obj?.first?["title"] as? String == "Buy milk")
        #expect(obj?.first?["status"] as? String == "todo")
    }

    @Test("NDJSON emits one JSON object per line")
    func ndjsonShape() throws {
        let lines = try CLIBridge.TaskRenderer.ndjson([make("A"), make("B")])
        let split = lines.split(separator: "\n").map(String.init)
        #expect(split.count == 2)
    }

    @Test("TSV emits header row plus tab-separated rows")
    func tsvShape() throws {
        let s = try CLIBridge.TaskRenderer.tsv([make("A"), make("B")])
        let rows = s.split(separator: "\n").map(String.init)
        #expect(rows.count == 3)
        #expect(rows[0].contains("\t"))
    }

    @Test("Pretty tree renders a single task on one line")
    func prettySingle() {
        let s = CLIBridge.TaskRenderer.prettyTree([make("Buy milk")], color: false)
        #expect(s.contains("Buy milk"))
        #expect(s.hasSuffix("\n"))
    }

    @Test("Pretty tree groups children under parent")
    func prettyNested() {
        let parent = make("Project")
        let child = make("Subtask", parentID: parent.id)
        let s = CLIBridge.TaskRenderer.prettyTree([parent, child], color: false)
        let lines = s.split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines[1].contains("Subtask"))
        #expect(lines[1].hasPrefix(" "))
    }

    @Test("Pretty tree with color emits ANSI codes")
    func prettyColor() {
        let s = CLIBridge.TaskRenderer.prettyTree([make("Buy milk", status: .blocked)], color: true)
        #expect(s.contains("\u{001B}["))
    }
}
