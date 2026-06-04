import Foundation

/// Test helper that intercepts `URLSession` requests and returns canned
/// responses. Used by the LinkPreview unfurl tests so they never hit the
/// network.
///
/// Each call to ``session(responder:)`` registers its closure under a
/// fresh token and configures the session to inject that token on every
/// outgoing request via the `X-StubURLProtocol-Token` header. The
/// protocol then looks the responder up by token. This keeps multiple
/// concurrent tests isolated from one another — Swift Testing runs
/// tests in parallel by default, and a previous design that used a
/// single shared static responder produced flaky failures when tests
/// raced.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response {
        let statusCode: Int
        let headers: [String: String]
        let body: Data

        init(statusCode: Int, headers: [String: String], body: Data) {
            self.statusCode = statusCode
            self.headers = headers
            self.body = body
        }

        /// Convenience for a 3xx redirect to `location`. The `Location`
        /// header is what `URLSession` follows, invoking the task
        /// delegate's `willPerformHTTPRedirection`.
        static func redirect(to location: String, statusCode: Int = 302) -> Response {
            Response(statusCode: statusCode, headers: ["Location": location], body: Data())
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var responders: [String: (URL) -> Response?] = [:]

    static let tokenHeader = "X-StubURLProtocol-Token"

    private static func register(_ responder: @escaping (URL) -> Response?) -> String {
        let token = UUID().uuidString
        lock.lock(); defer { lock.unlock() }
        responders[token] = responder
        return token
    }

    private static func responder(forToken token: String) -> ((URL) -> Response?)? {
        lock.lock(); defer { lock.unlock() }
        return responders[token]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let token = request.value(forHTTPHeaderField: Self.tokenHeader) ?? ""
        guard let url = request.url,
              let respond = Self.responder(forToken: token),
              let response = respond(url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        )!

        // A 3xx with a Location header is delivered as a redirect so the
        // session's task delegate gets willPerformHTTPRedirection. Without
        // a delegate-supplied new request the session would follow it
        // itself; our fetcher attaches a delegate to gate the hop.
        if (300..<400).contains(response.statusCode),
           let location = response.headers["Location"],
           let nextURL = URL(string: location, relativeTo: url) {
            var redirected = URLRequest(url: nextURL)
            redirected.httpMethod = request.httpMethod
            // Carry the per-session token so the follow-up request is
            // still routed to this test's responder.
            if let header = request.value(forHTTPHeaderField: Self.tokenHeader) {
                redirected.setValue(header, forHTTPHeaderField: Self.tokenHeader)
            }
            client?.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: httpResponse)
            return
        }

        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// Construct a `URLSession` whose requests will be served by `responder`.
    /// The responder is keyed by a per-session token so that multiple
    /// concurrent tests can use the helper without interfering with each
    /// other.
    static func session(responder: @escaping (URL) -> Response?) -> URLSession {
        let token = register(responder)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.httpAdditionalHeaders = [tokenHeader: token]
        return URLSession(configuration: config)
    }
}
