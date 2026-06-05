import XCTest
import Foundation
import LillistCore

/// Pins the SSRF gate the iOS Share Extension applies before persisting a
/// pasted/shared link (`link-preview-ssrf-guards` Task 6, residual #10).
/// `ShareRootView.save()` is SwiftUI in the signed extension and can't be
/// `@testable import`-ed, so we assert the shared `URLPreviewPolicy`
/// decision directly — the same call `save()` makes.
final class ShareLinkPolicyTests: XCTestCase {
    func test_loopbackURL_isRejected() {
        XCTAssertFalse(URLPreviewPolicy.isAllowed(URL(string: "http://localhost/x")!))
        XCTAssertFalse(URLPreviewPolicy.isAllowed(URL(string: "http://127.0.0.1/x")!))
    }

    func test_httpsPublicURL_isAccepted() {
        XCTAssertTrue(URLPreviewPolicy.isAllowed(URL(string: "https://apple.com/x")!))
    }
}
