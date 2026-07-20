import Foundation

/// Which tier produced a `TranslatedQuery` — surfaced to the UI/CLI so
/// results can be labeled (and so tests can assert which path ran without
/// depending on live model availability).
public enum TranslatorKind: String, Sendable, Equatable {
    /// The deterministic test/preview double (`MockQueryTranslator`).
    case mock
    /// Apple's on-device `SystemLanguageModel` (iOS/macOS 26+).
    case onDevice
    /// Apple's `PrivateCloudComputeLanguageModel` (iOS/macOS 27+).
    case privateCloudCompute
}

/// The end-to-end result of translating a natural-language query: a
/// ready-to-execute `PredicateGroup`, a human-readable summary for the UI
/// preview strip, and anything the translator/mapper couldn't place.
public struct TranslatedQuery: Sendable, Equatable {
    public var group: PredicateGroup
    public var explanation: String?
    public var unmappedTerms: [String]
    public var source: TranslatorKind

    public init(
        group: PredicateGroup,
        explanation: String?,
        unmappedTerms: [String],
        source: TranslatorKind
    ) {
        self.group = group
        self.explanation = explanation
        self.unmappedTerms = unmappedTerms
        self.source = source
    }

    /// True when the translation produced no usable predicates at all — the
    /// UI's cue to say "I couldn't understand that" rather than silently
    /// running an unconstrained filter.
    public var isEmpty: Bool {
        group.predicates.isEmpty
    }
}
