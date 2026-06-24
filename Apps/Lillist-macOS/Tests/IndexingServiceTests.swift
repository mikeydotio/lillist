import XCTest
import CoreSpotlight
import LillistCore

/// Plan 15 Task 24: covers the pure attribute-set / searchable-item
/// mappers used by the Spotlight indexing pipeline. The
/// `IndexingService` itself depends on `AppEnvironment` (which lives
/// in the app target and pulls in CloudKit), so the standalone test
/// bundle exercises only the pure `IndexingMappers` extracted in the
/// same task. Functional integration with `CSSearchableIndex` is
/// covered manually (Plan 15 Task 30's smoke test).
@MainActor
final class IndexingServiceTests: XCTestCase {

    func test_attributeSet_populatesTitleNotesKeywords() {
        let task = TaskStore.TaskRecord(
            id: UUID(),
            title: "Draft launch email",
            notes: "Mention CloudKit sync and the new recurrence engine.",
            status: .started,
            start: nil, startHasTime: false,
            deadline: nil, deadlineHasTime: false,
            position: 0, isPinned: false, parentID: nil,
            createdAt: Date(), modifiedAt: Date(),
            closedAt: nil, deletedAt: nil
        )
        let attrs = IndexingMappers.attributeSet(for: task, tagNames: ["work", "urgent"])
        XCTAssertEqual(attrs.title, "Draft launch email")
        XCTAssertEqual(attrs.contentDescription, "Mention CloudKit sync and the new recurrence engine.")
        let keywords = (attrs.keywords ?? [])
        XCTAssertTrue(keywords.contains("work"))
        XCTAssertTrue(keywords.contains("urgent"))
    }

    func test_searchableItem_usesCanonicalDomainIdentifier() {
        let task = TaskStore.TaskRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "x", notes: "", status: .todo,
            start: nil, startHasTime: false,
            deadline: nil, deadlineHasTime: false,
            position: 0, isPinned: false, parentID: nil,
            createdAt: Date(), modifiedAt: Date(),
            closedAt: nil, deletedAt: nil
        )
        let item = IndexingMappers.searchableItem(for: task, tagNames: [])
        XCTAssertEqual(item.domainIdentifier, "io.mikey.lillist.task")
        XCTAssertEqual(item.uniqueIdentifier, task.id.uuidString)
    }
}
