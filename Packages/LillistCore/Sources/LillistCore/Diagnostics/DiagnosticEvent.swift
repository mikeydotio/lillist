import Foundation

/// The process that authored a diagnostic event. One JSONL file is written per
/// process per day, so this also names the file (`diag-<day>-<process>.jsonl`).
public enum DiagProcess: String, Codable, Sendable {
    case app, macApp, shareExtension, appIntents, cli
}

/// Coarse classification of a diagnostic event for at-a-glance triage.
public enum DiagCategory: String, Codable, Sendable {
    case data, ui, lifecycle
}

/// A typed leaf so payloads stay structured but flexible.
///
/// JSON numbers carry no int/double distinction: an integral double (`2.0`)
/// serializes as `2` and therefore decodes back as `.int(2)`. That normalization
/// is intentional — a diagnostics value model does not need a tagged-number
/// encoding to preserve a distinction nothing downstream relies on (YAGNI).
public enum DiagValue: Codable, Sendable, Equatable {
    case string(String), int(Int), double(Double), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let i = try? c.decode(Int.self) { self = .int(i) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else { self = .string(try c.decode(String.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        }
    }
}

/// One line in a per-process JSONL diagnostic file.
///
/// Mirrors the `Breadcrumb`/`CrashReport` DTO discipline: value type, explicit
/// public init, `Codable + Sendable + Equatable`. Encoded as a single compact
/// JSON object terminated by `"\n"`; `JSONEncoder` escapes any newline inside a
/// value (`\n`), so each event is guaranteed to occupy exactly one physical line.
public struct DiagnosticEvent: Codable, Sendable, Equatable {
    public let at: Date
    public let seq: UInt64
    public let process: DiagProcess
    public let category: DiagCategory
    public let name: String
    public let payload: [String: DiagValue]

    public init(at: Date, seq: UInt64, process: DiagProcess, category: DiagCategory, name: String, payload: [String: DiagValue]) {
        self.at = at
        self.seq = seq
        self.process = process
        self.category = category
        self.name = name
        self.payload = payload
    }

    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        return e
    }

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// One compact JSON object + `"\n"`. `JSONEncoder` never emits a raw newline
    /// inside a value (they are escaped as `\n`), so each event is exactly one line.
    public static func encodeJSONLine(_ event: DiagnosticEvent) throws -> String {
        let data = try makeEncoder().encode(event)
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    public static func decodeJSONLine(_ line: String) throws -> DiagnosticEvent {
        try makeDecoder().decode(DiagnosticEvent.self, from: Data(line.utf8))
    }

    public static func decodeJSONLines(_ blob: String) throws -> [DiagnosticEvent] {
        try blob.split(separator: "\n", omittingEmptySubsequences: true)
            .map { try decodeJSONLine(String($0)) }
    }
}
