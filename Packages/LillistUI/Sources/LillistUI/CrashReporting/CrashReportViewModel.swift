import Foundation
import Observation
import LillistCore

/// Backs `CrashReportSheet`. All assembly happens here so the view
/// stays purely declarative.
@MainActor
@Observable
public final class CrashReportViewModel {
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

    /// Compose the would-be report (without sending) for the
    /// "View what will be sent" sheet.
    public func refreshPreview(buildVersion: String, osVersion: String, deviceModel: String) async {
        let report = CrashReport(
            buildVersion: buildVersion,
            osVersion: osVersion,
            deviceModel: deviceModel,
            canary: pending,
            userDescription: userDescription.isEmpty ? nil : userDescription,
            logs: includeLogs ? ["(logs will be loaded here when sent)"] : nil,
            breadcrumbs: includeBreadcrumbs ? [] : nil
        )
        previewText = report.renderedAsPlainText()
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
