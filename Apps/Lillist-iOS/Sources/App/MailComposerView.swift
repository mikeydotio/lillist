#if canImport(MessageUI)
import SwiftUI
import MessageUI

struct MailComposerView: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    let attachment: (filename: String, data: Data)?
    let onFinish: (Result<MFMailComposeResult, Error>) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([recipient])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        if let attachment {
            vc.addAttachmentData(attachment.data, mimeType: "application/json", fileName: attachment.filename)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (Result<MFMailComposeResult, Error>) -> Void
        init(onFinish: @escaping (Result<MFMailComposeResult, Error>) -> Void) {
            self.onFinish = onFinish
        }
        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true)
            if let error { onFinish(.failure(error)) } else { onFinish(.success(result)) }
        }
    }
}
#endif
