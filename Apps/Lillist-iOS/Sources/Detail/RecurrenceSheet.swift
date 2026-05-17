import SwiftUI
import LillistCore
import LillistUI

struct RecurrenceSheet: View {
    let taskID: UUID
    let initialSeriesID: UUID?
    let onClose: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var viewModel: RecurrenceEditorViewModel
    @State private var errorMessage: String?

    init(
        taskID: UUID,
        initialRule: RecurrenceRule?,
        initialSeriesID: UUID?,
        initialAnchorDate: Date? = nil,
        onClose: @escaping () -> Void
    ) {
        self.taskID = taskID
        self.initialSeriesID = initialSeriesID
        self.onClose = onClose
        self._viewModel = State(initialValue: RecurrenceEditorViewModel(
            rule: initialRule,
            taskAnchorDate: initialAnchorDate
        ))
    }

    var body: some View {
        NavigationStack {
            RecurrenceEditorView(viewModel: $viewModel)
                .navigationTitle("Recurrence")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { onClose() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task { await commit(viewModel.build()) }
                        }
                    }
                }
                .alert(
                    "Couldn't save recurrence",
                    isPresented: Binding(
                        get: { errorMessage != nil },
                        set: { if !$0 { errorMessage = nil } }
                    ),
                    presenting: errorMessage
                ) { _ in
                    Button("OK", role: .cancel) { errorMessage = nil }
                } message: { msg in
                    Text(msg)
                }
        }
    }

    private func commit(_ rule: RecurrenceRule?) async {
        do {
            if let rule {
                if let sid = initialSeriesID {
                    try await env.seriesStore.update(id: sid, rule: rule)
                } else {
                    _ = try await env.seriesStore.create(fromSeedTask: taskID, rule: rule)
                }
            } else if let sid = initialSeriesID {
                try await env.seriesStore.delete(id: sid)
            }
            AccessibilityAnnouncements.post(
                rule == nil
                    ? String(localized: "Recurrence removed.")
                    : String(localized: "Recurrence saved."),
                priority: .low
            )
            onClose()
        } catch {
            errorMessage = error.localizedDescription
            AccessibilityAnnouncements.post(
                String(localized: "Couldn't save recurrence: \(error.localizedDescription)"),
                priority: .high
            )
        }
    }
}
