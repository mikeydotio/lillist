#if os(macOS)
import XCTest
import SwiftUI
import SnapshotTesting
import LillistCore
@testable import LillistUI

@MainActor
final class TaskListViewSnapshotTests: XCTestCase {
    private func record(title: String, status: Status, deadline: Date? = nil) -> TaskStore.TaskRecord {
        TaskStore.TaskRecord(
            id: UUID(), title: title, notes: "", status: status,
            start: nil, startHasTime: false,
            deadline: deadline, deadlineHasTime: deadline != nil,
            position: 0, isPinned: false, parentID: nil,
            createdAt: Date(), modifiedAt: Date(),
            closedAt: status == .closed ? Date() : nil,
            deletedAt: nil
        )
    }

    func test_row_todo_light() {
        let host = makeHostingView(
            SnapshotHost(colorScheme: .light) {
                TaskRowView(task: self.record(title: "Buy milk", status: .todo),
                            tagNames: [],
                            onStatusClick: {}, onStatusLongPress: {})
                    .frame(width: 520)
            },
            size: CGSize(width: 520, height: 50)
        )
        assertSnapshot(of: host, as: .image(size: CGSize(width: 520, height: 50)))
    }

    func test_row_started_with_tags_dark() {
        let host = makeHostingView(
            SnapshotHost(colorScheme: .dark) {
                TaskRowView(task: self.record(title: "Draft email", status: .started),
                            tagNames: ["work", "urgent"],
                            onStatusClick: {}, onStatusLongPress: {})
                    .frame(width: 520)
            },
            size: CGSize(width: 520, height: 60)
        )
        assertSnapshot(of: host, as: .image(size: CGSize(width: 520, height: 60)))
    }

    func test_row_blocked_with_deadline_light() {
        let host = makeHostingView(
            SnapshotHost(colorScheme: .light) {
                TaskRowView(task: self.record(title: "Ship release",
                                         status: .blocked,
                                         deadline: Date(timeIntervalSince1970: 1_780_000_000)),
                            tagNames: ["release"],
                            onStatusClick: {}, onStatusLongPress: {})
                    .frame(width: 520)
            },
            size: CGSize(width: 520, height: 60)
        )
        assertSnapshot(of: host, as: .image(size: CGSize(width: 520, height: 60)))
    }

    func test_row_closed_strikethrough_dark() {
        let host = makeHostingView(
            SnapshotHost(colorScheme: .dark) {
                TaskRowView(task: self.record(title: "Pay rent", status: .closed),
                            tagNames: [],
                            onStatusClick: {}, onStatusLongPress: {})
                    .frame(width: 520)
            },
            size: CGSize(width: 520, height: 50)
        )
        assertSnapshot(of: host, as: .image(size: CGSize(width: 520, height: 50)))
    }

    func test_breadcrumb() {
        let host = makeHostingView(
            SnapshotHost(colorScheme: .light) {
                BreadcrumbView(path: ["Work", "Releases", "v0.2"]).padding()
            },
            size: CGSize(width: 320, height: 30)
        )
        assertSnapshot(of: host, as: .image(size: CGSize(width: 320, height: 30)))
    }

    func test_emptyState() {
        let host = makeHostingView(
            SnapshotHost(colorScheme: .light) {
                EmptyStateView(title: "Nothing matches \u{201C}Today\u{201D}",
                               message: "Tasks with a start or deadline on or before today appear here.",
                               systemImage: "sun.max")
                    .frame(width: 480, height: 320)
            },
            size: CGSize(width: 480, height: 320)
        )
        assertSnapshot(of: host, as: .image(size: CGSize(width: 480, height: 320)))
    }
}
#endif
