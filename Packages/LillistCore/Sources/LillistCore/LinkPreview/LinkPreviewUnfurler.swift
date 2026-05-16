import Foundation

/// Coordinates the unfurl flow:
///   1. Fetch the URL's HTML body via `fetcher`.
///   2. Parse OG / Twitter / `<title>` tags via `OpenGraphParser`.
///   3. Optionally fetch the OG image as raw bytes.
///   4. Write the merged metadata + thumbnail back through
///      `AttachmentStore.updateLinkPreview`.
///
/// All errors fold into `Outcome.failure(reason:)` — callers decide
/// whether to surface a "couldn't fetch" affordance with retry. Design
/// Section 3: "On success, update row with unfurled metadata. On
/// failure, leave raw URL with 'couldn't fetch' affordance and retry
/// button."
public actor LinkPreviewUnfurler {
    public enum FailureReason: Sendable, Equatable {
        case notFound
        case timeout
        case oversize
        case unsupportedContentType
        case parseError
        case storeError
    }

    public enum Outcome: Sendable, Equatable {
        case success
        case failure(FailureReason)
    }

    private let attachments: AttachmentStore
    private let fetcher: LinkPreviewFetching

    public init(attachments: AttachmentStore, fetcher: LinkPreviewFetching) {
        self.attachments = attachments
        self.fetcher = fetcher
    }

    /// Unfurl `url` and write the result to the attachment row identified
    /// by `attachmentID`. The attachment is assumed to already exist
    /// (typically created by `LinkHandler.run`).
    public func unfurl(attachmentID: UUID, url: URL) async -> Outcome {
        guard let htmlData = await fetcher.fetchHTML(url: url) else {
            return .failure(.notFound)
        }
        guard let html = String(data: htmlData, encoding: .utf8) else {
            return .failure(.parseError)
        }
        let metadata = OpenGraphParser.parse(html: html)
        let thumbnailData = await fetcher.fetchImage(url: metadata.imageURL)

        do {
            try await attachments.updateLinkPreview(
                id: attachmentID,
                metadata: metadata,
                thumbnailData: thumbnailData
            )
            return .success
        } catch {
            return .failure(.storeError)
        }
    }
}
