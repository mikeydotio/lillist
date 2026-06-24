import AppKit
import SwiftUI
import LillistCore
import LillistUI

/// Hosts the unified task editor as a singleton in-window overlay on macOS.
///
/// The macOS analogue of the iOS `TaskEditorHost`. Same two triggers and
/// the same `.taskEditorOverlay` presentation (a centered, dim-backed
/// floating card inside the main window — see engineering-notes for why
/// the in-window overlay replaced the docked detail column):
///
/// - `newCaptureTrigger` (the FAB / ⌘N binding) → open a `quick` draft.
/// - `openTaskID` (a row tap) → open an existing task in `full` mode.
///
/// Two macOS-specific divergences from the iOS host:
/// 1. Attachments use `NSOpenPanel` (not `PhotosPicker`), lifting the
///    same picker the floating `QuickCapturePanelController` uses.
/// 2. The capture-discard undo toast is omitted in this pass (the
///    `QuickCaptureDiscardToast` stays iOS-gated); a cancelled draft is
///    discarded silently, matching the panel's `close(cancelled:)`.
///
/// Note: the system-wide global-hotkey quick capture still flows through
/// `QuickCapturePanelController`'s separate `NSPanel` — it must work when
/// the main window is closed or another app is frontmost, which an
/// in-window overlay cannot. This host only owns the *in-app* path.
struct MacTaskEditorHost: ViewModifier {
    @Binding var newCaptureTrigger: Bool
    @Binding var openTaskID: UUID?
    let stores: TaskEditorModel.Stores
    var onChanged: () async -> Void = {}

    @State private var model: TaskEditorModel?
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .taskEditorOverlay(isPresented: $isPresented, onCancel: cancel) {
                if let model {
                    TaskEditorView(
                        model: model,
                        onDismiss: dismissCommitted,
                        onOpenSubtask: { id in openExisting(id) },
                        onAddAttachment: { presentAttachmentPicker(for: model) }
                    )
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
    /// soft-delete to Trash if it auto-promoted); an existing task just
    /// closes (already live-saved).
    private func cancel() {
        isPresented = false
        let model = self.model
        Task {
            if let model, model.presentation == .capture {
                await model.discard()
            } else {
                await model?.saveTextNow()
            }
            await onChanged()
        }
    }

    /// macOS attachment picker — `NSOpenPanel` restricted to images.
    /// Mirrors `QuickCapturePanelController.presentAttachmentPicker()`.
    private func presentAttachmentPicker(for model: TaskEditorModel) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.allowedContentTypes = [.image]
        openPanel.begin { response in
            guard response == .OK, let url = openPanel.url else { return }
            Task { @MainActor in
                guard let data = try? Data(contentsOf: url) else { return }
                try? await model.addImageAttachment(filename: url.lastPathComponent, data: data)
            }
        }
    }
}
