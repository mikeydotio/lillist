import SwiftUI
import LillistCore

public struct CrashReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable public var model: CrashReportViewModel

    /// Caller-provided metadata so the view model can render an
    /// honest preview (build/OS/device come from the host process).
    public let buildVersion: String
    public let osVersion: String
    public let deviceModel: String

    @State private var showingPreview = false

    public init(
        model: CrashReportViewModel,
        buildVersion: String,
        osVersion: String,
        deviceModel: String
    ) {
        self.model = model
        self.buildVersion = buildVersion
        self.osVersion = osVersion
        self.deviceModel = deviceModel
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Lillist quit unexpectedly last time.")
                        .font(.headline)
                    Text("Help me make it more reliable by sending a quick report. Totally optional.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section("What were you doing?") {
                    TextEditor(text: $model.userDescription)
                        .frame(minHeight: 80)
                        .accessibilityLabel(String(localized: "Description of what you were doing", bundle: .module))
                }
                Section("What to include") {
                    Toggle(isOn: $model.includeLogs) {
                        VStack(alignment: .leading) {
                            Text("Recent app logs")
                            Text("Last 5 min, ~50 KB; reviewable below")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: $model.includeBreadcrumbs) {
                        VStack(alignment: .leading) {
                            Text("Last action breadcrumbs")
                            Text("No titles or content, just verbs and counts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Button("View what will be sent") {
                        Task {
                            await model.refreshPreview(
                                buildVersion: buildVersion,
                                osVersion: osVersion,
                                deviceModel: deviceModel
                            )
                            showingPreview = true
                        }
                    }
                }
                Section {
                    Text("Reports go directly to Mikey (mikeyward@gmail.com). No third-party telemetry.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Crash report")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Don't send") {
                        Task {
                            try? await model.dontSend()
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send report") {
                        Task {
                            try? await model.send()
                            dismiss()
                        }
                    }
                    .disabled(model.isSubmitting)
                }
            }
            .sheet(isPresented: $showingPreview) {
                CrashReportPreviewSheet(body: model.previewText)
            }
        }
    }
}
