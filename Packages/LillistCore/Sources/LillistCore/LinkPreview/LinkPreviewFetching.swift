import Foundation

/// Abstracts the network side of the unfurl pipeline so tests can
/// substitute a stub. Implementations fetch HTML body bytes (and
/// optionally a thumbnail image) for a given URL.
public protocol LinkPreviewFetching: Sendable {
    /// Fetch and return the body bytes (HTML) for `url`. Implementations
    /// enforce the design Section 3 limits: 10s timeout, 5 MB cap.
    /// Returns `nil` on non-2xx, non-HTML, or oversize responses.
    func fetchHTML(url: URL) async -> Data?

    /// Fetch image bytes if `url` is provided and the response is an
    /// image. Returns `nil` on any failure. Same 10s / 5 MB limits.
    func fetchImage(url: URL?) async -> Data?
}

public enum LinkPreviewLimits {
    public static let timeout: TimeInterval = 10
    public static let bodyCapBytes: Int = 5 * 1024 * 1024

    /// Maximum number of HTTP redirects the fetcher will follow before
    /// giving up. Bounds redirect-chain abuse (linkpreview-2) while still
    /// permitting the common one- or two-hop canonical-URL redirects.
    public static let redirectHopLimit: Int = 5
}
