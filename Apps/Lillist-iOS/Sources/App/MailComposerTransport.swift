import Foundation
import LillistCore

/// iOS transport. The transport prepares the payload and stages a
/// pending presentation; the SwiftUI host pulls the staged value
/// and presents `MailComposerView`. This indirection keeps
/// `CrashReportTransport`'s `send(_:)` async-throwing as the protocol
/// defines, while still allowing the SwiftUI host to present
/// `MFMailComposeViewController` from a main-actor sheet.
public final class MailComposerTransport: CrashReportTransport, @unchecked Sendable {
    public struct Pending: Sendable, Identifiable {
        public let subject: String
        public let body: String
        public let attachmentName: String
        public let attachmentData: Data
        public var id: String { attachmentName }
    }

    private let queue = DispatchQueue(label: "MailComposerTransport.queue")
    private var pending: Pending?
    /// Hook for the SwiftUI host to learn that a payload is ready to
    /// present. Set on the main actor; called from background.
    public var onStage: (@Sendable (Pending) -> Void)?

    public init() {}

    public func send(_ report: CrashReport) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        let staged = Pending(
            subject: "Lillist crash report \(report.buildVersion)",
            body: report.renderedAsPlainText(),
            attachmentName: "lillist-crash-\(UUID().uuidString).lillistcrash",
            attachmentData: data
        )
        queue.sync { pending = staged }
        onStage?(staged)
    }
}
