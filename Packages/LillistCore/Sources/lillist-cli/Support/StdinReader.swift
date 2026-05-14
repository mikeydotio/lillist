import Foundation
import LillistCore

/// Reads identifiers (one per line) from stdin for batch mode.
public enum StdinReader {
    public static let sentinel = "-"

    public static func isStdinSentinel(_ token: String) -> Bool {
        token == sentinel
    }

    public static func readAllLines() -> [String] {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return linesFromData(data)
    }

    public static func linesFromData(_ data: Data) -> [String] {
        guard let s = String(data: data, encoding: .utf8) else { return [] }
        return s.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.isEmpty == false }
    }

    /// Verifies that every line is a parseable UUID. Returns the lines if so;
    /// throws `LillistError.validationFailed` otherwise. Used by destructive
    /// verbs that read tokens from stdin.
    public static func validateAllUUIDs(_ lines: [String]) throws -> [String] {
        for line in lines {
            if UUID(uuidString: line) == nil {
                throw LillistError.validationFailed([
                    .init(field: "stdin", message: "destructive verbs reject non-UUID tokens; pass --allow-fuzzy-from-stdin to override. Offending line: '\(line)'")
                ])
            }
        }
        return lines
    }
}
