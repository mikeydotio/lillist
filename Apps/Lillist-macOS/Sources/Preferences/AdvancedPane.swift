import SwiftUI
import AppKit
import LillistCore

/// macOS Preferences Advanced pane (Plan 10 Task 9).
///
/// Two actions:
/// - **Export now…**: triggers `LillistCore.Exporter.export(to:)` against a
///   user-chosen directory (NSOpenPanel), reveals the result in Finder on
///   success.
/// - **Reveal store in Finder**: opens the SQLite file location via
///   `NSWorkspace.activateFileViewerSelecting`.
struct AdvancedPane: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isExporting = false
    @State private var lastExportError: String?

    var body: some View {
        Form {
            Section("Data") {
                Button {
                    Task { await runExport() }
                } label: {
                    if isExporting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Export now…")
                    }
                }
                .disabled(isExporting)

                Button("Reveal store in Finder") {
                    revealStoreInFinder()
                }
            }
            if let lastExportError {
                Section {
                    Text(lastExportError)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func runExport() async {
        // Pick a *fresh* empty directory inside a user-chosen parent —
        // Exporter requires its destination to be empty, and forcing the
        // user to create a directory first is hostile.
        let panel = NSOpenPanel()
        panel.title = "Choose an export destination"
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let parent = panel.url else { return }

        let ts = Int(Date().timeIntervalSince1970)
        let dir = parent.appendingPathComponent("Lillist-Export-\(ts)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        } catch {
            lastExportError = "Couldn't create export directory: \(error.localizedDescription)"
            return
        }

        isExporting = true
        defer { isExporting = false }
        do {
            let exporter = Exporter(
                persistence: environment.persistence,
                preferences: environment.preferencesStore
            )
            try await exporter.export(to: dir)
            lastExportError = nil
            NSWorkspace.shared.activateFileViewerSelecting([dir])
        } catch {
            lastExportError = "Export failed: \(error.localizedDescription)"
        }
    }

    private func revealStoreInFinder() {
        guard case .onDisk(let url) = environment.persistence.configuration.storeKind else {
            lastExportError = "In-memory store has no file to reveal."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
