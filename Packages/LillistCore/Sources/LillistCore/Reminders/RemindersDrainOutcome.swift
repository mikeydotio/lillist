import Foundation

/// The result of one ``RemindersImporter`` drain pass.
///
/// Replaces a bare `Int` return, which collapsed six distinct reasons for
/// "nothing happened" (disabled, unselected, unauthorized, already-in-progress,
/// an unreadable list, and a genuinely-empty list) into the same `0` — the
/// silence issue #50 asks to fix. Every case here is a legible answer to
/// "why did nothing import," and the UI renders a distinct message per case
/// instead of always "Imported 0 tasks."
public enum RemindersDrainOutcome: Sendable, Equatable {
    /// The "Tasks from Reminders" feature is turned off.
    case featureDisabled
    /// The feature is on, but no list has been chosen yet.
    case noListSelected
    /// Reminders access is not (or no longer) granted.
    case notAuthorized
    /// A drain pass was already running; this call coalesced into a no-op.
    case busy
    /// The configured list's identifier no longer resolves (see
    /// ``RemindersGatewayError/listUnavailable(id:)``).
    case listUnavailable(listID: String)
    /// The list resolved, but reading its reminders failed (see
    /// ``RemindersGatewayError/fetchFailed(id:)``).
    case fetchFailed(listID: String)
    /// Issue #66: the **automatic** (activation-triggered, no UI to confirm
    /// through) pass found more incomplete reminders than
    /// `RemindersImporter.autoImportLimit` and imported **nothing** rather
    /// than silently draining them all — the shape that put ~1,900 mostly
    /// unwanted reminders into tasks in one pass with no preview and no way
    /// to undo (the reminder is also deleted from Reminders.app on import,
    /// so a large surprise import had no recourse but a full local restore).
    /// The **manual** "Drain now" path is never subject to this — the UI
    /// gates it behind an explicit count preview + confirmation instead.
    case tooManyToAutoImport(listID: String, count: Int)
    /// The pass ran to completion. `imported` is the count of newly-created
    /// tasks; `deletedWithoutImport` counts reminders removed because they were
    /// already recorded in-flight from an interrupted prior pass (the
    /// create→delete crash-window cleanup), so a `0`-imported completion can
    /// still be distinguished from "the list was empty."
    case completed(imported: Int, deletedWithoutImport: Int)

    /// The number of newly-created tasks, or `0` for every non-`completed`
    /// case. Kept for call sites (tests, coarse UI checks) that only care
    /// about the count, not why it's zero.
    public var importedCount: Int {
        if case .completed(let imported, _) = self { return imported }
        return 0
    }
}

/// Issue #66: a non-mutating preview of what draining a list would do —
/// `RemindersImporter.preview(listID:)`'s result, shown by the manual
/// "Drain now" UI in a confirmation dialog before anything is imported or
/// removed from Reminders.
public struct RemindersDrainPreview: Sendable, Equatable {
    public let listID: String
    /// Incomplete reminders that a drain right now would import.
    public let candidateCount: Int

    public init(listID: String, candidateCount: Int) {
        self.listID = listID
        self.candidateCount = candidateCount
    }
}

/// Issue #66: the result of `RemindersImporter.undoLastImport()`.
public enum RemindersUndoOutcome: Sendable, Equatable {
    /// A drain pass was in progress; the undo coalesced into a no-op rather
    /// than racing the batch it would have read.
    case busy
    /// No import is recorded as undoable — either nothing has been imported
    /// yet this launch, or the last recorded batch was already undone.
    case nothingToUndo
    /// `count` tasks were soft-deleted (moved to Trash). May be fewer than
    /// the recorded batch size if a task was already gone by other means.
    case undone(count: Int)
}
