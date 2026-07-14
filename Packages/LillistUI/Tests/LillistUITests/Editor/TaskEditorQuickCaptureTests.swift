import Testing
import Foundation
import LillistCore
@testable import LillistUI

/// The quick-capture bridge: parsing `#tag ^date` syntax into the structured
/// draft, expand-carries-text, and quick commit.
@MainActor
@Suite("TaskEditorModel quick capture")
struct TaskEditorQuickCaptureTests {

    private func newCapture(_ p: PersistenceController) -> TaskEditorModel {
        TaskEditorModel(
            stores: .init(
                tasks: TaskStore(persistence: p),
                tags: TagStore(persistence: p),
                series: SeriesStore(persistence: p),
                journal: JournalStore(persistence: p),
                attachments: AttachmentStore(persistence: p)
            ),
            opening: .newCapture(parentID: nil, placement: .top)
        )
    }

    @Test("isQuickCommittable tracks the parsed title")
    func quickCommittable() async throws {
        let p = try await TestStore.make()
        let model = newCapture(p)
        #expect(model.isQuickCommittable == false)
        model.captureText = "#onlytag"      // no title once tag is stripped
        #expect(model.isQuickCommittable == false)
        model.captureText = "Real title #tag"
        #expect(model.isQuickCommittable)
    }

    @Test("ingestCaptureText parses title, tags, and a relative date")
    func ingest() async throws {
        let p = try await TestStore.make()
        let model = newCapture(p)
        model.captureText = "Call Alice #work ^tomorrow"
        model.ingestCaptureText()
        #expect(model.title == "Call Alice")
        #expect(model.draftTagNames == ["work"])
        #expect(model.deadline != nil)
        #expect(model.deadlineHasTime == false)
    }

    @Test("expandToFull folds the quick text into structured fields")
    func expandIngests() async throws {
        let p = try await TestStore.make()
        let model = newCapture(p)
        model.captureText = "Plan trip #travel"
        model.expandToFull()
        #expect(model.mode == .full)
        #expect(model.title == "Plan trip")
        #expect(model.draftTagNames == ["travel"])
        #expect(model.phase == .draft)
    }

    @Test("commitQuickCapture parses then persists title + tags")
    func commitQuick() async throws {
        let p = try await TestStore.make()
        let model = newCapture(p)
        model.captureText = "Buy milk #home #errand"
        let id = try await model.commitQuickCapture()
        let rec = try await TaskStore(persistence: p).fetch(id: id)
        #expect(rec.title == "Buy milk")
        let tagIDs = try await TaskStore(persistence: p).tagIDs(forTask: id)
        #expect(tagIDs.count == 2)
    }
}
