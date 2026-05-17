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
                    // i18n-exempt: these are also the literal parser tokens
                    // accepted by RelativeDate.parse. Localizing the chip
                    // labels without first teaching the parser to accept
                    // localized aliases would break the round-trip. Tracked
                    // for a future plan.
                    dateSuggestions: ["today", "tomorrow", "+3d", "+1w"],
                    onSubmit: { _ in submit() }
                )
                .focused($focused)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(String(localized: "Title, required"))
                .accessibilityValue(trimmedTitleIsEmpty
                    ? String(localized: "Empty")
                    : String(localized: "Not empty")
                )
                if let errorMessage {
                    // SwiftUI has no `.accessibilityLiveRegion(_:)` modifier
                    // (it's an HTML/UIKit concept). The `updatesFrequently`
                    // trait hints VoiceOver to re-poll the content for
                    // changes; the assertive re-read comes from the
                    // AccessibilityAnnouncements.post call in submit().
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Quick Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { submit() }
                        .keyboardShortcut(.defaultAction)
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
        // No empty-title guard: Save is `.disabled(trimmedTitleIsEmpty)`
        // and QuickCaptureField.onSubmit doesn't fire on empty text.
        // See Plan 18 Task 3 + QuickCaptureSheetGuardTests.
        let title = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
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
                AccessibilityAnnouncements.post(
                    String(localized: "Task created: \(title)"),
                    priority: .low
                )
                dismiss()
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

    private func loadTagSuggestions() async -> [String] {
        // Top-of-tree tags as suggestions; deeper tags surface as user types.
        let roots = (try? await env.tagStore.children(of: nil)) ?? []
        return roots.map(\.name).sorted()
    }
}
