import SwiftUI
import LillistCore
import LillistUI

/// View modifier that hosts the Quick Capture dialog and its companion
/// discard toast. Attached by the iOS shells (`TabShell`, `SplitShell`)
/// via `.modifier(QuickCaptureDialogHost(isPresented:))`.
///
/// Owns:
/// - The editor text (`text`), error state, and submitting guard.
/// - The lock that keeps a fast Return-press from spawning two writes.
/// - The discard-toast bookkeeping (`discardedText`, `showDiscardToast`).
///
/// The host runs the same parse → create → assign tag → set deadline
/// pipeline the old `QuickCaptureSheet` ran. The empty-title guard is
/// now inside `submit()` itself (previously the disabled Save button
/// stopped empty submissions; with no Save button the gate has to
/// live here). `QuickCaptureDialogGuardTests` covers the predicate.
struct QuickCaptureDialogHost: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(AppEnvironment.self) private var env

    @State private var text: String = ""
    @State private var errorMessage: String?
    @State private var submitting = false
    @State private var discardedText: String = ""
    @State private var showDiscardToast = false

    func body(content: Content) -> some View {
        content
            .quickCaptureDialog(
                isPresented: $isPresented,
                onCancel: handleCancel
            ) {
                QuickCaptureDialog(
                    text: $text,
                    errorMessage: errorMessage,
                    onSubmit: submit
                )
            }
            .overlay(alignment: .bottom) {
                QuickCaptureDiscardToast(
                    isPresented: $showDiscardToast,
                    onUndo: undoDiscard
                )
            }
            .onChange(of: isPresented) { _, newValue in
                if !newValue {
                    text = ""
                    errorMessage = nil
                }
            }
    }

    private func handleCancel() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        discardedText = text
        showDiscardToast = true
    }

    private func undoDiscard() {
        text = discardedText
        discardedText = ""
        isPresented = true
    }

    private func submit() {
        guard !submitting else { return }
        let parsed = QuickCaptureParser.parse(text)
        let title = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
        // Plan 22: the dialog has no Save button, so the empty-title
        // gate that lived on the old sheet's `.disabled(...)` modifier
        // moves here. See `QuickCaptureDialogGuardTests`.
        guard !title.isEmpty else { return }
        submitting = true
        Task {
            do {
                let taskID = try await env.taskStore.create(title: title)
                for name in parsed.tags {
                    let tagID = try await env.tagStore.findOrCreate(name: name)
                    try await env.taskStore.assignTag(taskID: taskID, tagID: tagID)
                }
                if let dateToken = parsed.dateToken,
                   let resolved = resolveDeadline(dateToken: dateToken) {
                    try await env.taskStore.update(id: taskID) { draft in
                        draft.deadline = resolved
                        draft.deadlineHasTime = false
                    }
                }
                submitting = false
                AccessibilityAnnouncements.post(
                    String(localized: "Task created: \(title)"),
                    priority: .low
                )
                isPresented = false
            } catch {
                errorMessage = "\(error)"
                AccessibilityAnnouncements.post(
                    String(localized: "Couldn't create task: \(error.localizedDescription)"),
                    priority: .high
                )
                submitting = false
            }
        }
    }

    private func resolveDeadline(dateToken: String) -> Date? {
        guard let rel = try? RelativeDate.parse(dateToken) else { return nil }
        return RelativeDateResolver.resolve(rel)
    }
}
