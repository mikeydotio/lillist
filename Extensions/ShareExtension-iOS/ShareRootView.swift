import SwiftUI
import LillistCore

/// SwiftUI sheet shown when the user taps "Lillist" in another app's Share
/// menu. Pre-fills title/notes/url from the inbound payload, persists via
/// the App-Group-shared Core Data store so the main app sees the new task
/// on next foreground.
struct ShareRootView: View {
    let payload: SharePayload
    var onCancel: () -> Void
    var onSaved: () -> Void

    @State private var title = ""
    @State private var notes = ""
    @State private var attachedURL: URL?
    @State private var saving = false
    @State private var saveError: String?
    /// Set once the task is successfully created. On a retry after a
    /// failed link attachment we reuse this instead of creating a second
    /// task (see `ShareSaveFlow`).
    @State private var savedTaskID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $title)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
                if let url = attachedURL {
                    Section("Link") {
                        Text(url.absoluteString)
                            .font(.footnote)
                            .textSelection(.enabled)
                    }
                }
                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Save to Lillist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .disabled(title.isEmpty || saving)
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        let decoded = (try? await payload.decode()) ?? .init(suggestedTitle: "", notes: nil, url: nil)
        title = decoded.suggestedTitle
        notes = decoded.notes ?? ""
        attachedURL = decoded.url
    }

    private func save() async {
        saving = true
        defer { saving = false }
        saveError = nil
        do {
            // app-layer-test-rehab routed gated config resolution through
            // GatedPersistenceResolver so the in-flight-migration abort
            // branch lives in one tested place. If a migration is in
            // flight the resolver throws storeUnavailable and we surface
            // the message below so the user can retry.
            let appGroupID = "group.io.mikeydotio.Lillist"
            guard let resolver = GatedPersistenceResolver(appGroupID: appGroupID) else {
                saveError = "App Group container is not available."
                return
            }
            let persistence = try await resolver.makePersistence()
            let taskStore = TaskStore(persistence: persistence)
            let attachmentStore = AttachmentStore(persistence: persistence)

            // SSRF gate (link-preview-ssrf-guards Task 6 / residual #10):
            // reject a private/loopback/non-http(s) URL before it can be
            // persisted. We only attach when a URL is present AND allowed.
            let allowedURL: URL? = attachedURL.flatMap {
                URLPreviewPolicy.isAllowed($0) ? $0 : nil
            }
            if attachedURL != nil, allowedURL == nil {
                saveError = "That link can't be saved (private or unsupported address)."
                return
            }

            // Decide create-vs-reuse. On a retry after a failed link
            // attachment the task already exists, so we must not create a
            // second one — only re-attempt the attachment.
            let taskID: UUID
            switch ShareSaveFlow.next(savedTaskID: savedTaskID, hasURL: allowedURL != nil) {
            case .createTask:
                taskID = try await taskStore.create(title: title, notes: notes)
                savedTaskID = taskID
            case .attachLinkOnly(let existing):
                taskID = existing
            }

            // Link attachment failures are no longer swallowed: surface
            // them and keep the sheet open so the user can retry. The task
            // is already saved, so a retry won't duplicate it.
            if let url = allowedURL {
                _ = try await attachmentStore.addLinkPreview(
                    taskID: taskID,
                    url: url,
                    title: nil,
                    description: nil,
                    thumbnailData: nil,
                    faviconData: nil
                )
            }
            onSaved()
        } catch let LillistError.storeUnavailable(reason) {
            saveError = reason
        } catch {
            saveError = "\(error)"
        }
    }
}
