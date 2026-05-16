import Foundation

/// Pure value type representing the unfurled metadata of a URL.
/// Populated by `OpenGraphParser` from HTML body, then handed to
/// `AttachmentStore.updateLinkPreview` for persistence.
public struct LinkPreviewMetadata: Sendable, Equatable {
    public var title: String?
    public var description: String?
    public var imageURL: URL?
    public var siteName: String?

    public init(
        title: String? = nil,
        description: String? = nil,
        imageURL: URL? = nil,
        siteName: String? = nil
    ) {
        self.title = title
        self.description = description
        self.imageURL = imageURL
        self.siteName = siteName
    }

    public static let empty = LinkPreviewMetadata()
}
