import SwiftUI
import UniformTypeIdentifiers
import LillistCore

struct AdvancedSection: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var exportedURL: URL?
    @State private var isExporting = false
    @State private var lastError: String?
    @State private var isImporting = false
    @State private var importSummary: Importer.ImportSummary?
    @State private var showImportPicker = false

    var body: some View {
        Section("Advanced") {
            Button {
                Task { await runExport() }
            } label: {
                if isExporting {
                    ProgressView()
                } else {
                    Text("Export now…")
                }
            }
            .disabled(isExporting)
            if let url = exportedURL {
                ShareLink(item: url) {
                    Label("Share export", systemImage: "square.and.arrow.up")
                }
            }
            Button {
                showImportPicker = true
            } label: {
                if isImporting {
                    ProgressView()
                } else {
                    Text("Import Data…")
                }
            }
            .disabled(isImporting)
            if let summary = importSummary {
                Text("Imported \(summary.tasksInserted) new tasks, updated \(summary.tasksUpdated), skipped \(summary.tasksSkipped).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let lastError {
                Text(lastError)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.folder],
            onCompletion: { result in
                switch result {
                case .success(let url):
                    Task { await runImport(at: url) }
                case .failure(let error):
                    lastError = "Picker failed: \(error.localizedDescription)"
                }
            }
        )
    }

    private func runExport() async {
        isExporting = true
        lastError = nil
        defer { isExporting = false }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("Lillist-Export-\(Int(Date().timeIntervalSince1970))", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            let exporter = Exporter(
                persistence: environment.persistence,
                preferences: environment.preferencesStore
            )
            try await exporter.export(to: tmp)
            exportedURL = tmp
        } catch {
            lastError = "Export failed: \(error.localizedDescription)"
        }
    }

    private func runImport(at url: URL) async {
        isImporting = true
        lastError = nil
        defer { isImporting = false }
        // Document picker URLs come security-scoped on iOS.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let importer = Importer(persistence: environment.persistence)
        do {
            importSummary = try await importer.importBundle(at: url, conflictPolicy: .skipExisting)
        } catch {
            lastError = "Import failed: \(error.localizedDescription)"
        }
    }
}
