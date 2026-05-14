import Foundation
import LillistCore

/// Opens `mailto:` via `/usr/bin/open` on macOS. Identical body
/// composition to the GUI's `MailtoTransport`, but standalone so
/// the CLI doesn't depend on AppKit.
public struct CLIMailtoTransport: CrashReportTransport {
    private let recipient: String
    public init(recipient: String = "mikeyward@gmail.com") { self.recipient = recipient }
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

        (Attach the .lillistcrash file from \(tmp.path) if your mail client did not auto-attach it.)
        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        guard let url = components.url else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = [url.absoluteString]
        try task.run()
        task.waitUntilExit()
        FileHandle.standardError.write(Data("Crash report staged at \(tmp.path)\n".utf8))
    }
}
