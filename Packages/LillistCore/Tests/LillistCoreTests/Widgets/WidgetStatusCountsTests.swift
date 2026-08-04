import Testing
@testable import LillistCore

/// `LIL-96`: ``WidgetSnapshot/StatusCounts`` — the per-status tally that backs
/// the `systemSmall` status donut. Pure value math; no Core Data involved.
@Suite("WidgetSnapshot.StatusCounts")
struct WidgetStatusCountsTests {
    @Test("tallying an empty sequence yields all zeros")
    func tallyingEmptyYieldsZeros() {
        let counts = WidgetSnapshot.StatusCounts(tallying: [])
        #expect(counts.todo == 0)
        #expect(counts.started == 0)
        #expect(counts.blocked == 0)
        #expect(counts.closed == 0)
        #expect(counts.total == 0)
        #expect(counts.open == 0)
    }

    @Test("tallying counts each status independently")
    func tallyingCountsEachStatus() {
        let counts = WidgetSnapshot.StatusCounts(tallying: [
            .todo, .todo, .todo,
            .started,
            .blocked,
            .closed, .closed, .closed, .closed,
        ])
        #expect(counts.todo == 3)
        #expect(counts.started == 1)
        #expect(counts.blocked == 1)
        #expect(counts.closed == 4)
    }

    @Test("total sums every status; open excludes closed")
    func totalAndOpenDerivation() {
        let counts = WidgetSnapshot.StatusCounts(tallying: [.todo, .todo, .started, .blocked, .closed])
        #expect(counts.total == 5)
        #expect(counts.open == 4)
    }

    @Test("the memberwise init sets fields directly")
    func memberwiseInit() {
        let counts = WidgetSnapshot.StatusCounts(todo: 3, started: 1, blocked: 1, closed: 4)
        #expect(counts.total == 9)
        #expect(counts.open == 5)
    }

    @Test("subscript reads the count for each status")
    func subscriptCoversAllStatuses() {
        let counts = WidgetSnapshot.StatusCounts(todo: 3, started: 1, blocked: 2, closed: 4)
        #expect(counts[.todo] == 3)
        #expect(counts[.started] == 1)
        #expect(counts[.blocked] == 2)
        #expect(counts[.closed] == 4)
    }
}
