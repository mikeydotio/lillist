import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge.TagRenderer")
struct TagRendererTests {
    private func make(_ name: String, parent: UUID? = nil) -> TagStore.TagRecord {
        TagStore.TagRecord(id: UUID(), name: name, tintColor: nil, parentID: parent, position: 1.0)
    }

    @Test("Pretty tree nests by parent")
    func prettyNested() {
        let work = make("Work")
        let email = make("Email", parent: work.id)
        let s = CLIBridge.TagRenderer.prettyTree([work, email], color: false)
        let lines = s.split(separator: "\n").map(String.init)
        #expect(lines.contains { $0.contains("Work") && $0.hasPrefix("#") })
        #expect(lines.contains { $0.contains("Email") && $0.hasPrefix("  #") })
    }

    @Test("JSON serializes tags")
    func json() throws {
        let data = try CLIBridge.TagRenderer.json([make("Work")])
        let obj = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        #expect(obj?.first?["name"] as? String == "Work")
    }
}
