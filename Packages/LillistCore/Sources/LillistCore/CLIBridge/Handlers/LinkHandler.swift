import Foundation

extension CLIBridge {
    public enum LinkHandler {
        @discardableResult
        public static func run(
            token: String,
            urlString: String,
            persistence: PersistenceController
        ) async throws -> UUID {
            guard let url = URL(string: urlString), url.scheme != nil else {
                throw LillistError.validationFailed([.init(field: "url", message: "invalid URL '\(urlString)'")])
            }
            let r = try await Resolver.resolve(
                token: token, scope: .anywhereIncludingClosed,
                destructiveness: .readOnly, persistence: persistence
            )
            // Plan 2's link-preview unfurl pipeline takes over once available.
            // For now, attach a placeholder linkPreview with just the URL.
            let store = AttachmentStore(persistence: persistence)
            return try await store.addLinkPreview(
                taskID: r.id,
                url: url,
                title: nil,
                description: nil,
                thumbnailData: nil,
                faviconData: nil
            )
        }
    }
}
