import Foundation

extension CLIBridge {
    public enum LinkHandler {
        @discardableResult
        public static func run(
            token: String,
            urlString: String,
            persistence: PersistenceController,
            fetcher: LinkPreviewFetching? = nil
        ) async throws -> UUID {
            guard let url = URL(string: urlString), url.scheme != nil else {
                throw LillistError.validationFailed([.init(field: "url", message: "invalid URL '\(urlString)'")])
            }
            let r = try await Resolver.resolve(
                token: token, scope: .anywhereIncludingClosed,
                destructiveness: .readOnly, persistence: persistence
            )

            let attachments = AttachmentStore(persistence: persistence)
            let attachmentID = try await attachments.addLinkPreview(
                taskID: r.id,
                url: url,
                title: nil,
                description: nil,
                thumbnailData: nil,
                faviconData: nil
            )

            // Best-effort unfurl. Failure leaves the row with just the URL —
            // matches design Section 3's "couldn't fetch" affordance.
            let f = fetcher ?? URLSessionLinkPreviewFetcher()
            let unfurler = LinkPreviewUnfurler(attachments: attachments, fetcher: f)
            _ = await unfurler.unfurl(attachmentID: attachmentID, url: url)

            return attachmentID
        }
    }
}
