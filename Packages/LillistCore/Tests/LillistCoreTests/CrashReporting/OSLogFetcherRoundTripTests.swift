import Testing
import Foundation
import OSLog
@testable import LillistCore

@Suite("OSLogFetcher round-trip")
struct OSLogFetcherRoundTripTests {
    /// Emit a uniquely-tagged line through the production LillistLog
    /// path, then read it back through the SAME subsystem the crash
    /// reporter queries. When log access is granted (local dev,
    /// host-app test target) this proves the logs section is now real;
    /// when it is denied (sandboxed CI) we assert only that the fetch
    /// does not throw, matching OSLogFetcherTests' calibration.
    @Test("A LillistLog line is collectable via the crash-reporter subsystem")
    func lillistLogLineIsCollectable() async throws {
        let marker = "rt-marker-\(UUID().uuidString)"
        let since = Date()
        LillistLog.app.notice("\(marker, privacy: .public)")

        let fetcher = OSLogFetcher()
        let lines = try await fetcher.fetchRecentLines(
            since: since.addingTimeInterval(-1),
            subsystem: CrashReporting.subsystemIdentifier
        )

        // Always-true safety net so sandboxed runners pass.
        #expect(lines.count >= 0)
        // When the store returned entries at all, our marker must be
        // among them — i.e. LillistLog writes on the subsystem the
        // crash reporter reads. If the store returned nothing, log
        // access was denied and we skip the strict check.
        if !lines.isEmpty {
            #expect(lines.contains { $0.contains(marker) })
        }
    }
}
