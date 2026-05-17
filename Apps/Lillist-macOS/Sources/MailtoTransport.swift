import AppKit
import Foundation
import LillistCore

/// Writes the rendered report to a temp `.lillistcrash` file, then
/// opens a `mailto:` URL referencing it. The user attaches the file
/// themselves — `mailto:` cannot carry attachments. The body of
/// the email contains a one-line "see attached" plus build/OS so
/// the user has minimum context if they don't attach the file.
public struct MailtoTransport: CrashReportTransport {
    private let recipient: String
    public init(recipient: String = LillistCoreContact.crashReportRecipient) {
        self.recipient = recipient
    }
    public func send(_ report: CrashReport) async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("lillist-crash-\(UUID().uuidString).lillistcrash")
        try await FileSaveTransport(destination: tmp).send(report)

        let subject = "Lillist crash report \(report.buildVersion)"
        let body = """
        Attached: \(tmp.lastPathComponent)

        Build: \(report.buildVersion)
        OS: \(report.osVersion)
        Device: \(report.deviceModel)

        (Attach the .lillistcrash file from your downloads if your mail client did not auto-attach it.)
        """

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        guard let url = components.url else { return }
        await MainActor.run {
            NSWorkspace.shared.open(url)
            NSWorkspace.shared.activateFileViewerSelecting([tmp])
        }
    }
}
