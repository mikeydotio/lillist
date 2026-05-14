import XCTest
import Foundation
import LillistCore

final class ReportCrashIntentTests: XCTestCase {
    /// Helper: fresh temp path so we never touch real ~/Library state.
    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("intent-canary-\(UUID().uuidString).json")
    }

    func test_noPendingCanary_returnsFriendlyMessage() {
        let url = makeTempURL()
        // Ensure no file is present.
        try? FileManager.default.removeItem(at: url)

        let message = ReportCrashIntentResolver.resolve(canaryURL: url)
        XCTAssertTrue(message.contains("No pending crash"), "got: \(message)")
    }

    func test_pendingCanary_promptsToOpenLillist() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try CanaryFile(url: url).writeFresh(
            CrashCanary(pid: 1, startedAt: .now, buildVersion: "1.0", hostname: "h")
        )

        let message = ReportCrashIntentResolver.resolve(canaryURL: url)
        XCTAssertTrue(message.contains("Open Lillist"), "got: \(message)")
    }
}
