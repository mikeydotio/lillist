#if canImport(MessageUI)
import SwiftUI
import MessageUI

struct MailComposerView: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    let attachment: (filename: String, data: Data)?
    /// `@MainActor` because the only thing callers do with the result
    /// is update SwiftUI state. Carrying the isolation in the closure
    /// type lets the nonisolated `MFMailComposeViewControllerDelegate`
    /// callback below invoke `onFinish` from inside a
    /// `MainActor.assumeIsolated { … }` block without smuggling
    /// non-Sendable state across actor boundaries.
    let onFinish: @MainActor (Result<MFMailComposeResult, Error>) -> Void

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
        let onFinish: @MainActor (Result<MFMailComposeResult, Error>) -> Void
        init(onFinish: @escaping @MainActor (Result<MFMailComposeResult, Error>) -> Void) {
            self.onFinish = onFinish
        }
        /// `MFMailComposeViewControllerDelegate` is declared
        /// `nonisolated` in the SDK so the conformance method
        /// inherits that isolation. UIKit, however, documents this
        /// callback as firing on the main thread, so we bridge into
        /// the main actor with `assumeIsolated` for the two pieces of
        /// main-actor work that follow (`controller.dismiss(...)` and
        /// the `onFinish` callback). `onFinish` is copied into a
        /// local first so the assumed-isolated closure doesn't have
        /// to capture `self`.
        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            let onFinish = self.onFinish
            MainActor.assumeIsolated {
                controller.dismiss(animated: true)
                if let error { onFinish(.failure(error)) } else { onFinish(.success(result)) }
            }
        }
    }
}
#endif
