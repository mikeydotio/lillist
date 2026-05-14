import Foundation
import OSLog

/// Abstracts log retrieval so the crash reporter can be tested
/// without depending on `OSLogStore` (which is unavailable or
/// permission-gated in sandboxed test environments).
public protocol LogFetching: Sendable {
    func fetchRecentLines(since: Date, subsystem: String) async throws -> [String]
}

/// Production implementation backed by `OSLogStore`.
///
/// Each line is the rendered composed message (no metadata) so the
/// resulting strings feed directly into `LogRedactor.redact`.
public struct OSLogFetcher: LogFetching {
    public init() {}

    public func fetchRecentLines(since: Date, subsystem: String) async throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let position = store.position(date: since)
        let entries = try store.getEntries(at: position)
        var lines: [String] = []
        for entry in entries {
            guard let logEntry = entry as? OSLogEntryLog else { continue }
            if logEntry.subsystem != subsystem { continue }
            lines.append("\(logEntry.date.ISO8601Format()) \(logEntry.composedMessage)")
        }
        return lines
    }
}
