import SwiftUI
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
                    Text("Mail is not configured on this device.")
                        .padding()
                }
                #else
                Text("Mail unavailable on this platform.")
                #endif
            }
    }
}
