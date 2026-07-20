import Foundation

/// A tag's id and display name, as known to a `TranslationContext`. Lets a
/// `FilterQueryTranslator` resolve a natural-language tag mention (e.g.
/// "tagged Home") to the id `IntermediateFilterMapper` needs to build a real
/// `Value.uuidSet` — translators never see raw tag ids otherwise.
public struct TagRef: Sendable, Equatable {
    public var id: UUID
    public var name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}
