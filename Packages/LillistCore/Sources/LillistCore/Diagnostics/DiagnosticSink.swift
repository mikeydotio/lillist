import Foundation

/// The minimal contract a diagnostic event consumer fulfills. `DiagnosticLog`
/// (the on-disk writer) is the production conformer; tests substitute an
/// in-memory spy. Letting the observer and stores depend on this protocol —
/// rather than the concrete actor — keeps them testable without touching disk.
public protocol DiagnosticSink: Sendable {
    func log(_ event: DiagnosticEvent) async
}

extension DiagnosticLog: DiagnosticSink {}
