import Foundation

/// A deterministic `FilterQueryTranslator` double. Every automated test in
/// this repo exercises the translator protocol, `TasksView`/`MacTasksView`
/// wiring, and the CLI `AskHandler` through this type — the on-device and
/// Private Cloud Compute tiers are non-deterministic and availability-gated
/// (no model on a hosted CI runner, unreliable on a simulator), so they are
/// verified manually on a capable device instead. Public (not test-only)
/// because downstream modules (LillistUI, the iOS/macOS apps) need a real
/// translator to inject in their own tests without `@testable import`.
///
/// Never selected by `FilterTranslatorFactory` in production.
public struct MockQueryTranslator: FilterQueryTranslator, Sendable {
    public var kind: TranslatorKind
    private let result: Result<IntermediateFilter, TranslationFailure>

    public init(kind: TranslatorKind = .mock, returning filter: IntermediateFilter) {
        self.kind = kind
        self.result = .success(filter)
    }

    public init(kind: TranslatorKind = .mock, throwing failure: TranslationFailure) {
        self.kind = kind
        self.result = .failure(failure)
    }

    public func generateIntermediateFilter(
        for query: String,
        context: TranslationContext
    ) async throws -> IntermediateFilter {
        try result.get()
    }
}
