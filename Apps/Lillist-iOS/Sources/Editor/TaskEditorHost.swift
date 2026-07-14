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
    /// Seed text handed off by the Quick Capture App Intent (via
    /// `AppEnvironment.pendingQuickCaptureSeed`). When non-nil, opens a new
    /// capture pre-filled with the text; reset to `nil` once consumed. Unlike
    /// `newCaptureTrigger` (a bare Bool), this carries the prefill.
    @Binding var captureSeed: String?
    let stores: TaskEditorModel.Stores
    var onChanged: () async -> Void = {}

    @State private var model: TaskEditorModel?
    @State private var isPresented = false
    @State private var showPhotoPicker = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var discardedText = ""
    @State private var showDiscardToast = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                QuickCaptureDiscardToast(isPresented: $showDiscardToast, onUndo: undoDiscard)
            }
            .taskEditorOverlay(isPresented: $isPresented, onCancel: cancel) {
                if let model {
                    TaskEditorView(
                        model: model,
                        onDismiss: dismissCommitted,
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
            .onChange(of: captureSeed) { _, seed in
                consumeSeed(seed)
            }
            // Cold-launch case: the seed may already be set before this view
            // appears (bootstrap consumes the handoff), so .onChange never
            // fires — consume the initial value here too.
            .task { consumeSeed(captureSeed) }
    }

    /// Open a pre-filled capture for a handed-off seed, then clear it so it
    /// can't re-fire. A non-nil seed (including `""`) means "open the dialog".
    private func consumeSeed(_ seed: String?) {
        guard let seed else { return }
        openNewCapture(prefill: seed)
        captureSeed = nil
    }

    private func openNewCapture(prefill: String = "") {
        guard !isPresented else { return }   // singleton: ignore while open
        let m = TaskEditorModel(stores: stores, opening: .newCapture(parentID: nil, placement: .top))
        m.captureText = prefill
        model = m
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
    /// A non-empty pure draft offers an Undo toast that re-opens it.
    private func cancel() {
        isPresented = false
        let model = self.model
        Task {
            if let model, model.presentation == .capture {
                // Preserve the user's text for Undo before discarding (only
                // for a pure, never-promoted draft — a promoted one lands in
                // Trash with its own recovery).
                if model.taskID == nil {
                    let text = model.captureText.isEmpty ? model.title : model.captureText
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        discardedText = text
                        showDiscardToast = true
                    }
                }
                await model.discard()
            } else {
                await model?.saveTextNow()
            }
            await onChanged()
        }
    }

    private func undoDiscard() {
        let text = discardedText
        discardedText = ""
        showDiscardToast = false
        openNewCapture(prefill: text)
    }
}
