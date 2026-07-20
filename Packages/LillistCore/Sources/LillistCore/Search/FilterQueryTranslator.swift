import Foundation

/// Why a `FilterQueryTranslator` could not produce a `TranslatedQuery` at
/// all (as opposed to producing one with some clauses dropped, which is
/// `MappingResult.dropped` — a normal, expected outcome, not a failure).
public enum TranslationFailure: Error, Sendable, Equatable {
    /// No capable backend was available (e.g. no on-device model and no
    /// Private Cloud Compute tier — see `FilterTranslatorFactory`).
    case unsupported
    /// The query was empty after trimming whitespace.
    case emptyQuery
    /// An opaque, translator-specific failure (network error, quota limit,
    /// service unavailable, …); the message is for logging/diagnostics.
    case underlying(String)
}

extension TranslationFailure: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupported:
            return "Smart search requires Apple Intelligence (on-device or Private Cloud Compute), which isn't available on this device."
        case .emptyQuery:
            return "Enter a search query."
        case .underlying(let message):
            return "Smart search failed: \(message)"
        }
    }
}

/// Translates a natural-language search query into an executable
/// `PredicateGroup`. Conforming types implement only
/// `generateIntermediateFilter(for:context:)` — the *only* job of a
/// translator is proposing a flat `IntermediateFilter`; the default
/// `translate(_:context:)` implementation always routes that proposal
/// through `IntermediateFilterMapper`, so no conforming type can bypass its
/// validation and construct an unsafe `PredicateGroup` directly.
public protocol FilterQueryTranslator: Sendable {
    /// Which tier this translator represents (mock, on-device, Private
    /// Cloud Compute, …) — carried onto every `TranslatedQuery` it produces.
    var kind: TranslatorKind { get }

    /// Propose a flat interpretation of `query`. Implementations should
    /// return their best-effort guess rather than throwing for a partially
    /// understood query — `IntermediateFilterMapper` already tolerates
    /// per-clause failure. Throw only when translation could not be
    /// attempted at all (backend unavailable, query rejected upstream, …).
    func generateIntermediateFilter(
        for query: String,
        context: TranslationContext
    ) async throws -> IntermediateFilter
}

extension FilterQueryTranslator {
    /// Translate `query` into a validated, ready-to-execute
    /// `TranslatedQuery`. Trims the query, rejects an empty one, calls
    /// `generateIntermediateFilter`, then maps the result through
    /// `IntermediateFilterMapper` and renders an `explanation` via
    /// `PredicateGroupExplainer` — the full pipeline every conforming type
    /// gets for free.
    public func translate(_ query: String, context: TranslationContext) async throws -> TranslatedQuery {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationFailure.emptyQuery }

        let intermediate = try await generateIntermediateFilter(for: trimmed, context: context)
        let mapped = IntermediateFilterMapper.map(intermediate, context: context)

        var unmappedTerms = mapped.unresolvedTagNames.map { "tag “\($0)”" }
        unmappedTerms.append(contentsOf: mapped.dropped.map(Self.describe(_:)))

        return TranslatedQuery(
            group: mapped.group,
            explanation: PredicateGroupExplainer.explain(mapped.group),
            unmappedTerms: unmappedTerms,
            source: kind
        )
    }

    private static func describe(_ dropped: DroppedClause) -> String {
        "\(dropped.field.rawValue) \(dropped.op.rawValue)"
    }
}
