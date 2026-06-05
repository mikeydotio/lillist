import XCTest
import LillistCore
import LillistUI

/// LillistCore + LillistUI composition test for the Quick Capture pipeline.
/// This bundle cannot `@testable import Lillist_iOS` (no signed app host),
/// so it does NOT exercise `QuickCaptureDialogHost.submit()` directly — it
/// re-walks the equivalent parse → create → resolve-tags → resolve-deadline
/// path through `QuickCaptureParser` + `TaskStore` + `TagStore`. Named to
/// signal that it covers the composition, not the app-layer view model.
final class LillistCoreQuickCaptureCompositionTests: XCTestCase {
    func test_parse_create_resolve_tag_and_deadline() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let taskStore = TaskStore(persistence: persistence)
        let tagStore = TagStore(persistence: persistence)

        let parsed = QuickCaptureParser.parse("Buy milk #errands ^tomorrow")
        XCTAssertEqual(parsed.title, "Buy milk")
        XCTAssertEqual(parsed.tags, ["errands"])
        XCTAssertEqual(parsed.dateToken, "tomorrow")

        let taskID = try await taskStore.create(title: parsed.title)
        for name in parsed.tags {
            let tagID = try await tagStore.findOrCreate(name: name)
            try await taskStore.assignTag(taskID: taskID, tagID: tagID)
        }
        if let token = parsed.dateToken {
            let rel = try RelativeDate.parse(token)
            let resolved = RelativeDateResolver.resolve(rel)
            try await taskStore.update(id: taskID) { draft in
                draft.deadline = resolved
                draft.deadlineHasTime = false
            }
        }

        let task = try await taskStore.fetch(id: taskID)
        XCTAssertEqual(task.title, "Buy milk")
        XCTAssertNotNil(task.deadline)

        let tagIDs = try await taskStore.tagIDs(forTask: taskID)
        XCTAssertEqual(tagIDs.count, 1)
        let tag = try await tagStore.fetch(id: tagIDs[0])
        XCTAssertEqual(tag.name, "errands")
    }

    func test_empty_title_rejected() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let taskStore = TaskStore(persistence: persistence)

        let parsed = QuickCaptureParser.parse("#only #tags")
        XCTAssertEqual(parsed.title, "")

        do {
            _ = try await taskStore.create(title: parsed.title)
            XCTFail("Expected validation failure on empty title")
        } catch {
            // Expected — TaskStore.create validates title is non-empty.
        }
    }
}
