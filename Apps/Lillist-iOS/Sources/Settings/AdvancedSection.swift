import SwiftUI
import LillistCore

struct AdvancedSection: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var exportedURL: URL?
    @State private var isExporting = false
    @State private var lastError: String?

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
            if let lastError {
                Text(lastError)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
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
}
