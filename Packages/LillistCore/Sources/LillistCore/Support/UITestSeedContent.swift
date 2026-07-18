import Foundation

/// Shared source of truth for UI-test seed content that must agree across
/// process/target boundaries.
///
/// The `--ui-test-seed-fat-notes` seam (in the app target) creates a task with
/// this body, and the app-hosted `GlassSnapshotTests` boundary probes measure a
/// card built from the *same* body. If the two drifted, the probes would report
/// boundary numbers for a different card than the UI test actually drives — and
/// both would keep passing against different inputs, so the divergence would be
/// invisible. Keeping the body here (the lowest shared layer both import) makes
/// them build the same card by construction.
public enum UITestSeedContent {
    /// Title of the single task the `--ui-test-seed-fat-notes` seam creates.
    /// The UI-test bundle can't import LillistCore (it's black-box against the
    /// app), so `UITestHelpers` repeats this literal; a mismatch there fails
    /// loudly (the row is never found), unlike a silent body drift.
    public static let fatNotesTaskTitle = "uitest-fat-notes"

    /// A notes body long enough to drive the full editor's content-hugging
    /// notes field (`.lineLimit(2...8)`) to its scroll cap, so the detail card
    /// is tall enough to cross the keyboard-driven fit boundary.
    public static func fatNotesBody() -> String {
        (1...10)
            .map { "Notes line \($0): detail that grows the content-hugging box." }
            .joined(separator: "\n")
    }
}
