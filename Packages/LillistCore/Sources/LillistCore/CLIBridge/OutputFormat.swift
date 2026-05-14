import Foundation

extension CLIBridge {
    public enum OutputFormat: String, CaseIterable, Sendable, Codable {
        case pretty
        case json
        case ndjson
        case tsv
    }
}
