# Link-Preview SSRF Guards Implementation Plan

> **📍 STATUS — ◧ PARTIALLY MERGED to `main` (2026-06-04) — Wave 2.** Tasks 1–5
> landed (commits `356ed97`..`4bb6154`); 738 LillistCore tests green, warning-free.
> Closed linkpreview-1, linkpreview-2, and the policy/fetcher/CLI halves of
> linkpreview-3 (`URLPreviewPolicy` + fetcher pre-check/streaming-cap/`RedirectGuard`
> + `LinkHandler` ingest gate). **Task 6 (iOS Share Extension `ShareRootView` gate)
> is DEFERRED to Wave 6** per index chain #3 (that file is restructured first by
> `app-layer-test-rehab`/`extension-persistence-unification`) — tracked as index
> residual #10. Task 5's zero-attachment assertion uses `attachments(forTask:).isEmpty`
> (no `count(forTask:)` exists). Do NOT re-run Tasks 1–5; execute only Task 6 in Wave 6.
>
> Part of the **Foundation Hardening** program. **Single source of truth for progress, wave order, and cross-plan coordination:** [`2026-05-29-foundation-hardening-index.md`](2026-05-29-foundation-hardening-index.md). New to this project? Read the index first, then the review ([`docs/reviews/2026-05-28-foundation-review.md`](../../reviews/2026-05-28-foundation-review.md)) for *why* this work exists, then `CLAUDE.md` for conventions + build/test commands. Execute task-by-task with `superpowers:subagent-driven-development`.
>
> ⚠️ **Wave 1 (`store-swap-safety`) is merged to `main`.** It changed several shared files (`MigrationCoordinator`, `PersistenceHost`, `QuarantineManager`, `MigrationJournal`, both `AppEnvironment`s, `PersistenceController`). **Re-Read every file before editing and anchor by code structure — the line numbers in this plan may have drifted.**

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the link-preview pipeline from issuing requests to attacker-chosen private/loopback/non-HTTP endpoints by adding a shared `URLPreviewPolicy` enforced at the ingest boundary, on every fetch, across redirects (with a hop cap), and a true streaming 5 MB byte cap with early abort.

**Architecture:** Introduce a pure value-type `URLPreviewPolicy` in `LillistCore` that classifies a `URL` as allowed/blocked using scheme allow-listing (http/https only) and host blocking (literal `localhost`, any `*.local`, and numeric IP literals in loopback/link-local/RFC1918/IPv6-loopback/unique-local ranges). `URLSessionLinkPreviewFetcher` validates the initial URL with the policy before requesting, switches to `URLSession.bytes(for:delegate:)` so it can abort the moment the running byte total exceeds the cap, and attaches a small `Sendable` `URLSessionTaskDelegate` that re-applies the policy on `willPerformHTTPRedirection` and caps redirect hops. The same policy gates ingest in `CLIBridge.LinkHandler.run` and the iOS Share Extension so blocked URLs never even create an attachment row.

**Tech Stack:** Swift 6.2, Foundation (`URLSession.bytes(for:delegate:)`, `URLSessionTaskDelegate`), Swift Testing (`import Testing`, `@Test`/`#expect`), `StubURLProtocol` test helper.

**Source findings:** linkpreview-1, linkpreview-2, linkpreview-3 (Roadmap #6; also closes part of test-1's StubURLProtocol negative-test gap for this pipeline).

---

## File Structure

**Create:**
- `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLPreviewPolicy.swift` — pure value-type SSRF policy: scheme allow-list + host/IP-literal block-list + a redirect-hop limit constant. One responsibility: decide whether a single `URL` may be fetched. No I/O.
- `Packages/LillistCore/Tests/LillistCoreTests/LinkPreview/URLPreviewPolicyTests.swift` — unit tests for the pure policy classification (schemes, hosts, IP literals).
- `Packages/LillistCore/Tests/LillistCoreTests/LinkPreview/URLSessionLinkPreviewFetcherTests.swift` — `StubURLProtocol`-backed negative tests: blocked scheme, private host, 302-to-blocked-host, oversize body, plus a redirect-hop-cap test and a happy-path streaming test.

**Modify:**
- `Packages/LillistCore/Tests/LillistCoreTests/Helpers/StubURLProtocol.swift` — add optional redirect (3xx `Location`) emission so the fetcher's redirect delegate can be exercised. Backward compatible: existing `Response(statusCode:headers:body:)` callers unchanged.
- `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLSessionLinkPreviewFetcher.swift` (currently lines 23–57: `fetchHTML`/`fetchImage`) — pre-validate with `URLPreviewPolicy`, fetch via `bytes(for:delegate:)` with early-abort streaming cap, attach the redirect-guarding delegate.
- `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewFetching.swift` (currently lines 17–20: `LinkPreviewLimits`) — add `redirectHopLimit` constant alongside `timeout`/`bodyCapBytes` (single source of truth).
- `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/LinkHandler.swift` (currently lines 12–14: URL parse/validate) — reject policy-blocked URLs at ingest before any attachment row is created.
- `Extensions/ShareExtension-iOS/ShareRootView.swift` (currently lines 82–91: the `addLinkPreview` call) — drop the attached URL (and surface a message) when `URLPreviewPolicy` blocks it, so the extension never persists an SSRF-bait URL.

---

## Task 1: Add the redirect-hop-limit constant to `LinkPreviewLimits`

**Files:** Modify `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewFetching.swift` (lines 17–20).

This is a one-constant change consumed by Tasks 2–3; verified by the package building.

- [ ] **Step 1: Add the constant.** Replace the `LinkPreviewLimits` enum (current lines 17–20) with:

```swift
public enum LinkPreviewLimits {
    public static let timeout: TimeInterval = 10
    public static let bodyCapBytes: Int = 5 * 1024 * 1024

    /// Maximum number of HTTP redirects the fetcher will follow before
    /// giving up. Bounds redirect-chain abuse (linkpreview-2) while still
    /// permitting the common one- or two-hop canonical-URL redirects.
    public static let redirectHopLimit: Int = 5
}
```

- [ ] **Step 2: Verify it compiles.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift build --package-path Packages/LillistCore
```

Expected: `Build complete!` with no warnings (warnings are errors on this target).

- [ ] **Step 3: Commit.**

```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewFetching.swift
git commit -m "feat(linkpreview): add redirectHopLimit to LinkPreviewLimits

Single source of truth for the SSRF redirect-chain cap consumed by the
fetcher's redirect-guarding delegate. Refs linkpreview-2."
```

---

## Task 2: Create the `URLPreviewPolicy` value type (TDD)

**Files:**
- Create `Packages/LillistCore/Tests/LillistCoreTests/LinkPreview/URLPreviewPolicyTests.swift`
- Create `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLPreviewPolicy.swift`

The policy is pure (no I/O), so it is unit-testable on the host with `swift test`. Tests use Swift Testing to match `LinkPreviewUnfurlerTests.swift` in the same directory.

- [ ] **Step 1: Write the failing test.** Create `Packages/LillistCore/Tests/LillistCoreTests/LinkPreview/URLPreviewPolicyTests.swift` with the complete content:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("URLPreviewPolicy")
struct URLPreviewPolicyTests {
    // MARK: Allowed

    @Test("Public https URL is allowed")
    func publicHTTPSAllowed() {
        #expect(URLPreviewPolicy.isAllowed(URL(string: "https://example.com/page")!))
    }

    @Test("Public http URL is allowed")
    func publicHTTPAllowed() {
        #expect(URLPreviewPolicy.isAllowed(URL(string: "http://example.com/page")!))
    }

    @Test("Public routable IPv4 literal is allowed")
    func publicIPv4Allowed() {
        #expect(URLPreviewPolicy.isAllowed(URL(string: "https://93.184.216.34/")!))
    }

    // MARK: Blocked schemes (linkpreview-1)

    @Test("file scheme is blocked", arguments: [
        "file:///etc/passwd",
        "ftp://example.com/x",
        "data:text/html,<h1>hi</h1>",
        "javascript:alert(1)",
        "about:blank"
    ])
    func nonHTTPSchemesBlocked(_ raw: String) {
        let url = URL(string: raw)!
        #expect(!URLPreviewPolicy.isAllowed(url))
    }

    @Test("URL with no scheme is blocked")
    func schemelessBlocked() {
        // A relative reference parses with a nil scheme.
        let url = URL(string: "//example.com/path", relativeTo: nil)!
        #expect(!URLPreviewPolicy.isAllowed(url))
    }

    // MARK: Blocked hosts (linkpreview-3)

    @Test("localhost and *.local hostnames are blocked", arguments: [
        "http://localhost/",
        "http://LOCALHOST:8080/admin",
        "http://printer.local/",
        "https://Foo.LOCAL/path"
    ])
    func localHostnamesBlocked(_ raw: String) {
        let url = URL(string: raw)!
        #expect(!URLPreviewPolicy.isAllowed(url))
    }

    @Test("Loopback IPv4 literals are blocked", arguments: [
        "http://127.0.0.1/",
        "http://127.1.2.3/",
        "http://0.0.0.0/"
    ])
    func loopbackIPv4Blocked(_ raw: String) {
        let url = URL(string: raw)!
        #expect(!URLPreviewPolicy.isAllowed(url))
    }

    @Test("Link-local and RFC1918 IPv4 literals are blocked", arguments: [
        "http://169.254.169.254/latest/meta-data/",  // cloud metadata
        "http://10.0.0.5/",
        "http://172.16.0.1/",
        "http://172.31.255.254/",
        "http://192.168.1.1/"
    ])
    func privateIPv4Blocked(_ raw: String) {
        let url = URL(string: raw)!
        #expect(!URLPreviewPolicy.isAllowed(url))
    }

    @Test("Public IPv4 just outside private ranges is allowed", arguments: [
        "http://172.15.0.1/",   // below 172.16
        "http://172.32.0.1/",   // above 172.31
        "http://11.0.0.1/",     // not 10.x
        "http://192.169.0.1/"   // not 192.168.x
    ])
    func nearMissPublicIPv4Allowed(_ raw: String) {
        let url = URL(string: raw)!
        #expect(URLPreviewPolicy.isAllowed(url))
    }

    @Test("IPv6 loopback and unique-local/link-local literals are blocked", arguments: [
        "http://[::1]/",
        "http://[fe80::1]/",
        "http://[fc00::1]/",
        "http://[fd12:3456::1]/"
    ])
    func privateIPv6Blocked(_ raw: String) {
        let url = URL(string: raw)!
        #expect(!URLPreviewPolicy.isAllowed(url))
    }

    @Test("Public IPv6 literal is allowed")
    func publicIPv6Allowed() {
        #expect(URLPreviewPolicy.isAllowed(URL(string: "http://[2606:2800:220:1:248:1893:25c8:1946]/")!))
    }
}
```

- [ ] **Step 2: Run the test, expect failure.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter URLPreviewPolicy
```

Expected: compile failure — `error: cannot find 'URLPreviewPolicy' in scope` (the type does not exist yet).

- [ ] **Step 3: Implement the minimal change.** Create `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLPreviewPolicy.swift` with the complete content:

```swift
import Foundation

/// Stateless SSRF guard for the link-preview pipeline. Decides whether a
/// single `URL` is safe to fetch. Pure value math — no I/O — so it can be
/// applied at the ingest boundary (`CLIBridge.LinkHandler`, the iOS Share
/// Extension), on the initial request, and re-applied on every redirect
/// hop without crossing any actor or network boundary.
///
/// Policy (design Section 3, security hardening — linkpreview-1/3):
///   * Scheme allow-list: `http` and `https` only.
///   * Host block-list: literal `localhost`, any `*.local` mDNS name, and
///     numeric IP literals in loopback / link-local / RFC1918 / IPv6
///     loopback / IPv6 unique-local / IPv6 link-local ranges.
///
/// DNS rebinding (a public name resolving to a private address at connect
/// time) is out of scope here; it is partially mitigated by re-validating
/// the literal host on every redirect, and fully addressing it would
/// require a custom resolver. We block the literal-IP and well-known-name
/// vectors, which are the ones reachable from pasted/shared URLs.
public enum URLPreviewPolicy {
    /// Allowed URL schemes (lowercased).
    public static let allowedSchemes: Set<String> = ["http", "https"]

    /// Returns `true` when `url` may be fetched under the policy.
    public static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), allowedSchemes.contains(scheme) else {
            return false
        }
        guard let host = url.host(percentEncoded: false), !host.isEmpty else {
            return false
        }
        return !isBlockedHost(host)
    }

    /// Returns `true` when `host` (a hostname or bracket-stripped IP
    /// literal) is on the block-list.
    static func isBlockedHost(_ host: String) -> Bool {
        let normalized = host.lowercased()

        if normalized == "localhost" { return true }
        if normalized.hasSuffix(".local") || normalized == "local" { return true }

        // `URL.host(percentEncoded:)` already strips the surrounding
        // brackets from an IPv6 literal, but be defensive.
        let bare = normalized.hasPrefix("[") && normalized.hasSuffix("]")
            ? String(normalized.dropFirst().dropLast())
            : normalized

        if let v4 = IPv4Address(bare) { return v4.isPrivateOrLoopbackOrLinkLocal }
        if let v6 = IPv6Octets(bare) { return v6.isPrivateOrLoopbackOrLinkLocal }

        return false
    }
}

/// Minimal dotted-quad IPv4 parser. Foundation has no public host-literal
/// classifier, so we parse the four octets ourselves and range-check.
struct IPv4Address {
    let octets: (UInt8, UInt8, UInt8, UInt8)

    init?(_ string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var values: [UInt8] = []
        for part in parts {
            // Reject leading/trailing junk and non-decimal forms so we
            // don't misclassify hostnames that merely contain digits.
            guard !part.isEmpty, part.allSatisfy({ $0.isNumber }),
                  let n = UInt16(part), n <= 255 else { return nil }
            values.append(UInt8(n))
        }
        octets = (values[0], values[1], values[2], values[3])
    }

    /// Loopback `127/8` + `0.0.0.0` + link-local `169.254/16`
    /// + RFC1918 `10/8`, `172.16/12`, `192.168/16`.
    var isPrivateOrLoopbackOrLinkLocal: Bool {
        let (a, b, _, _) = octets
        if a == 127 { return true }                          // loopback
        if a == 0 { return true }                            // 0.0.0.0/8 "this host"
        if a == 169 && b == 254 { return true }              // link-local
        if a == 10 { return true }                           // RFC1918 /8
        if a == 172 && (16...31).contains(b) { return true } // RFC1918 /12
        if a == 192 && b == 168 { return true }              // RFC1918 /16
        return false
    }
}

/// Minimal IPv6 literal classifier. We only need to recognize the blocked
/// ranges by their high-order bits, so we parse the first hextet group.
struct IPv6Octets {
    /// Lowercased, bracket-free IPv6 text retained for prefix checks.
    let text: String

    init?(_ string: String) {
        // Must contain a colon and only valid IPv6 characters to qualify.
        guard string.contains(":") else { return nil }
        let allowed = CharacterSet(charactersIn: "0123456789abcdef:.")
        guard string.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        text = string
    }

    /// `::1` loopback, `::` unspecified, `fc00::/7` unique-local,
    /// `fe80::/10` link-local. IPv4-mapped/embedded forms (e.g.
    /// `::ffff:127.0.0.1`) are handled by extracting the trailing IPv4.
    var isPrivateOrLoopbackOrLinkLocal: Bool {
        if text == "::1" || text == "::" { return true }

        // IPv4-mapped / IPv4-compatible: classify the embedded IPv4.
        if let lastColon = text.lastIndex(of: ":") {
            let tail = String(text[text.index(after: lastColon)...])
            if tail.contains("."), let v4 = IPv4Address(tail), v4.isPrivateOrLoopbackOrLinkLocal {
                return true
            }
        }

        // First hextet group determines unique-local / link-local.
        let firstGroup = text.split(separator: ":", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        guard let value = UInt16(firstGroup, radix: 16) else { return false }
        if (value & 0xFE00) == 0xFC00 { return true } // fc00::/7 unique-local
        if (value & 0xFFC0) == 0xFE80 { return true } // fe80::/10 link-local
        return false
    }
}
```

- [ ] **Step 4: Run the test, expect pass.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter URLPreviewPolicy
```

Expected: all `URLPreviewPolicy` tests pass (e.g. `Test Suite 'URLPreviewPolicy' passed`), zero failures.

- [ ] **Step 5: Commit.**

```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistCore/Sources/LillistCore/LinkPreview/URLPreviewPolicy.swift \
        Packages/LillistCore/Tests/LillistCoreTests/LinkPreview/URLPreviewPolicyTests.swift
git commit -m "feat(linkpreview): add URLPreviewPolicy SSRF guard

Pure value-type policy: http/https-only scheme allow-list plus a host
block-list covering localhost, *.local, and loopback/link-local/RFC1918
IPv4 and IPv6 loopback/unique-local/link-local literals. Closes
linkpreview-1 and linkpreview-3 at the policy layer."
```

---

## Task 3: Extend `StubURLProtocol` to emit redirects

**Files:** Modify `Packages/LillistCore/Tests/LillistCoreTests/Helpers/StubURLProtocol.swift`.

The current stub can only emit a single terminal response. The 302-to-blocked-host and hop-cap tests in Task 5 need it to emit a 3xx with a `Location` header so `URLSession` invokes the fetcher's redirect delegate. This is a test-helper change with no production impact; it is verified by the existing LinkPreview tests still passing plus the new tests in Task 5.

- [ ] **Step 1: Add a redirect-aware response path.** Replace the `Response` struct and `startLoading()` (current lines 16–20 and 42–59) so the stub can emit a redirect. The full replacement for `startLoading()` and the augmented `Response`:

Replace the `Response` struct (current lines 16–20):

```swift
    struct Response {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
    }
```

with:

```swift
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
```

Then replace `startLoading()` (current lines 42–59):

```swift
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
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }
```

with:

```swift
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
```

- [ ] **Step 2: Verify existing LinkPreview tests still pass.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter LinkPreview
```

Expected: `LinkPreviewUnfurler` and `URLPreviewPolicy` suites pass unchanged (no behavior change for non-3xx responses).

- [ ] **Step 3: Commit.**

```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistCore/Tests/LillistCoreTests/Helpers/StubURLProtocol.swift
git commit -m "test(linkpreview): let StubURLProtocol emit 3xx redirects

Adds Response.redirect(to:) and a wasRedirectedTo path so the fetcher's
redirect-guarding delegate can be exercised. Refs linkpreview-2, test-1."
```

---

## Task 4: Enforce the policy + streaming cap + redirect guard in `URLSessionLinkPreviewFetcher` (TDD)

**Files:**
- Create `Packages/LillistCore/Tests/LillistCoreTests/LinkPreview/URLSessionLinkPreviewFetcherTests.swift`
- Modify `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLSessionLinkPreviewFetcher.swift` (whole file).

The fetcher gains: (a) a `URLPreviewPolicy.isAllowed` pre-check returning `nil` for blocked URLs, (b) a `bytes(for:delegate:)` streaming loop that aborts as soon as the running total exceeds `bodyCapBytes`, and (c) a private `RedirectGuard` delegate that re-applies the policy and caps hops.

- [ ] **Step 1: Write the failing tests.** Create `Packages/LillistCore/Tests/LillistCoreTests/LinkPreview/URLSessionLinkPreviewFetcherTests.swift` with the complete content:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("URLSessionLinkPreviewFetcher SSRF guards")
struct URLSessionLinkPreviewFetcherTests {
    // Happy path through the streaming reader.
    @Test("fetchHTML returns body for a small text/html response")
    func fetchHTMLHappyPath() async {
        let session = StubURLProtocol.session { url in
            guard url.path == "/page" else { return nil }
            let html = "<html><head><title>OK</title></head></html>"
            return .init(statusCode: 200, headers: ["Content-Type": "text/html"], body: Data(html.utf8))
        }
        let fetcher = URLSessionLinkPreviewFetcher(session: session)
        let data = await fetcher.fetchHTML(url: URL(string: "https://example.com/page")!)
        #expect(data != nil)
        #expect(String(data: data ?? Data(), encoding: .utf8)?.contains("OK") == true)
    }

    // linkpreview-1: blocked scheme never reaches the network.
    @Test("fetchHTML returns nil for a file:// URL without hitting the session")
    func fetchHTMLBlocksFileScheme() async {
        let session = StubURLProtocol.session { _ in
            Issue.record("Blocked URL must not reach the session")
            return .init(statusCode: 200, headers: ["Content-Type": "text/html"], body: Data("x".utf8))
        }
        let fetcher = URLSessionLinkPreviewFetcher(session: session)
        let data = await fetcher.fetchHTML(url: URL(string: "file:///etc/passwd")!)
        #expect(data == nil)
    }

    // linkpreview-3: private host never reaches the network.
    @Test("fetchHTML returns nil for a 127.0.0.1 URL without hitting the session")
    func fetchHTMLBlocksLoopbackHost() async {
        let session = StubURLProtocol.session { _ in
            Issue.record("Blocked URL must not reach the session")
            return .init(statusCode: 200, headers: ["Content-Type": "text/html"], body: Data("x".utf8))
        }
        let fetcher = URLSessionLinkPreviewFetcher(session: session)
        let data = await fetcher.fetchHTML(url: URL(string: "http://127.0.0.1/")!)
        #expect(data == nil)
    }

    @Test("fetchImage returns nil for a link-local metadata URL")
    func fetchImageBlocksLinkLocal() async {
        let session = StubURLProtocol.session { _ in
            Issue.record("Blocked URL must not reach the session")
            return .init(statusCode: 200, headers: ["Content-Type": "image/png"], body: Data([0x89, 0x50]))
        }
        let fetcher = URLSessionLinkPreviewFetcher(session: session)
        let data = await fetcher.fetchImage(url: URL(string: "http://169.254.169.254/latest/meta-data/")!)
        #expect(data == nil)
    }

    // linkpreview-2: a redirect to a blocked host is refused.
    @Test("fetchHTML refuses a 302 redirect to a private host")
    func fetchHTMLBlocksRedirectToPrivateHost() async {
        let session = StubURLProtocol.session { url in
            switch url.host {
            case "example.com":
                return .redirect(to: "http://127.0.0.1/secret")
            case "127.0.0.1":
                Issue.record("Redirect to a private host must be refused before the follow-up request")
                return .init(statusCode: 200, headers: ["Content-Type": "text/html"], body: Data("leak".utf8))
            default:
                return nil
            }
        }
        let fetcher = URLSessionLinkPreviewFetcher(session: session)
        let data = await fetcher.fetchHTML(url: URL(string: "https://example.com/start")!)
        #expect(data == nil)
    }

    // linkpreview-2: a redirect to another public host is allowed.
    @Test("fetchHTML follows a single 302 to a public host")
    func fetchHTMLFollowsPublicRedirect() async {
        let session = StubURLProtocol.session { url in
            switch (url.host, url.path) {
            case ("a.example", "/start"):
                return .redirect(to: "https://b.example/final")
            case ("b.example", "/final"):
                return .init(statusCode: 200, headers: ["Content-Type": "text/html"], body: Data("<html>arrived</html>".utf8))
            default:
                return nil
            }
        }
        let fetcher = URLSessionLinkPreviewFetcher(session: session)
        let data = await fetcher.fetchHTML(url: URL(string: "https://a.example/start")!)
        #expect(String(data: data ?? Data(), encoding: .utf8)?.contains("arrived") == true)
    }

    // linkpreview-2: too many hops is refused even when every hop is public.
    @Test("fetchHTML gives up after exceeding the redirect hop limit")
    func fetchHTMLEnforcesHopLimit() async {
        let session = StubURLProtocol.session { url in
            // Each hop redirects to the next index on a public host; the
            // chain is longer than redirectHopLimit so it must fail.
            let hop = Int(url.lastPathComponent) ?? 0
            return .redirect(to: "https://chain.example/\(hop + 1)")
        }
        let fetcher = URLSessionLinkPreviewFetcher(session: session)
        let data = await fetcher.fetchHTML(url: URL(string: "https://chain.example/0")!)
        #expect(data == nil)
    }

    // linkpreview-2 / size cap: an oversize body is aborted mid-stream.
    @Test("fetchHTML returns nil when the body exceeds the 5 MB cap")
    func fetchHTMLAbortsOversizeBody() async {
        let oversize = Data(repeating: 0x41, count: LinkPreviewLimits.bodyCapBytes + 1024)
        let session = StubURLProtocol.session { url in
            guard url.path == "/big" else { return nil }
            return .init(statusCode: 200, headers: ["Content-Type": "text/html"], body: oversize)
        }
        let fetcher = URLSessionLinkPreviewFetcher(session: session)
        let data = await fetcher.fetchHTML(url: URL(string: "https://example.com/big")!)
        #expect(data == nil)
    }

    @Test("fetchHTML accepts a body exactly at the cap")
    func fetchHTMLAcceptsBodyAtCap() async {
        let atCap = Data(repeating: 0x41, count: LinkPreviewLimits.bodyCapBytes)
        let session = StubURLProtocol.session { url in
            guard url.path == "/atcap" else { return nil }
            return .init(statusCode: 200, headers: ["Content-Type": "text/html"], body: atCap)
        }
        let fetcher = URLSessionLinkPreviewFetcher(session: session)
        let data = await fetcher.fetchHTML(url: URL(string: "https://example.com/atcap")!)
        #expect(data?.count == LinkPreviewLimits.bodyCapBytes)
    }
}
```

- [ ] **Step 2: Run the tests, expect failure.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "URLSessionLinkPreviewFetcher SSRF guards"
```

Expected: failures — at minimum `fetchHTMLBlocksFileScheme`, `fetchHTMLBlocksLoopbackHost`, `fetchImageBlocksLinkLocal`, `fetchHTMLBlocksRedirectToPrivateHost`, `fetchHTMLEnforcesHopLimit`, and `fetchHTMLAbortsOversizeBody` fail because the current fetcher applies no policy, follows redirects unguarded, and buffers the whole body (the oversize test currently only rejects *after* fully downloading, and the redirect tests record `Issue`s).

- [ ] **Step 3: Implement the minimal change.** Replace the entire contents of `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLSessionLinkPreviewFetcher.swift` with:

```swift
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
```

- [ ] **Step 4: Run the tests, expect pass.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "URLSessionLinkPreviewFetcher SSRF guards"
```

Expected: all nine tests in the suite pass, zero failures. Then run the whole LinkPreview area to confirm no regression:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter LinkPreview
```

Expected: `URLPreviewPolicy`, `LinkPreviewUnfurler`, and `URLSessionLinkPreviewFetcher SSRF guards` suites all pass.

- [ ] **Step 5: Commit.**

```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistCore/Sources/LillistCore/LinkPreview/URLSessionLinkPreviewFetcher.swift \
        Packages/LillistCore/Tests/LillistCoreTests/LinkPreview/URLSessionLinkPreviewFetcherTests.swift
git commit -m "feat(linkpreview): enforce SSRF policy, redirect guard, streaming cap

fetchHTML/fetchImage now pre-validate via URLPreviewPolicy, stream the
body with bytes(for:delegate:) aborting past the 5 MB cap, and attach a
per-task RedirectGuard that re-applies the policy on each redirect and
caps the hop count. Closes linkpreview-1, linkpreview-2, linkpreview-3."
```

---

## Task 5: Gate ingest in `CLIBridge.LinkHandler.run` (TDD)

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/LinkHandler.swift` (lines 12–14).
- Modify `Packages/LillistCore/Tests/LillistCoreTests/CLIBridge/Handlers/LinkHandlerTests.swift` (add one test).

Defense in depth: even though the fetcher now refuses blocked URLs, a blocked URL still creates an attachment row today. Reject at the boundary so no row is created and the CLI reports a validation error.

- [ ] **Step 1: Write the failing test.** Append this test inside the `LinkHandlerTests` struct in `Packages/LillistCore/Tests/LillistCoreTests/CLIBridge/Handlers/LinkHandlerTests.swift` (after the existing `runWithStubFetcher` test, before the closing `}`):

```swift
    @Test("Run rejects a non-http/https URL at the ingest boundary")
    func runRejectsBlockedScheme() async throws {
        let persistence = try await TestStore.make()
        let tasks = TaskStore(persistence: persistence)
        let taskID = try await tasks.create(title: "host")

        await #expect(throws: LillistError.self) {
            _ = try await CLIBridge.LinkHandler.run(
                token: taskID.uuidString,
                urlString: "file:///etc/passwd",
                persistence: persistence,
                fetcher: nil
            )
        }
    }

    @Test("Run rejects a private-host URL and creates no attachment")
    func runRejectsPrivateHost() async throws {
        let persistence = try await TestStore.make()
        let tasks = TaskStore(persistence: persistence)
        let taskID = try await tasks.create(title: "host")

        await #expect(throws: LillistError.self) {
            _ = try await CLIBridge.LinkHandler.run(
                token: taskID.uuidString,
                urlString: "http://169.254.169.254/latest/meta-data/",
                persistence: persistence,
                fetcher: nil
            )
        }

        let count = try await AttachmentStore(persistence: persistence).count(forTask: taskID)
        #expect(count == 0)
    }
```

> Note: if `AttachmentStore` exposes no `count(forTask:)`, replace the final two lines of `runRejectsPrivateHost` with a `fetchAll`/list call that the store does expose (verify the store's public surface with `grep -n "public func" Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift`); the assertion intent is "zero attachments for the task." Keep `runRejectsBlockedScheme` as-is regardless.

- [ ] **Step 2: Run the test, expect failure.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter LinkHandler
```

Expected: `runRejectsBlockedScheme` and `runRejectsPrivateHost` fail — the current handler accepts any URL whose `scheme != nil`, so `file://` and the link-local host pass the guard and an attachment row is created (no error thrown).

- [ ] **Step 3: Implement the minimal change.** Replace the URL validation block in `LinkHandler.run` (current lines 12–14):

```swift
            guard let url = URL(string: urlString), url.scheme != nil else {
                throw LillistError.validationFailed([.init(field: "url", message: "invalid URL '\(urlString)'")])
            }
```

with:

```swift
            guard let url = URL(string: urlString), url.scheme != nil else {
                throw LillistError.validationFailed([.init(field: "url", message: "invalid URL '\(urlString)'")])
            }
            // SSRF ingest guard (linkpreview-1/3): refuse non-http(s)
            // schemes and private/loopback/link-local hosts before any
            // attachment row is created.
            guard URLPreviewPolicy.isAllowed(url) else {
                throw LillistError.validationFailed([
                    .init(field: "url", message: "URL is not allowed for link previews: '\(urlString)'")
                ])
            }
```

- [ ] **Step 4: Run the test, expect pass.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter LinkHandler
```

Expected: `runWithStubFetcher`, `runRejectsBlockedScheme`, and `runRejectsPrivateHost` all pass.

- [ ] **Step 5: Commit.**

```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/LinkHandler.swift \
        Packages/LillistCore/Tests/LillistCoreTests/CLIBridge/Handlers/LinkHandlerTests.swift
git commit -m "feat(linkpreview): gate LinkHandler ingest with URLPreviewPolicy

Blocked schemes and private/loopback hosts now throw validationFailed
before any attachment row is created. Closes the CLI ingest half of
linkpreview-1/3."
```

---

## Task 6: Gate ingest in the iOS Share Extension

**Files:** Modify `Extensions/ShareExtension-iOS/ShareRootView.swift` (lines 82–91, the `addLinkPreview` block; and the surrounding `save()`).

The Share Extension persists `attachedURL` directly via `addLinkPreview` with no scheme check. Apply `URLPreviewPolicy` so a shared `file://`/private-host URL is dropped (and the user sees why) rather than stored as SSRF bait. The extension target imports `LillistCore`, so `URLPreviewPolicy` is available. This is iOS-app/extension code; it builds under `xcodebuild` (not `swift test`).

- [ ] **Step 1: Read the current file.** Re-read `Extensions/ShareExtension-iOS/ShareRootView.swift` to confirm lines 82–91 and the `saveError` state are unchanged since this plan was written:

```bash
cd /Volumes/Code/mikeyward/Lillist && grep -n "addLinkPreview\|attachedURL\|saveError" Extensions/ShareExtension-iOS/ShareRootView.swift
```

Expected: the `if let url = attachedURL { _ = try? await attachmentStore.addLinkPreview(...) }` block is present around lines 82–91.

- [ ] **Step 2: Implement the guard.** Replace the `addLinkPreview` block (current lines 82–91):

```swift
            if let url = attachedURL {
                _ = try? await attachmentStore.addLinkPreview(
                    taskID: taskID,
                    url: url,
                    title: nil,
                    description: nil,
                    thumbnailData: nil,
                    faviconData: nil
                )
            }
```

with:

```swift
            if let url = attachedURL {
                // SSRF ingest guard (linkpreview-1/3): only persist a link
                // attachment for an http/https URL on a non-private host.
                // A blocked URL is dropped; the task itself still saves.
                if URLPreviewPolicy.isAllowed(url) {
                    _ = try? await attachmentStore.addLinkPreview(
                        taskID: taskID,
                        url: url,
                        title: nil,
                        description: nil,
                        thumbnailData: nil,
                        faviconData: nil
                    )
                } else {
                    saveError = "That link can't be previewed and was not attached."
                }
            }
```

- [ ] **Step 3: Build the iOS app target (no signing).** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **` with no new warnings (`URLPreviewPolicy` resolves via the `import LillistCore` already at the top of the file).

- [ ] **Step 4: Commit.**

```bash
cd /Volumes/Code/mikeyward/Lillist
git add Extensions/ShareExtension-iOS/ShareRootView.swift
git commit -m "feat(linkpreview): gate Share Extension ingest with URLPreviewPolicy

A shared non-http(s)/private-host URL is no longer persisted as a link
attachment; the task still saves and the sheet explains why. Closes the
Share Extension ingest half of linkpreview-1/3."
```

---

## Task 7: Full-suite regression + warnings-as-errors check

**Files:** none (verification only).

- [ ] **Step 1: Run the full LillistCore test suite.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore
```

Expected: the entire suite passes, including the new `URLPreviewPolicy`, `URLSessionLinkPreviewFetcher SSRF guards`, updated `LinkHandler`, and unchanged `LinkPreviewUnfurler` tests. Zero failures.

- [ ] **Step 2: Confirm a clean warnings-as-errors build of the source target.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift build --package-path Packages/LillistCore
```

Expected: `Build complete!` — no warnings (they are errors on this target; in particular confirm `RedirectGuard`'s `@unchecked Sendable` and the `bytes(for:delegate:)` call produce no concurrency diagnostics).

- [ ] **Step 3: Build the iOS app + Share Extension once more (no signing).** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`. No commit — this task only verifies the integrated result.

---

## Self-review checklist

- [ ] **linkpreview-1 (scheme validation):** closed by Task 2 (`URLPreviewPolicy.allowedSchemes` http/https-only + `URLPreviewPolicyTests.nonHTTPSchemesBlocked`), Task 4 (`fetchHTML`/`fetchImage` pre-check + `fetchHTMLBlocksFileScheme`), Task 5 (`LinkHandler.run` guard + `runRejectsBlockedScheme`), and Task 6 (Share Extension guard).
- [ ] **linkpreview-2 (redirect + size guards):** closed by Task 1 (`redirectHopLimit`), Task 3 (`StubURLProtocol` redirect emission), and Task 4 (`RedirectGuard` re-applying the policy + hop cap, and the `bytes(for:delegate:)` streaming early-abort cap; tests `fetchHTMLBlocksRedirectToPrivateHost`, `fetchHTMLFollowsPublicRedirect`, `fetchHTMLEnforcesHopLimit`, `fetchHTMLAbortsOversizeBody`, `fetchHTMLAcceptsBodyAtCap`).
- [ ] **linkpreview-3 (private-host validation):** closed by Task 2 (`isBlockedHost` covering localhost/`*.local`/IPv4 loopback+link-local+RFC1918/IPv6 loopback+unique-local+link-local, with the `URLPreviewPolicyTests` host/IP cases), enforced in the fetcher (Task 4: `fetchHTMLBlocksLoopbackHost`, `fetchImageBlocksLinkLocal`), at the CLI boundary (Task 5: `runRejectsPrivateHost`), and at the Share Extension boundary (Task 6).
- [ ] **test-1 (StubURLProtocol negative tests for this pipeline):** the four mandated negative cases — blocked scheme, private host, 302-to-blocked-host, oversize body — all exist as named `StubURLProtocol`-backed tests in `URLSessionLinkPreviewFetcherTests` (Task 4).
- [ ] **Strengths preserved:** the clean `LinkPreviewFetching` protocol seam, the per-session-token `StubURLProtocol` isolation pattern, and the `LinkPreviewUnfurler` "best-effort, fold-to-failure" outcome contract are all retained — no callers' signatures changed and existing `LinkPreviewUnfurler`/`LinkHandler` happy-path tests still pass unchanged.
- [ ] **Conventions:** value-type policy (no `NSManagedObject` escape), explicit `public` API, Calendar not relevant (no date math), strict-concurrency-clean `RedirectGuard`, warnings-as-errors verified, conventional commits per task.
