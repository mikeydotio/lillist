import SwiftUI
import LillistCore
import LillistUI

/// Inline form revealed when the user moves a task to Blocked, per design Section 4 and Section 7.
/// Submitting calls `TaskStore.scheduleFollowUp` (Plan 5), which creates a sibling task and
/// writes a `createdFollowUp` journal entry on the blocked task.
struct FollowUpFormView: View {
    @Environment(AppEnvironment.self) private var env
    let blockedTaskID: UUID
    let parentTitle: String
    var onCommit: () -> Void
    var onDismiss: () -> Void

    @State private var title: String = ""
    @State private var deadline: Date = Calendar.current.date(
        bySettingHour: 9, minute: 0, second: 0,
        of: Calendar.current.date(byAdding: .day, value: 1, to: Date())!
    )!

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Schedule follow-up", systemImage: "arrow.uturn.right.circle.fill")
                .font(.headline)
            TextField("Follow up on '\(parentTitle)'", text: $title)
                .textFieldStyle(.roundedBorder)
            DatePicker("Deadline", selection: $deadline, displayedComponents: [.date, .hourAndMinute])
            HStack {
                Button("Cancel", action: onDismiss).keyboardShortcut(.escape)
                Spacer()
                Button("Create follow-up") { Task { await submit() } }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Schedule follow-up form"))
    }

    private func submit() async {
        let useTitle = title.isEmpty ? "Follow up on '\(parentTitle)'" : title
        do {
            _ = try await env.taskStore.scheduleFollowUp(
                parentTaskID: blockedTaskID,
                title: useTitle,
                deadline: deadline
            )
            AccessibilityAnnouncements.post(
                String(localized: "Follow-up scheduled: \(useTitle)"),
                priority: .low
            )
            onCommit()
        } catch {
            AccessibilityAnnouncements.post(
                String(localized: "Couldn't schedule follow-up: \(error.localizedDescription)"),
                priority: .high
            )
        }
    }
}
