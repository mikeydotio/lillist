import Foundation

/// Pure title normalization for `AddTaskIntent`, extracted so it can be
/// unit-tested from the standalone iOS test bundle without a ShortcutsActions
/// extension test host (mirrors the `ReportCrashIntentResolver` pattern).
enum AddTaskInput {
    /// Trim a spoken/typed title. Returns `nil` when nothing usable remains —
    /// the caller then re-requests the value from the user via Siri.
    static func normalizedTitle(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
