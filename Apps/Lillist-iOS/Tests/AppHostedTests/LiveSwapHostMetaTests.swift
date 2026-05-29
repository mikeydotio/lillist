import Testing
import Foundation

/// Meta-test: this target exists *specifically* to run the live-store
/// swap tests under a real app host. Those tests gate themselves on
/// `Bundle.main.bundleIdentifier?.isEmpty == false` (a.k.a.
/// `liveSwapAllowed`). If the host is ever misconfigured back to a
/// `TEST_HOST=""` standalone bundle, that gate silently turns the
/// safety-critical swap tests into no-ops that "pass". This test fails
/// loudly in that case so the regression can't ship green (test-1).
@Suite("Live swap host configuration")
struct LiveSwapHostMetaTests {
    @Test("This target runs inside a real app host (non-empty bundle identifier)")
    func bundleIdentifierIsPresent() {
        let bundleID = Bundle.main.bundleIdentifier
        #expect(bundleID?.isEmpty == false,
                "Live-swap tests require an app-hosted target. Bundle.main.bundleIdentifier was \(bundleID ?? "nil"). The Lillist-iOSAppHostedTests target must keep TEST_HOST pointed at Lillist-iOS.")
    }
}
