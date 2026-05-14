import SwiftUI

/// Placeholder for the recurrence editor slot.
///
/// Plan 4 landed the engine (`SeriesStore`, `RecurrenceRule`, auto-spawn on
/// close), so the data model is ready. The full UI editor (frequency picker,
/// byDay grid, byMonthDay pad, end-condition controls, "edit all future"
/// affordance backed by `SeriesStore.forkFutureFromInstance`) is a follow-up
/// task tracked outside this plan. Until it lands, this view shows the task's
/// current recurrence summary if one exists, or a disabled hint if not.
public struct RecurrenceFieldPlaceholderView: View {
    private let summary: String?
    public init(summary: String? = nil) {
        self.summary = summary
    }
    public var body: some View {
        HStack {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.tertiary)
            Text(summary ?? "Recurrence — tap to edit (coming soon)")
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .font(.subheadline)
        .accessibilityLabel(summary.map { "Recurrence: \($0)" } ?? "Recurrence editor not yet available")
    }
}
