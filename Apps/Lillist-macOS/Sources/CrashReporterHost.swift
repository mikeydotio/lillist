import SwiftUI
import LillistCore
import LillistUI

/// Sits at the root of the macOS scene and presents the crash
/// report sheet on first appearance if a stale canary was detected.
struct CrashReporterHost<Content: View>: View {
    @State private var pendingCanary: CrashCanary?
    @State private var presenting = false
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
                pendingCanary = pending
                model = CrashReportViewModel(pending: pending, reporter: reporter)
                presenting = true
            }
            .sheet(isPresented: $presenting) {
                if let model {
                    CrashReportSheet(
                        model: model,
                        buildVersion: buildVersion,
                        osVersion: osVersion,
                        deviceModel: deviceModel
                    )
                }
            }
    }
}
