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

    /// Address crash reports are emailed to. Injected (defaulting to the
    /// resolved `LillistCoreContact.crashReportRecipient`) so snapshot
    /// tests render a deterministic, non-personal value and so the
    /// unconfigured ("") state can be exercised. Empty hides the
    /// recipient line.
    public let contactRecipient: String

    /// Single presentation slot for the three preview variants (full / logs /
    /// breadcrumbs). Three stacked `.sheet(isPresented:)` modifiers on one view
    /// let only the last present reliably; one `.sheet(item:)` fixes that.
    @State private var preview: PreviewPayload?

    /// The text to show in the (single) preview sheet. A fresh `id` per request
    /// re-presents the sheet even when re-previewing the same variant.
    private struct PreviewPayload: Identifiable {
        let id = UUID()
        let body: String
    }

    public init(
        model: CrashReportViewModel,
        buildVersion: String,
        osVersion: String,
        deviceModel: String,
        contactRecipient: String = LillistCoreContact.crashReportRecipient
    ) {
        self.model = model
        self.buildVersion = buildVersion
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.contactRecipient = contactRecipient
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
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(isOn: $model.includeLogs) {
                            VStack(alignment: .leading) {
                                Text("Recent app logs")
                                Text("Last 5 min, ~50 KB; reviewable below")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button("Preview these") {
                            Task {
                                let text = await model.renderPreview(
                                    includeLogs: true,
                                    includeBreadcrumbs: false,
                                    buildVersion: buildVersion,
                                    osVersion: osVersion,
                                    deviceModel: deviceModel
                                )
                                preview = PreviewPayload(body: text)
                            }
                        }
                        .font(.caption)
                        .accessibilityLabel(String(localized: "Preview the logs that would be sent", bundle: .module))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(isOn: $model.includeBreadcrumbs) {
                            VStack(alignment: .leading) {
                                Text("Last action breadcrumbs")
                                Text("No titles or content, just verbs and counts")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button("Preview these") {
                            Task {
                                let text = await model.renderPreview(
                                    includeLogs: false,
                                    includeBreadcrumbs: true,
                                    buildVersion: buildVersion,
                                    osVersion: osVersion,
                                    deviceModel: deviceModel
                                )
                                preview = PreviewPayload(body: text)
                            }
                        }
                        .font(.caption)
                        .accessibilityLabel(String(localized: "Preview the breadcrumbs that would be sent", bundle: .module))
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
                            preview = PreviewPayload(body: model.previewText)
                        }
                    }
                }
                Section {
                    if contactRecipient.isEmpty {
                        // No contact configured for this build (e.g. a fork
                        // that hasn't set LILLIST_CONTACT_EMAIL). Keep the
                        // privacy reassurance but omit the broken mailto.
                        Text("No third-party telemetry.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        // Embed the email as an explicit markdown link so the
                        // address renders as a clickable mailto. SwiftUI's
                        // automatic data-detection only links bare URLs/emails
                        // when the LocalizedStringKey is a compile-time literal;
                        // interpolated values are rendered as plain text, so
                        // we spell the link out to preserve the affordance.
                        Text("Reports go directly to Mikey ([\(contactRecipient)](mailto:\(contactRecipient))). No third-party telemetry.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .toggleStyle(.rainbow)
            .navigationTitle("Crash report")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Don't Send") {
                        Task {
                            try? await model.dontSend()
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send Report") {
                        Task {
                            try? await model.send()
                            dismiss()
                        }
                    }
                    .disabled(model.isSubmitting)
                }
            }
            .sheet(item: $preview) { payload in
                CrashReportPreviewSheet(body: payload.body)
            }
        }
    }
}
