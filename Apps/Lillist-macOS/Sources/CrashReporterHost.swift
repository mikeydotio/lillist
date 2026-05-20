import SwiftUI
import LillistCore
import LillistUI

/// Sits at the root of the macOS scene and presents the crash
/// report sheet on first appearance if a stale canary was detected.
struct CrashReporterHost<Content: View>: View {
    /// `.sheet(item:)` binds presentation directly to model presence —
    /// the sheet cannot appear without a non-nil `CrashReportViewModel`,
    /// which structurally rules out the "empty modal" failure mode that
    /// `.sheet(isPresented:) + if let model` permitted.
    @State private var model: CrashReportViewModel?

    let reporter: CrashReporter
    let buildVersion: String
    let osVersion: String
    let deviceModel: String
    let crashPromptsEnabled: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .task {
                guard crashPromptsEnabled else { return }
                let pending = try? await reporter.detectAndPrepare()
                guard let pending else { return }
                model = CrashReportViewModel(pending: pending, reporter: reporter)
            }
            .sheet(item: $model) { model in
                CrashReportSheet(
                    model: model,
                    buildVersion: buildVersion,
                    osVersion: osVersion,
                    deviceModel: deviceModel
                )
            }
    }
}
