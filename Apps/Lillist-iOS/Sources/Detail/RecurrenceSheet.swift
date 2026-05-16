import SwiftUI
import LillistCore
import LillistUI

struct RecurrenceSheet: View {
    let taskID: UUID
    let initialSeriesID: UUID?
    let onClose: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var viewModel: RecurrenceEditorViewModel

    init(taskID: UUID, initialRule: RecurrenceRule?, initialSeriesID: UUID?, onClose: @escaping () -> Void) {
        self.taskID = taskID
        self.initialSeriesID = initialSeriesID
        self.onClose = onClose
        self._viewModel = State(initialValue: RecurrenceEditorViewModel(rule: initialRule))
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
            onClose()
        } catch {
            // Sheet remains open; future polish would surface an inline error.
        }
    }
}
