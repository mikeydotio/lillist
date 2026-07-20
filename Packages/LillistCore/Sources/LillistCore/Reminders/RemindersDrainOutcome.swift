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
