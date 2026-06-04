import Foundation

/// Production implementation of `LinkPreviewFetching`. Uses a single
/// `URLSession` configured per design Section 3 ("10s timeout, 5 MB
/// cap, HTML-only parsing"). Test code constructs a session with
/// `StubURLProtocol` registered.
///
/// SSRF hardening (linkpreview-1/2/3): every fetch is gated by
/// `URLPreviewPolicy` before the request is issued, the policy is
/// re-applied on each redirect via `RedirectGuard` (which also caps the
/// hop count), and the response body is read with `bytes(for:delegate:)`
/// so an oversize payload is aborted mid-stream rather than fully
/// buffered.
public final class URLSessionLinkPreviewFetcher: LinkPreviewFetching {
    private let session: URLSession

    public init(session: URLSession = URLSessionLinkPreviewFetcher.makeDefaultSession()) {
        self.session = session
    }

    public static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = LinkPreviewLimits.timeout
        config.timeoutIntervalForResource = LinkPreviewLimits.timeout
        config.httpMaximumConnectionsPerHost = 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }

    public func fetchHTML(url: URL) async -> Data? {
        guard URLPreviewPolicy.isAllowed(url) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: LinkPreviewLimits.timeout)
        req.httpMethod = "GET"
        req.setValue("Mozilla/5.0 (Lillist link unfurl)", forHTTPHeaderField: "User-Agent")
        guard let (data, http) = await capRead(req) else { return nil }
        guard (200..<300).contains(http.statusCode) else { return nil }
        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        guard contentType.contains("text/html") || contentType.contains("application/xhtml") || contentType.isEmpty else {
            return nil
        }
        return data
    }

    public func fetchImage(url: URL?) async -> Data? {
        guard let url, URLPreviewPolicy.isAllowed(url) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: LinkPreviewLimits.timeout)
        req.httpMethod = "GET"
        guard let (data, http) = await capRead(req) else { return nil }
        guard (200..<300).contains(http.statusCode) else { return nil }
        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        guard contentType.hasPrefix("image/") else { return nil }
        return data
    }

    /// Stream the response body, attaching the redirect-guarding delegate,
    /// and abort the moment the running byte total exceeds the cap. Returns
    /// `nil` on transport error, redirect refusal, or oversize body.
    private func capRead(_ request: URLRequest) async -> (Data, HTTPURLResponse)? {
        let guardDelegate = RedirectGuard()
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: guardDelegate)
            guard let http = response as? HTTPURLResponse else { return nil }

            // Cheap pre-check: if the server advertises an oversize body,
            // reject without reading a single byte.
            if let lengthString = http.value(forHTTPHeaderField: "Content-Length"),
               let length = Int(lengthString), length > LinkPreviewLimits.bodyCapBytes {
                return nil
            }

            var data = Data()
            data.reserveCapacity(min(LinkPreviewLimits.bodyCapBytes, 64 * 1024))
            for try await byte in bytes {
                data.append(byte)
                if data.count > LinkPreviewLimits.bodyCapBytes { return nil }
            }
            return (data, http)
        } catch {
            return nil
        }
    }
}

/// Per-task `URLSession` delegate that re-applies `URLPreviewPolicy` to
/// every redirect target and caps the redirect-chain length. Attached via
/// `bytes(for:delegate:)` so it never becomes a session-wide retained
/// delegate (no retain cycle). Immutable except for the hop counter, which
/// `URLSession` only mutates serially from its delegate queue.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private var hopCount = 0

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        hopCount += 1
        guard hopCount <= LinkPreviewLimits.redirectHopLimit else { return nil }
        guard let url = request.url, URLPreviewPolicy.isAllowed(url) else { return nil }
        return request
    }
}
