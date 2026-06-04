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
