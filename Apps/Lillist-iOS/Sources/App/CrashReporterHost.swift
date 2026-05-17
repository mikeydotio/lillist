import SwiftUI
import UIKit
import LillistCore
import LillistUI
#if canImport(MessageUI)
import MessageUI
#endif

struct CrashReporterHost<Content: View>: View {
    @State private var pending: CrashCanary?
    @State private var model: CrashReportViewModel?
    @State private var presenting = false
    @State private var mailPending: MailComposerTransport.Pending?
    @State private var clipboardConfirmation: String?

    let reporter: CrashReporter
    let mailTransport: MailComposerTransport
    let buildVersion: String
    let osVersion: String
    let deviceModel: String
    let crashPromptsEnabled: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .task {
                mailTransport.onStage = { staged in
                    Task { @MainActor in self.mailPending = staged }
                }
                guard crashPromptsEnabled else { return }
                let p = try? await reporter.detectAndPrepare()
                guard let p else { return }
                pending = p
                model = CrashReportViewModel(pending: p, reporter: reporter)
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
            .sheet(item: Binding<MailComposerTransport.Pending?>(
                get: { mailPending },
                set: { mailPending = $0 }
            )) { staged in
                #if canImport(MessageUI)
                if MFMailComposeViewController.canSendMail() {
                    MailComposerView(
                        recipient: "mikeyward@gmail.com",
                        subject: staged.subject,
                        body: staged.body,
                        attachment: (staged.attachmentName, staged.attachmentData),
                        onFinish: { _ in mailPending = nil }
                    )
                } else {
                    clipboardFallback(for: staged)
                }
                #else
                Text("Mail unavailable on this platform.")
                #endif
            }
            .alert(
                String(localized: "Copied"),
                isPresented: Binding(
                    get: { clipboardConfirmation != nil },
                    set: { if !$0 { clipboardConfirmation = nil } }
                )
            ) {
                Button("OK", role: .cancel) { clipboardConfirmation = nil }
            } message: {
                Text(clipboardConfirmation ?? "")
            }
    }

    /// Fallback view shown when `MFMailComposeViewController.canSendMail()`
    /// returns false (fresh simulator, or a device with no Mail account).
    /// Offers the user a way to extract the report instead of leaving them
    /// at a dead-end "Mail not configured" text.
    @ViewBuilder
    private func clipboardFallback(for staged: MailComposerTransport.Pending) -> some View {
        VStack(spacing: 16) {
            Text("Mail is not configured on this device.")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Copy the report to your clipboard to paste into any email or messaging app.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                UIPasteboard.general.string = "Subject: \(staged.subject)\n\n\(staged.body)"
                clipboardConfirmation = String(localized: "Crash report copied to clipboard.")
                mailPending = nil
            } label: {
                Label("Copy report to clipboard", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Button("Cancel") { mailPending = nil }
        }
        .padding()
        .frame(maxWidth: 400)
    }
}
