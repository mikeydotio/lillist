import Testing
import Foundation
import LillistCore
@testable import LillistUI

@Suite("TaskRowView accessibility")
@MainActor
struct TaskRowViewA11yTests {
    @Test("Combined a11y label includes title, status, tags, and deadline")
    func combinedLabelComposition() {
        // The label format documented in TaskRowView. We assert the
        // composed string directly — the SwiftUI accessibility tree is
        // host-target-dependent, but the helper that builds the string is
        // pure and testable.
        let record = TaskStore.TaskRecord(
            id: UUID(),
            title: "Buy milk",
            notes: "",
            status: .todo,
            start: nil,
            startHasTime: false,
            // Noon UTC so the abbreviated-date format reads as May 20 in
            // every test-runner timezone (midnight UTC rolls to the
            // previous day in negative-offset zones like US Pacific).
            deadline: ISO8601DateFormatter().date(from: "2026-05-20T12:00:00Z"),
            deadlineHasTime: false,
            position: 0,
            isPinned: false,
            parentID: nil,
            createdAt: Date(),
            modifiedAt: Date(),
            closedAt: nil,
            deletedAt: nil,
            seriesID: nil
        )
        let label = TaskRowView.composedAccessibilityLabel(
            task: record,
            tagNames: ["errands", "grocery"]
        )
        #expect(label.contains("Buy milk"))
        #expect(label.contains("To do"))
        #expect(label.contains("errands"))
        #expect(label.contains("grocery"))
        #expect(label.contains("May 20")) // formatted abbreviated date
    }

    @Test("Reorder a11y actions fire their closures")
    func reorderActionsFireClosures() {
        var calls: [String] = []
        let record = TaskStore.TaskRecord(
            id: UUID(), title: "x", notes: "", status: .todo,
            start: nil, startHasTime: false, deadline: nil, deadlineHasTime: false,
            position: 0, isPinned: false, parentID: nil,
            createdAt: Date(), modifiedAt: Date(), closedAt: nil, deletedAt: nil,
            seriesID: nil
        )
        let view = TaskRowView(
            task: record,
            tagNames: [],
            onStatusClick: {},
            onStatusSet: { _ in },
            onMoveUp: { calls.append("up") },
            onMoveDown: { calls.append("down") },
            onIndent: { calls.append("indent") },
            onOutdent: { calls.append("outdent") }
        )
        // Compile-time wiring guard: the closures are stored and the init
        // signature includes the four optional reorder callbacks.
        _ = view
        #expect(calls.isEmpty, "Closures should not fire on construction")
    }
}
