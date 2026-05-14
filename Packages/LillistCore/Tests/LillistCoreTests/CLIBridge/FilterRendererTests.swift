import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge.FilterRenderer")
struct FilterRendererTests {
    @Test("Renders saved filter list with names")
    func listing() {
        let summary = CLIBridge.FilterRenderer.PrettyFilterSummary(
            id: UUID(),
            name: "Today",
            isPinned: true,
            tintColor: nil,
            sortField: .deadline,
            sortAscending: true
        )
        let s = CLIBridge.FilterRenderer.prettyList([summary], color: false)
        #expect(s.contains("Today"))
        #expect(s.contains("pinned"))
    }
}
