import Foundation
import Observation
import LillistCore

/// The single owner of unified-task-editor state.
///
/// Views **bind to this model and never call stores directly** — that is what
/// keeps the auto-promote machinery race-safe. Because the class is
/// `@MainActor`, every read-modify-write of `phase` / `promoteTask` is
/// serialized by the actor (no locks), and the only suspension points are the
/// `await`s into the (non-isolated) Core Data stores.
///
/// ## Lifecycle
/// A brand-new capture starts as an **in-memory draft** (`phase == .draft`):
/// nothing is written to Core Data. Scalars, tag *names*, and the recurrence
/// rule buffer in the model. The moment the user performs an op that needs a
/// persisted parent (attachment / journal note / a recurrence series), the
/// draft **auto-promotes**: `ensureLive()` commits it
/// to a real row, then the op proceeds. An existing task opens directly in
/// `.live` and every edit live-saves.
///
/// LillistUI stays `AppEnvironment`-free: the model is injected with a
/// `Stores` value bundle by the app-layer host.
@MainActor
@Observable
public final class TaskEditorModel {

    // MARK: - Injected dependencies

    /// Value bundle of the LillistCore stores the editor composes. Holding
    /// the (`@unchecked Sendable`) store classes keeps this `Sendable` and
    /// lets LillistUI avoid importing the app's `AppEnvironment`.
    public struct Stores: Sendable {
        public let tasks: TaskStore
        public let tags: TagStore
        public let series: SeriesStore
        public let journal: JournalStore
        /// Optional: macOS historically didn't wire it. When `nil` the
        /// attachment section is inert rather than crashing.
        public let attachments: AttachmentStore?

        public init(
            tasks: TaskStore,
            tags: TagStore,
            series: SeriesStore,
            journal: JournalStore,
            attachments: AttachmentStore?
        ) {
            self.tasks = tasks
            self.tags = tags
            self.series = series
            self.journal = journal
            self.attachments = attachments
        }
    }

    @ObservationIgnored private let stores: Stores

    // MARK: - Identity

    /// Lifecycle identity — the un-foolable source of "is there a row yet".
    enum Phase: Equatable {
        /// In-memory only; nothing persisted.
        case draft
        /// Commit in flight; a second trigger awaits the same `promoteTask`.
        case promoting
        /// A real Core Data row exists.
        case live(UUID)
        /// Closed via discard/delete; nothing further to persist.
        case abandoned
    }

    /// Current lifecycle phase. Internal (the public surface exposes
    /// `taskID`/`mode`/`presentation` instead); observed so the UI can, e.g.,
    /// disable controls while `.promoting`.
    private(set) var phase: Phase

    /// How the editor was opened.
    public let presentation: TaskEditorPresentation

    /// The live task's id, or `nil` while still a draft.
    public var taskID: UUID? {
        if case .live(let id) = phase { return id }
        return nil
    }

    // MARK: - Presentation

    /// `quick` (single field) vs `full` (all sections). Flipping this is the
    /// entire quick→full expansion at the data layer.
    public var mode: TaskEditorMode

    // MARK: - Quick-capture raw text

    /// The raw text of the `quick` mode single field, which keeps the
    /// `#tag ^date` Quick Capture syntax. Parsed into the structured fields
    /// (`title` / `draftTagNames` / `deadline`) on expand or commit. Unused
    /// once in `full` mode or for an existing task.
    public var captureText: String = ""

    // MARK: - Scalar field mirror (editing surface for BOTH draft and live)

    public var title: String = ""
    public var notes: String = ""
    public var start: Date?
    public var startHasTime: Bool = false
    public var deadline: Date?
    public var deadlineHasTime: Bool = false
    public var isPinned: Bool = false
    public var status: Status = .todo

    // MARK: - Relational state

    /// Buffered tag names while a draft (no Tag rows minted yet — avoids
    /// orphaning tags when a draft is abandoned). Flushed at commit.
    public internal(set) var draftTagNames: [String] = []
    /// Materialized tags once live.
    public private(set) var assignedTags: [TagStore.TagRecord] = []
    /// Tag names to show regardless of phase: buffered draft names while a
    /// draft, materialized tag names once live.
    public var displayedTagNames: [String] {
        if case .live = phase { return assignedTags.map(\.name) }
        return draftTagNames
    }
    /// Recurrence editor VM — buffered while draft, round-tripped from the
    /// series once live.
    public var recurrence: RecurrenceEditorViewModel = .init(rule: nil)
    /// The backing series id, if this task recurs.
    public internal(set) var seriesID: UUID?
    public private(set) var attachments: [AttachmentStore.AttachmentRecord] = []
    public private(set) var journal: [JournalStore.JournalRecord] = []

    /// Non-fatal warning from a partial commit (the row was created but a
    /// follow-on enrichment step — a tag, the recurrence series — failed).
    /// The UI surfaces this without treating the create as failed.
    public internal(set) var lastCommitWarning: String?

    // MARK: - Draft creation context

    @ObservationIgnored private let draftParentID: UUID?
    @ObservationIgnored private let draftPlacement: NewTaskPlacement

    // MARK: - Promotion serialization

    @ObservationIgnored private var promoteTask: Task<UUID, Error>?

    // MARK: - Open intent

    public enum OpenIntent: Sendable {
        /// A brand-new capture. `parentID` is set when capturing a subtask of
        /// an existing task; `placement` is `.top` for user capture.
        case newCapture(parentID: UUID?, placement: NewTaskPlacement)
        /// Edit an already-persisted task.
        case existing(UUID)
    }

    public init(stores: Stores, opening intent: OpenIntent) {
        self.stores = stores
        switch intent {
        case .newCapture(let parentID, let placement):
            self.phase = .draft
            self.mode = .quick
            self.presentation = .capture
            self.draftParentID = parentID
            self.draftPlacement = placement
        case .existing(let id):
            self.phase = .live(id)
            self.mode = .full
            self.presentation = .existing
            self.draftParentID = nil
            self.draftPlacement = .bottom
        }
    }

    /// Whether the current title would survive commit (non-empty after trim).
    /// Drives the quick-mode "Add" button's enabled state.
    public var isCommittable: Bool { TaskStore.isCommittableTitle(title) }

    // MARK: - Loading (existing tasks)

    /// Populate field mirror + relations for an existing task. No-op for a
    /// draft. Call from the host's `.task`/`onAppear`.
    public func load() async {
        guard case .live(let id) = phase else { return }
        if let rec = try? await stores.tasks.fetch(id: id) {
            seedScalars(from: rec)
        }
        await reloadRelations(id: id)
    }

    // MARK: - Quick-capture parsing

    /// Whether the quick field would produce a committable task — i.e. its
    /// parsed title is non-empty. Drives the quick-mode "Add" button.
    public var isQuickCommittable: Bool {
        TaskStore.isCommittableTitle(QuickCaptureParser.parse(captureText).title)
    }

    /// Parse `captureText`'s `#tag ^date` syntax into the structured draft
    /// fields. `title` becomes the parsed title; parsed tags are appended
    /// (case-insensitive dedupe); a resolvable `^date` sets the deadline.
    /// No-op when the parsed title is empty (don't wipe a real title on an
    /// accidental expand of empty text).
    public func ingestCaptureText() {
        let parsed = QuickCaptureParser.parse(captureText)
        let trimmed = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        title = trimmed
        for name in parsed.tags
        where !draftTagNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            draftTagNames.append(name)
        }
        if let token = parsed.dateToken, let rel = try? RelativeDate.parse(token) {
            deadline = RelativeDateResolver.resolve(rel)
            deadlineHasTime = false
        }
    }

    // MARK: - Expansion

    /// Flip quick → full, first folding the quick field's `#tag ^date` text
    /// into the structured fields so nothing typed is lost. Pure
    /// in-memory; the buffered draft carries over with zero data migration.
    public func expandToFull() {
        ingestCaptureText()
        mode = .full
    }

    // MARK: - Explicit commit

    /// Commit the quick field (the quick-mode "Add" path): parse `captureText`
    /// then commit. Returns the new task id.
    @discardableResult
    public func commitQuickCapture() async throws -> UUID {
        ingestCaptureText()
        return try await ensureLive()
    }

    /// Commit a pure draft to a real task (full-mode explicit save) and
    /// return its id. Idempotent with auto-promote — both funnel through
    /// `ensureLive()`.
    @discardableResult
    public func commitDraft() async throws -> UUID {
        try await ensureLive()
    }

    // MARK: - Auto-promote

    /// Return the live task id, committing the draft first if needed.
    /// Idempotent and serialized: concurrent callers all await the *same*
    /// in-flight commit rather than racing a second `create`.
    @discardableResult
    public func ensureLive() async throws -> UUID {
        switch phase {
        case .live(let id):
            return id
        case .promoting:
            // A commit is already in flight; await the same Task.
            if let task = promoteTask { return try await task.value }
            throw TaskEditorError.inconsistentPromotion
        case .abandoned:
            throw TaskEditorError.editorClosed
        case .draft:
            guard TaskStore.isCommittableTitle(title) else {
                throw TaskEditorError.emptyTitle
            }
            let snapshot = makeDraftSnapshot()
            let task = Task { try await self.runCommit(snapshot) }
            promoteTask = task
            phase = .promoting
            do {
                let id = try await task.value
                phase = .live(id)
                promoteTask = nil
                await reloadRelations(id: id)
                return id
            } catch {
                // `create` failed → no row exists; revert to an editable draft.
                phase = .draft
                promoteTask = nil
                throw error
            }
        }
    }

    /// The create-then-best-effort commit. The **only** throwing step is
    /// `create`; if it fails the whole promote fails and we revert to draft.
    /// Post-create enrichment is best-effort — a failed tag/series leaves the
    /// created row intact and records `lastCommitWarning`. Runs on the
    /// MainActor (the `Task` inherits the model's isolation), so assigning
    /// `lastCommitWarning` here is safe.
    private func runCommit(_ d: DraftSnapshot) async throws -> UUID {
        let id = try await stores.tasks.create(
            title: d.title,
            notes: d.notes,
            parent: d.parentID,
            placement: d.placement
        )
        var warning: String?
        func note(_ step: String) { if warning == nil { warning = step } }

        if d.start != nil || d.deadline != nil || d.isPinned
            || d.startHasTime || d.deadlineHasTime {
            do {
                try await stores.tasks.update(id: id) { draft in
                    draft.start = d.start
                    draft.startHasTime = d.startHasTime
                    draft.deadline = d.deadline
                    draft.deadlineHasTime = d.deadlineHasTime
                    draft.isPinned = d.isPinned
                }
            } catch { note("dates") }
        }
        if d.status != .todo {
            do { try await stores.tasks.transition(id: id, to: d.status) }
            catch { note("status") }
        }
        for name in d.tagNames {
            do {
                let tagID = try await stores.tags.findOrCreate(name: name)
                try await stores.tasks.assignTag(taskID: id, tagID: tagID)
            } catch { note("tag") }
        }
        if let rule = d.recurrenceRule {
            do { _ = try await stores.series.create(fromSeedTask: id, rule: rule) }
            catch { note("recurrence") }
        }
        lastCommitWarning = warning
        return id
    }

    private func makeDraftSnapshot() -> DraftSnapshot {
        DraftSnapshot(
            title: title,
            notes: notes,
            start: start,
            startHasTime: startHasTime,
            deadline: deadline,
            deadlineHasTime: deadlineHasTime,
            isPinned: isPinned,
            status: status,
            tagNames: draftTagNames,
            recurrenceRule: recurrence.build(),
            parentID: draftParentID,
            placement: draftPlacement
        )
    }

    /// Immutable commit payload assembled from the model's current fields at
    /// trigger time — capturing it freezes the buffer for the in-flight Task.
    private struct DraftSnapshot: Sendable {
        var title: String
        var notes: String
        var start: Date?
        var startHasTime: Bool
        var deadline: Date?
        var deadlineHasTime: Bool
        var isPinned: Bool
        var status: Status
        var tagNames: [String]
        var recurrenceRule: RecurrenceRule?
        var parentID: UUID?
        var placement: NewTaskPlacement
    }

    // MARK: - Live-save (existing/promoted scalars)

    /// Persist title + notes. Called by the host after its debounce timer and
    /// on blur/dismiss. No-op while a draft (scalars buffer in the mirror).
    public func saveTextNow() async {
        guard case .live(let id) = phase else { return }
        let t = title, n = notes
        try? await stores.tasks.update(id: id) { draft in
            draft.title = t
            draft.notes = n
        }
    }

    /// Persist dates + pin immediately. No-op while a draft.
    public func saveScalarsNow() async {
        guard case .live(let id) = phase else { return }
        let s = start, sht = startHasTime, d = deadline, dht = deadlineHasTime, p = isPinned
        try? await stores.tasks.update(id: id) { draft in
            draft.start = s
            draft.startHasTime = sht
            draft.deadline = d
            draft.deadlineHasTime = dht
            draft.isPinned = p
        }
    }

    /// Set status. Updates the mirror always; transitions the row immediately
    /// when live (buffered in `status` while a draft).
    public func setStatus(_ newStatus: Status) async {
        status = newStatus
        guard case .live(let id) = phase else { return }
        try? await stores.tasks.transition(id: id, to: newStatus)
        await reloadJournal(id: id) // a transition writes a journal entry
    }

    // MARK: - Tags (no auto-promote — buffered names while draft)

    public func addTag(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch phase {
        case .live(let id):
            guard let tagID = try? await stores.tags.findOrCreate(name: trimmed) else { return }
            try? await stores.tasks.assignTag(taskID: id, tagID: tagID)
            await reloadTags(id: id)
        case .draft, .promoting:
            if !draftTagNames.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                draftTagNames.append(trimmed)
            }
        case .abandoned:
            break
        }
    }

    public func removeTag(named name: String) async {
        switch phase {
        case .live(let id):
            if let tag = assignedTags.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                try? await stores.tasks.unassignTag(taskID: id, tagID: tag.id)
                await reloadTags(id: id)
            }
        case .draft, .promoting:
            draftTagNames.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
        case .abandoned:
            break
        }
    }

    // MARK: - Recurrence (auto-promote only when a rule exists)

    /// Apply the current `recurrence` VM: create/update/delete the series.
    /// A rule needs a persisted seed, so setting one auto-promotes; clearing
    /// one on a draft is a no-op (no series ever existed).
    public func commitRecurrence() async throws {
        let rule = recurrence.build()
        if let rule {
            let id = try await ensureLive()
            if let seriesID {
                try await stores.series.update(id: seriesID, rule: rule)
            } else {
                seriesID = try await stores.series.create(fromSeedTask: id, rule: rule)
            }
        } else if let seriesID {
            try await stores.series.delete(id: seriesID)
            self.seriesID = nil
        }
    }

    // MARK: - Journal (auto-promote)

    public func addJournalNote(_ body: String) async throws {
        let id = try await ensureLive()
        _ = try await stores.journal.appendNote(taskID: id, body: body)
        await reloadJournal(id: id)
    }

    // MARK: - Attachments (auto-promote; inert without an attachment store)

    public func addImageAttachment(filename: String, data: Data) async throws {
        guard let attachmentStore = stores.attachments else { return }
        let id = try await ensureLive()
        _ = try await attachmentStore.addImage(taskID: id, filename: filename, data: data)
        await reloadAttachments(id: id)
    }

    public func deleteAttachment(id attachmentID: UUID) async {
        guard let attachmentStore = stores.attachments else { return }
        try? await attachmentStore.delete(id: attachmentID)
        if case .live(let id) = phase { await reloadAttachments(id: id) }
    }

    // MARK: - Discard / delete

    /// Bail out of the editor.
    /// - Pure draft → writes nothing.
    /// - Promoting → await the in-flight commit, then soft-delete the row it
    ///   created (the promote was triggered by real content the user added).
    /// - Live → soft-delete (→ Trash, recoverable), never hard-delete.
    public func discard() async {
        switch phase {
        case .draft, .abandoned:
            phase = .abandoned
        case .promoting:
            let committedID = try? await promoteTask?.value
            if let committedID { try? await stores.tasks.softDelete(id: committedID) }
            phase = .abandoned
        case .live(let id):
            try? await stores.tasks.softDelete(id: id)
            phase = .abandoned
        }
    }

    /// Explicit "Delete task" for an existing task — soft-delete to Trash.
    public func deleteTask() async {
        guard case .live(let id) = phase else { return }
        try? await stores.tasks.softDelete(id: id)
        phase = .abandoned
    }

    // MARK: - Seeding & reloads

    private func seedScalars(from rec: TaskStore.TaskRecord) {
        title = rec.title
        notes = rec.notes
        start = rec.start
        startHasTime = rec.startHasTime
        deadline = rec.deadline
        deadlineHasTime = rec.deadlineHasTime
        isPinned = rec.isPinned
        status = rec.status
    }

    /// Adopt live relational state. Clears the draft tag buffer (its names were
    /// just materialized) and loads every collection. Scalars are left to
    /// live-save so in-progress edits are never clobbered.
    private func reloadRelations(id: UUID) async {
        draftTagNames = []
        await reloadTags(id: id)
        await reloadRecurrence(id: id)
        await reloadAttachments(id: id)
        await reloadJournal(id: id)
    }

    private func reloadTags(id: UUID) async {
        guard let ids = try? await stores.tasks.tagIDs(forTask: id) else { return }
        var recs: [TagStore.TagRecord] = []
        for tid in ids {
            if let t = try? await stores.tags.fetch(id: tid) { recs.append(t) }
        }
        assignedTags = recs
    }

    private func reloadRecurrence(id: UUID) async {
        guard let rec = try? await stores.tasks.fetch(id: id) else { return }
        let anchor = rec.start ?? rec.deadline
        if let sid = rec.seriesID, let series = try? await stores.series.fetch(id: sid) {
            seriesID = sid
            recurrence = RecurrenceEditorViewModel(rule: series.rule, taskAnchorDate: anchor)
        } else {
            seriesID = nil
            recurrence = RecurrenceEditorViewModel(rule: nil, taskAnchorDate: anchor)
        }
    }

    private func reloadAttachments(id: UUID) async {
        guard let attachmentStore = stores.attachments else { attachments = []; return }
        attachments = (try? await attachmentStore.attachments(forTask: id)) ?? []
    }

    private func reloadJournal(id: UUID) async {
        journal = (try? await stores.journal.entries(forTask: id)) ?? []
    }
}

/// Errors surfaced by the unified editor's commit path.
public enum TaskEditorError: Error, Equatable {
    /// Tried to commit a draft whose title is empty after trimming.
    case emptyTitle
    /// `.promoting` with no in-flight task — should be unreachable.
    case inconsistentPromotion
    /// Operated on an already-closed editor.
    case editorClosed
}
