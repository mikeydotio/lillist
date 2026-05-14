import Foundation

/// Strategy interface for delivering a crash report.
///
/// All transports are user-mediated per design Section 8:
/// `mailto:` opens the user's mail client with the payload prefilled
/// and *they* hit send; "Save as file…" produces a `.lillistcrash`
/// bundle the user can move and email later.
public protocol CrashReportTransport: Sendable {
    func send(_ report: CrashReport) async throws
}

/// Test-only transport that records every send for inspection.
public actor RecordingTransport: CrashReportTransport {
    public private(set) var captured: [CrashReport] = []
    public init() {}
    public func send(_ report: CrashReport) async throws {
        captured.append(report)
    }
}

/// Writes the report to a user-chosen file path as a `.lillistcrash`
/// bundle (currently a plain JSON encoding of the report; zip-style
/// bundling is a v2 nicety once a zip dependency is justified).
public struct FileSaveTransport: CrashReportTransport {
    public let destination: URL
    public init(destination: URL) {
        self.destination = destination
    }
    public func send(_ report: CrashReport) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try data.write(to: destination, options: .atomic)
    }
}
