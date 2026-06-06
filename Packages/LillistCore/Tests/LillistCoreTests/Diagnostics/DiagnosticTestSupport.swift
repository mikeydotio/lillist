import Foundation
@testable import LillistCore

/// Collects events the code under test emits, without touching disk. Mirrors the
/// async `DiagnosticSink` contract that `DiagnosticLog` fulfills.
actor SpyDiagnosticSink: DiagnosticSink {
    private(set) var events: [DiagnosticEvent] = []
    func log(_ event: DiagnosticEvent) { events.append(event) }
}

extension DiagValue {
    /// Test convenience: `changedProps` is stored as a sorted, comma-joined
    /// string, so this checks membership without exposing a list-valued
    /// `DiagValue` variant in production (YAGNI).
    func containsName(_ name: String) -> Bool {
        if case .string(let s) = self {
            return s.split(separator: ",").map(String.init).contains(name)
        }
        return false
    }
}
