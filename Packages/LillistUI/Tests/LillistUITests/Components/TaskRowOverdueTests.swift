import XCTest
@testable import LillistUI
import LillistCore

/// Pins `TaskRowLabel.isOverdue` — the predicate behind the
/// action-orange due-date ink in task rows.
final class TaskRowOverdueTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_750_000_000) // fixed reference
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    func testTimedDeadlineInPastIsOverdue() {
        XCTAssertTrue(TaskRowLabel.isOverdue(
            deadline: now.addingTimeInterval(-60), hasTime: true,
            status: .todo, now: now, calendar: calendar
        ))
    }

    func testTimedDeadlineInFutureIsNotOverdue() {
        XCTAssertFalse(TaskRowLabel.isOverdue(
            deadline: now.addingTimeInterval(60), hasTime: true,
            status: .todo, now: now, calendar: calendar
        ))
    }

    func testDateOnlyDeadlineTodayIsNotOverdue() {
        // Earlier clock time today, but date-only — due *today*, not late.
        let earlierToday = calendar.startOfDay(for: now)
        XCTAssertFalse(TaskRowLabel.isOverdue(
            deadline: earlierToday, hasTime: false,
            status: .started, now: now, calendar: calendar
        ))
    }

    func testDateOnlyDeadlineYesterdayIsOverdue() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        XCTAssertTrue(TaskRowLabel.isOverdue(
            deadline: yesterday, hasTime: false,
            status: .blocked, now: now, calendar: calendar
        ))
    }

    func testClosedTaskIsNeverOverdue() {
        XCTAssertFalse(TaskRowLabel.isOverdue(
            deadline: now.addingTimeInterval(-86_400), hasTime: true,
            status: .closed, now: now, calendar: calendar
        ))
    }

    func testNilDeadlineIsNeverOverdue() {
        XCTAssertFalse(TaskRowLabel.isOverdue(
            deadline: nil, hasTime: true,
            status: .todo, now: now, calendar: calendar
        ))
    }
}
