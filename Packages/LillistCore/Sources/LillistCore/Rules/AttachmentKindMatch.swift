import Foundation

/// Companion value for `Field.hasAttachments` with the optional `ofKind` qualifier.
///
/// When `kind` is nil, the leaf matches any attachment kind. When set, only
/// attachments of that kind count.
public struct AttachmentKindMatch: Codable, Sendable, Equatable {
    public var present: Bool
    public var kind: AttachmentKind?

    public init(present: Bool, kind: AttachmentKind? = nil) {
        self.present = present
        self.kind = kind
    }
}
