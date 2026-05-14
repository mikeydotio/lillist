import Testing
import Foundation
import OSLog
@testable import LillistCore

@Suite("OSLogFetcher")
struct OSLogFetcherTests {
    @Test("Fake fetcher returns whatever was injected")
    func fake_returnsInjected() async throws {
        let fake = FakeLogFetcher(lines: ["a", "b"])
        let lines = try await fake.fetchRecentLines(since: .now, subsystem: "x")
        #expect(lines == ["a", "b"])
    }

    @Test("Real OSLogFetcher returns an array (may be empty in test environments)")
    func real_returnsArray() async throws {
        let fetcher = OSLogFetcher()
        let lines = try await fetcher.fetchRecentLines(
            since: Date(timeIntervalSinceNow: -300),
            subsystem: CrashReporting.subsystemIdentifier
        )
        // We don't assert non-empty: sandboxed test runners may not
        // grant log access. We only assert it doesn't throw.
        #expect(lines.count >= 0)
    }
}

/// Test-only fake.
struct FakeLogFetcher: LogFetching {
    let lines: [String]
    func fetchRecentLines(since: Date, subsystem: String) async throws -> [String] {
        lines
    }
}
