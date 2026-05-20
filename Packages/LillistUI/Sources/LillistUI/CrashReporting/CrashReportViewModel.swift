import Foundation
import Observation
import LillistCore

/// Backs `CrashReportSheet`. All assembly happens here so the view
/// stays purely declarative.
@MainActor
@Observable
public final class CrashReportViewModel: Identifiable {
    /// Stable identity for SwiftUI's `.sheet(item:)` binding. A fresh
    /// UUID per instance is sufficient — there is at most one model
    /// alive per `CrashReporterHost` at a time.
    public nonisolated let id = UUID()

    public var userDescription: String = ""
    public var includeLogs: Bool = true
    public var includeBreadcrumbs: Bool = true
    public var previewExpanded: Bool = false
    public private(set) var previewText: String = ""
    public private(set) var isSubmitting: Bool = false

    public let pending: CrashCanary
    private let reporter: CrashReporter

    public init(pending: CrashCanary, reporter: CrashReporter) {
        self.pending = pending
        self.reporter = reporter
    }

    /// Pure rendering of the report body for arbitrary include flags
    /// — does *not* touch `self.includeLogs` / `self.includeBreadcrumbs`,
    /// so per-toggle previews don't disturb the model. Used by both
    /// the bulk-preview button (driven by the model's own flags) and
    /// the per-toggle "Preview these" buttons added in Plan 18 Task 10.
    public func renderPreview(
        includeLogs: Bool,
        includeBreadcrumbs: Bool,
        buildVersion: String,
        osVersion: String,
        deviceModel: String
    ) async -> String {
        let report = CrashReport(
            buildVersion: buildVersion,
            osVersion: osVersion,
            deviceModel: deviceModel,
            canary: pending,
            userDescription: userDescription.isEmpty ? nil : userDescription,
            logs: includeLogs ? ["(logs will be loaded here when sent)"] : nil,
            breadcrumbs: includeBreadcrumbs ? [] : nil
        )
        return report.renderedAsPlainText()
    }

    /// Compose the would-be report (without sending) for the bulk
    /// "View what will be sent" sheet. Delegates to `renderPreview`
    /// and stores the result on `self.previewText`.
    public func refreshPreview(buildVersion: String, osVersion: String, deviceModel: String) async {
        previewText = await renderPreview(
            includeLogs: includeLogs,
            includeBreadcrumbs: includeBreadcrumbs,
            buildVersion: buildVersion,
            osVersion: osVersion,
            deviceModel: deviceModel
        )
    }

    /// Hit by the "Send report" button.
    public func send() async throws {
        isSubmitting = true
        defer { isSubmitting = false }
        try await reporter.submit(
            decision: .send,
            description: userDescription,
            includeLogs: includeLogs,
            includeBreadcrumbs: includeBreadcrumbs,
            pending: pending
        )
    }

    /// Hit by "Don't send".
    public func dontSend() async throws {
        try await reporter.submit(
            decision: .dontSend,
            description: nil,
            includeLogs: false,
            includeBreadcrumbs: false,
            pending: pending
        )
    }
}
