import Foundation

/// Production implementation of `LinkPreviewFetching`. Uses a single
/// `URLSession` configured per design Section 3 ("10s timeout, 5 MB
/// cap, HTML-only parsing"). Test code constructs a session with
/// `StubURLProtocol` registered.
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
        var req = URLRequest(url: url, timeoutInterval: LinkPreviewLimits.timeout)
        req.httpMethod = "GET"
        req.setValue("Mozilla/5.0 (Lillist link unfurl)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { return nil }
            guard (200..<300).contains(http.statusCode) else { return nil }
            let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            guard contentType.contains("text/html") || contentType.contains("application/xhtml") || contentType.isEmpty else {
                return nil
            }
            guard data.count <= LinkPreviewLimits.bodyCapBytes else { return nil }
            return data
        } catch {
            return nil
        }
    }

    public func fetchImage(url: URL?) async -> Data? {
        guard let url else { return nil }
        var req = URLRequest(url: url, timeoutInterval: LinkPreviewLimits.timeout)
        req.httpMethod = "GET"
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { return nil }
            guard (200..<300).contains(http.statusCode) else { return nil }
            let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            guard contentType.hasPrefix("image/") else { return nil }
            guard data.count <= LinkPreviewLimits.bodyCapBytes else { return nil }
            return data
        } catch {
            return nil
        }
    }
}
