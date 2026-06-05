import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge.WatchHandler")
struct WatchHandlerTests {
    private func record(_ id: UUID, _ title: String, status: Status = .todo) -> TaskStore.TaskRecord {
        TaskStore.TaskRecord(
            id: id, title: title, notes: "", status: status,
            start: nil, startHasTime: false, deadline: nil, deadlineHasTime: false,
            position: 1.0, isPinned: false, parentID: nil,
            createdAt: nil, modifiedAt: nil, closedAt: nil, deletedAt: nil
        )
    }

    @Test("First evaluation emits every current record as an update")
    func initialEmitsAll() {
        let a = record(UUID(), "A")
        let b = record(UUID(), "B")
        let (toEmit, next) = CLIBridge.WatchHandler.snapshotStep(previous: nil, current: [a, b])
        #expect(toEmit.map(\.id) == [a.id, b.id])
        #expect(next.count == 2)
    }

    @Test("Unchanged set emits nothing (dedup)")
    func unchangedDedup() {
        let a = record(UUID(), "A")
        let (_, after1) = CLIBridge.WatchHandler.snapshotStep(previous: nil, current: [a])
        let (toEmit, _) = CLIBridge.WatchHandler.snapshotStep(previous: after1, current: [a])
        #expect(toEmit.isEmpty)
    }

    @Test("A changed record re-emits; unchanged siblings stay quiet")
    func changedReemits() {
        let aID = UUID()
        let bID = UUID()
        let a = record(aID, "A")
        let b = record(bID, "B")
        let (_, after1) = CLIBridge.WatchHandler.snapshotStep(previous: nil, current: [a, b])
        let aChanged = record(aID, "A", status: .started)
        let (toEmit, _) = CLIBridge.WatchHandler.snapshotStep(previous: after1, current: [aChanged, b])
        #expect(toEmit.map(\.id) == [aID])
    }

    @Test("A newly matching record emits as an update")
    func newMatchEmits() {
        let aID = UUID()
        let a = record(aID, "A")
        let (_, after1) = CLIBridge.WatchHandler.snapshotStep(previous: nil, current: [a])
        let bID = UUID()
        let b = record(bID, "B")
        let (toEmit, _) = CLIBridge.WatchHandler.snapshotStep(previous: after1, current: [a, b])
        #expect(toEmit.map(\.id) == [bID])
    }
}
