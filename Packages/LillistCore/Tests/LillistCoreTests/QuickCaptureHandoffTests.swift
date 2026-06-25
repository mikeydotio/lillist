import Testing
import Foundation
@testable import LillistCore

@Suite("QuickCaptureHandoff")
struct QuickCaptureHandoffTests {
    private static func freshSuite() -> String {
        let suite = "QuickCaptureHandoffTests-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        return suite
    }

    @Test("Stash then take round-trips the seed text")
    func roundTrip() {
        let suite = Self.freshSuite()
        QuickCaptureHandoff.stash("buy milk", appGroupID: suite)
        #expect(QuickCaptureHandoff.take(appGroupID: suite) == "buy milk")
    }

    @Test("An empty-string seed still returns non-nil (means: open empty dialog)")
    func emptySeedOpens() {
        let suite = Self.freshSuite()
        QuickCaptureHandoff.stash("", appGroupID: suite)
        #expect(QuickCaptureHandoff.take(appGroupID: suite) == "")
    }

    @Test("Take clears the seed — a second take returns nil")
    func takeClears() {
        let suite = Self.freshSuite()
        QuickCaptureHandoff.stash("once", appGroupID: suite)
        _ = QuickCaptureHandoff.take(appGroupID: suite)
        #expect(QuickCaptureHandoff.take(appGroupID: suite) == nil)
    }

    @Test("No stash means take returns nil")
    func absentReturnsNil() {
        #expect(QuickCaptureHandoff.take(appGroupID: Self.freshSuite()) == nil)
    }

    @Test("A seed older than the TTL is discarded")
    func ttlExpiry() {
        let suite = Self.freshSuite()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        QuickCaptureHandoff.stash("stale", appGroupID: suite, now: t0)
        let expired = QuickCaptureHandoff.take(
            appGroupID: suite,
            now: t0.addingTimeInterval(QuickCaptureHandoff.ttl + 1)
        )
        #expect(expired == nil)
    }

    @Test("A seed within the TTL is returned")
    func withinTTL() {
        let suite = Self.freshSuite()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        QuickCaptureHandoff.stash("fresh", appGroupID: suite, now: t0)
        let value = QuickCaptureHandoff.take(
            appGroupID: suite,
            now: t0.addingTimeInterval(QuickCaptureHandoff.ttl - 1)
        )
        #expect(value == "fresh")
    }
}
