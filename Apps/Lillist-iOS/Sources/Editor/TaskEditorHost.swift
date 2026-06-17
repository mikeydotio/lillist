import SwiftUI
import PhotosUI
import LillistCore
import LillistUI

/// Hosts the unified task editor as a singleton floating overlay on iOS.
/// Replaces `QuickCaptureDialogHost`: the same surface now handles both quick
/// capture (new) and full editing (existing), driven by two triggers:
///
/// - `newCaptureTrigger` (the FAB / ⌘⇧N binding) → open a `quick` draft.
/// - `openTaskID` (a row tap) → open an existing task in `full` mode.
///
/// Singleton: only one editor at a time. Opening while presented re-targets
/// (existing) or is ignored (new capture). Tap-outside / Esc cancels — a
/// capture draft is discarded, an existing task just closes (already
/// live-saved). The `onChanged` closure refreshes the owning list.
struct TaskEditorHost: ViewModifier {
    @Binding var newCaptureTrigger: Bool
    @Binding var openTaskID: UUID?
    let stores: TaskEditorModel.Stores
    var onChanged: () async -> Void = {}

    @State private var model: TaskEditorModel?
    @State private var isPresented = false
    @State private var showPhotoPicker = false
    @State private var pickedItem: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .taskEditorOverlay(isPresented: $isPresented, onCancel: cancel) {
                if let model {
                    TaskEditorView(
                        model: model,
                        onDismiss: dismissCommitted,
                        onOpenSubtask: { id in openExisting(id) },
                        onAddAttachment: { showPhotoPicker = true }
                    )
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $pickedItem, matching: .images)
            .onChange(of: pickedItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        try? await model?.addImageAttachment(
                            filename: "image-\(UUID().uuidString).jpg",
                            data: data
                        )
                    }
                    pickedItem = nil
                }
            }
            .onChange(of: newCaptureTrigger) { _, trigger in
                if trigger {
                    openNewCapture()
                    newCaptureTrigger = false
                }
            }
            .onChange(of: openTaskID) { _, id in
                if let id {
                    openExisting(id)
                    openTaskID = nil
                }
            }
    }

    private func openNewCapture() {
        guard !isPresented else { return }   // singleton: ignore while open
        model = TaskEditorModel(stores: stores, opening: .newCapture(parentID: nil, placement: .top))
        isPresented = true
    }

    private func openExisting(_ id: UUID) {
        let m = TaskEditorModel(stores: stores, opening: .existing(id))
        model = m                            // re-target (replaces any open editor)
        isPresented = true
        Task { await m.load() }
    }

    /// Committed/explicit dismissal (Add / Done): the task is already
    /// persisted/live-saved; just close and refresh.
    private func dismissCommitted() {
        isPresented = false
        Task { await onChanged() }
    }

    /// Tap-outside / Esc: discard a capture draft (nothing persisted, or a
    /// soft-delete to Trash if it auto-promoted); an existing task just closes.
    private func cancel() {
        isPresented = false
        Task {
            if let model, model.presentation == .capture {
                await model.discard()
            } else {
                await model?.saveTextNow()
            }
            await onChanged()
        }
    }
}
