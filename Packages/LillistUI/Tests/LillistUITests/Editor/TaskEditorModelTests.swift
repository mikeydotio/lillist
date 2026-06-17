import Testing
import Foundation
import LillistCore
@testable import LillistUI

/// Exercises the unified editor's state machine: draft buffering, silent
/// auto-promote, live-save, and discard — all against a real in-memory
/// Core Data stack (no mocks; production store code paths).
@MainActor
@Suite("TaskEditorModel")
struct TaskEditorModelTests {

    // MARK: - Fixtures

    private func makeStores(_ p: PersistenceController) -> TaskEditorModel.Stores {
        TaskEditorModel.Stores(
            tasks: TaskStore(persistence: p),
            tags: TagStore(persistence: p),
            series: SeriesStore(persistence: p),
            journal: JournalStore(persistence: p),
            notifications: NotificationSpecStore(persistence: p),
            attachments: AttachmentStore(persistence: p)
        )
    }

    private func newCapture(_ p: PersistenceController) -> TaskEditorModel {
        TaskEditorModel(stores: makeStores(p), opening: .newCapture(parentID: nil, placement: .top))
    }

    // MARK: - Draft basics

    @Test("A fresh capture is a quick draft and writes nothing")
    func freshCaptureIsEmptyDraft() async throws {
        let p = try await TestStore.make()
        let model = newCapture(p)
        #expect(model.phase == .draft)
        #expect(model.mode == .quick)
        #expect(model.presentation == .capture)
        #expect(model.taskID == nil)
        #expect(model.isCommittable == false)

        let verifier = TaskStore(persistence: p)
        let top = try await verifier.children(of: nil)
        #expect(top.isEmpty)
    }

    @Test("isCommittable tracks the trimmed title")
    func committableTracksTitle() async throws {
        let p = try await TestStore.make()
        let model = newCapture(p)
        model.title = "   "
        #expect(model.isCommittable == false)
        model.title = "Buy milk"
        #expect(model.isCommittable)
    }

    @Test("expandToFull flips mode without touching data")
    func expandKeepsData() async throws {
        let p = try await TestStore.make()
        let model = newCapture(p)
        model.title = "Draft"
        model.expandToFull()
        #expect(model.mode == .full)
        #expect(model.phase == .draft)
    }

    // MARK: - Explicit commit

    @Test("commitDraft persists title + notes + scalars and goes live")
    func explicitCommitPersistsScalars() async throws {
        let p = try await TestStore.make()
        let model = newCapture(p)
        model.title = "Write plan"
        model.notes = "with detail"
        model.deadline = Date(timeIntervalSince1970: 1_000_000)
        model.isPinned = true

        let id = try await model.commitDraft()
        #expect(model.phase == .live(id))

        let rec = try await TaskStore(persistence: p).fetch(id: id)
        #expect(rec.title == "Write plan")
        #expect(rec.notes == "with detail")
        #expect(rec.deadline == Date(timeIntervalSince1970: 1_000_000))
        #expect(rec.isPinned)
    }

    @Test("ensureLive on an empty-title draft throws emptyTitle")
    func emptyTitleRejected() async throws {
        let p = try await TestStore.make()
        let model = newCapture(p)
        await #expect(throws: TaskEditorError.emptyTitle) {
            _ = try await model.ensureLive()
        }
        #expect(model.phase == .draft)
    }

    // MARK: - Auto-promote triggers

    @Test("Adding a subtask silently auto-promotes the draft")
    func subtaskPromotes() async throws {
        let p = try await TestStore.make()
        let model = newCapture(p)
        model.title = "Parent"

        try await model.addSubtask(title: "Child")

        let id = try #require(model.taskID)
        #expect(model.phase == .live(id))
        let kids = try await TaskStore(persistence: p).children(of: id)
        #expect(kids.map(\.title) == ["Child"])
        #expect(model.subtasks.map(\.title) == ["Child"])
    }

    @Test("Adding a journal note auto-promotes")
    func journalPromotes() async throws {
        let p = try await TestStore.make()
        let model = newCapture(p)
        model.title = "Parent"

        try await model.addJournalNote("first note")

        let id = try #require(model.taskID)
        let entries = try await JournalStore(persistence: p).entries(forTask: id)
        #expect(entries.contains { $0.body == "first note" })
        #expect(model.journal.contains { $0.body == "first note" })
    }

    @Test("Adding a reminder auto-promotes")
    func reminderPromotes() async throws {
        let p = try await TestStore.make()
        let model = newCapture(p)
        model.title = "Parent"

        try await model.addReminder(kind: .nudge, offsetMinutes: nil, fireDate: Date(timeIntervalSince1970: 2_000_000))

        let id = try #require(model.taskID)
        let specs = try await NotificationSpecStore(persistence: p).specs(forTask: id)
        #expect(!specs.isEmpty)
        #expect(!model.reminders.isEmpty)
    }

    @Test("Committing a recurrence rule auto-promotes and creates a series")
    func recurrencePromotes() async throws {
        let p = try await TestStore.make()
        let model = newCapture(p)
        model.title = "Daily standup"
        model.recurrence.repeats = true
        model.recurrence.freq = .daily
        model.recurrence.interval = 1

        try await model.commitRecurrence()

        let id = try #require(model.taskID)
        let sid = try #require(model.seriesID)
        let rec = try await TaskStore(persistence: p).fetch(id: id)
        #expect(rec.seriesID == sid)
    }

    @Test("Clearing recurrence on a never-recurred draft does not promote")
    func clearingRecurrenceNoPromote() async throws {
        let p = try await TestStore.make()
        let model = newCapture(p)
        model.title = "One-off"
        model.recurrence.repeats = false

        try await model.commitRecurrence()

        #expect(model.phase == .draft)
        let top = try await TaskStore(persistence: p).children(of: nil)
        #expect(top.isEmpty)
    }

    // MARK: - Tag buffering

    @Test("Tags buffer as names on a draft and don't promote")
    func tagsBufferOnDraft() async throws {
        let p = try await TestStore.make()
        let model = newCapture(p)
        model.title = "Tagged"
        await model.addTag(name: "home")
        await model.addTag(name: "Work")
        await model.addTag(name: "HOME") // case-insensitive dedupe

        #expect(model.draftTagNames == ["home", "Work"])
        #expect(model.phase == .draft)
        let top = try await TaskStore(persistence: p).children(of: nil)
        #expect(top.isEmpty)
    }

    @Test("Buffered tags are materialized at commit")
    func tagsFlushOnCommit() async throws {
        let p = try await TestStore.make()
        let model = newCapture(p)
        model.title = "Tagged"
        await model.addTag(name: "home")
        await model.addTag(name: "work")

        let id = try await model.commitDraft()

        #expect(model.draftTagNames.isEmpty)
        #expect(Set(model.assignedTags.map(\.name)) == ["home", "work"])
        let tagIDs = try await TaskStore(persistence: p).tagIDs(forTask: id)
        #expect(tagIDs.count == 2)
    }

    // MARK: - Concurrency / idempotency

    @Test("Concurrent ensureLive calls commit exactly one row")
    func concurrentEnsureLiveIsIdempotent() async throws {
        let p = try await TestStore.make()
        let model = newCapture(p)
        model.title = "Race"

        async let a = model.ensureLive()
        async let b = model.ensureLive()
        let (id1, id2) = try await (a, b)

        #expect(id1 == id2)
        let top = try await TaskStore(persistence: p).children(of: nil)
        #expect(top.count == 1)
    }

    // MARK: - Discard

    @Test("Discarding a pure draft persists nothing")
    func discardPureDraft() async throws {
        let p = try await TestStore.make()
        let model = newCapture(p)
        model.title = "Throwaway"
        await model.addTag(name: "junk")

        await model.discard()

        #expect(model.phase == .abandoned)
        let top = try await TaskStore(persistence: p).children(of: nil)
        #expect(top.isEmpty)
    }

    @Test("Discarding an auto-promoted draft soft-deletes it to Trash")
    func discardPromotedDraft() async throws {
        let p = try await TestStore.make()
        let model = newCapture(p)
        model.title = "Promoted then bailed"
        try await model.addSubtask(title: "child")
        let id = try #require(model.taskID)

        await model.discard()

        #expect(model.phase == .abandoned)
        let trashed = try await TaskStore(persistence: p).trashed()
        #expect(trashed.contains { $0.id == id })
    }

    // MARK: - Existing-task editing (live-save)

    @Test("Opening an existing task seeds its fields")
    func loadExisting() async throws {
        let p = try await TestStore.make()
        let setup = TaskStore(persistence: p)
        let id = try await setup.create(title: "Existing", notes: "n", placement: .top)

        let model = TaskEditorModel(stores: makeStores(p), opening: .existing(id))
        #expect(model.phase == .live(id))
        #expect(model.mode == .full)
        await model.load()
        #expect(model.title == "Existing")
        #expect(model.notes == "n")
    }

    @Test("Live-save persists title, notes, scalars, and status immediately")
    func liveSaveExisting() async throws {
        let p = try await TestStore.make()
        let setup = TaskStore(persistence: p)
        let id = try await setup.create(title: "Before", placement: .top)

        let model = TaskEditorModel(stores: makeStores(p), opening: .existing(id))
        await model.load()

        model.title = "After"
        model.notes = "edited"
        await model.saveTextNow()

        model.isPinned = true
        model.deadline = Date(timeIntervalSince1970: 3_000_000)
        await model.saveScalarsNow()

        await model.setStatus(.started)

        let rec = try await setup.fetch(id: id)
        #expect(rec.title == "After")
        #expect(rec.notes == "edited")
        #expect(rec.isPinned)
        #expect(rec.deadline == Date(timeIntervalSince1970: 3_000_000))
        #expect(rec.status == .started)
    }

    @Test("setStatus on a draft buffers and applies at commit")
    func draftStatusBuffered() async throws {
        let p = try await TestStore.make()
        let model = newCapture(p)
        model.title = "Will start"
        await model.setStatus(.started)
        #expect(model.status == .started)
        #expect(model.phase == .draft)

        let id = try await model.commitDraft()
        let rec = try await TaskStore(persistence: p).fetch(id: id)
        #expect(rec.status == .started)
    }

    @Test("deleteTask soft-deletes an existing task")
    func deleteExisting() async throws {
        let p = try await TestStore.make()
        let setup = TaskStore(persistence: p)
        let id = try await setup.create(title: "Doomed", placement: .top)

        let model = TaskEditorModel(stores: makeStores(p), opening: .existing(id))
        await model.deleteTask()

        #expect(model.phase == .abandoned)
        let trashed = try await setup.trashed()
        #expect(trashed.contains { $0.id == id })
    }
}
