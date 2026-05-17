import SwiftUI
import LillistCore
import LillistUI

/// Modal sheet driven by the floating "+" overlay and the lock-screen
/// `QuickCaptureLockScreenIntent`. Hosts the shared `QuickCaptureField`
/// (which uses the same `QuickCaptureParser` as the macOS Quick Capture
/// surface) and creates a task with parsed tags and deadline on submit.
struct QuickCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env

    @State private var text: String = ""
    @State private var tagSuggestions: [String] = []
    @State private var submitting = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool
    @AppStorage("hasCapturedTask") private var hasCapturedTask = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                QuickCaptureField(
                    text: $text,
                    tagSuggestions: tagSuggestions,
                    dateSuggestions: ["today", "tomorrow", "+3d", "+1w"],
                    onSubmit: { _ in submit() }
                )
                .focused($focused)
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Quick Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { submit() }
                        .disabled(submitting || trimmedTitleIsEmpty)
                }
            }
        }
        .task {
            focused = true
            tagSuggestions = await loadTagSuggestions()
        }
    }

    private var trimmedTitleIsEmpty: Bool {
        QuickCaptureParser.parse(text).title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private func submit() {
        guard !submitting else { return }
        submitting = true
        let parsed = QuickCaptureParser.parse(text)
        let title = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            submitting = false
            return
        }
        // Drop the keyboard immediately so its collapse animation runs in
        // parallel with the Core Data + CloudKit write below.
        focused = false
        Task {
            do {
                let taskID = try await env.taskStore.create(title: title)
                for name in parsed.tags {
                    let tagID = try await env.tagStore.findOrCreate(name: name)
                    try await env.taskStore.assignTag(taskID: taskID, tagID: tagID)
                }
                if let dateToken = parsed.dateToken {
                    if let resolved = resolveDeadline(dateToken: dateToken) {
                        try await env.taskStore.update(id: taskID) { draft in
                            draft.deadline = resolved
                            draft.deadlineHasTime = false
                        }
                    }
                }
                hasCapturedTask = true
                submitting = false
                dismiss()
            } catch {
                errorMessage = "\(error)"
                submitting = false
            }
        }
    }

    private func resolveDeadline(dateToken: String) -> Date? {
        guard let rel = try? RelativeDate.parse(dateToken) else { return nil }
        return RelativeDateResolver.resolve(rel)
    }

    private func loadTagSuggestions() async -> [String] {
        // Top-of-tree tags as suggestions; deeper tags surface as user types.
        let roots = (try? await env.tagStore.children(of: nil)) ?? []
        return roots.map(\.name).sorted()
    }
}
