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
        do {
            // Plan 21: resolve the store configuration through the
            // MigrationGate (via GatedPersistenceResolver) so the
            // extension doesn't race a foreground sync-mode migration.
            // If a migration is in flight the resolver throws
            // storeUnavailable, caught below to surface the retry message.
            let appGroupID = "group.io.mikeydotio.Lillist"
            guard let resolver = GatedPersistenceResolver(appGroupID: appGroupID) else {
                saveError = "App Group container is not available."
                return
            }
            let persistence = try await resolver.makePersistence()
            let taskStore = TaskStore(persistence: persistence)
            let attachmentStore = AttachmentStore(persistence: persistence)
            let taskID = try await taskStore.create(title: title, notes: notes)
            if let url = attachedURL {
                _ = try? await attachmentStore.addLinkPreview(
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
