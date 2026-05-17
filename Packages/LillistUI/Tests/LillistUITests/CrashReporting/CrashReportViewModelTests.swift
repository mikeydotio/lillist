import XCTest
import Foundation
import LillistCore
@testable import LillistUI

/// Plan 18 Task 10: `renderPreview(includeLogs:includeBreadcrumbs:...)` is
/// the pure sibling of `refreshPreview`. Per-toggle preview buttons in
/// `CrashReportSheet` call it without mutating the model's stored
/// `includeLogs` / `includeBreadcrumbs` flags. This suite pins the
/// contract: the returned string includes (or omits) the logs and
/// breadcrumbs blocks based on the arguments — and `self.previewText`
/// stays untouched.
@MainActor
final class CrashReportViewModelTests: XCTestCase {

    private func makeModel() -> CrashReportViewModel {
        let canary = CrashCanary(
            pid: 1,
            startedAt: Date(timeIntervalSince1970: 0),
            buildVersion: "1.0",
            hostname: "h"
        )
        let reporter = CrashReporter(
            canaryFile: CanaryFile(
                url: FileManager.default.temporaryDirectory.appendingPathComponent("vm-\(UUID()).json")
            ),
            buildVersion: "1.0 (1)",
            osVersion: "macOS 15",
            deviceModel: "Mac",
            hostname: "host",
            logFetcher: NoopLogFetcher(),
            breadcrumbs: BreadcrumbBuffer(),
            transport: NoopTransport()
        )
        return CrashReportViewModel(pending: canary, reporter: reporter)
    }

    func test_renderPreview_logsOnly_includes_log_marker() async {
        let model = makeModel()
        let body = await model.renderPreview(
            includeLogs: true,
            includeBreadcrumbs: false,
            buildVersion: "1.0 (1)",
            osVersion: "macOS 15",
            deviceModel: "Mac"
        )
        XCTAssertTrue(body.contains("logs"), "Logs section should appear in the body")
    }

    func test_renderPreview_breadcrumbsOnly_excludes_log_marker() async {
        let model = makeModel()
        let body = await model.renderPreview(
            includeLogs: false,
            includeBreadcrumbs: true,
            buildVersion: "1.0 (1)",
            osVersion: "macOS 15",
            deviceModel: "Mac"
        )
        XCTAssertFalse(body.contains("(logs will be loaded here when sent)"),
                       "Logs sentinel should not appear when includeLogs is false")
    }

    func test_renderPreview_does_not_mutate_model_flags() async {
        let model = makeModel()
        // Start with the production defaults (both true).
        XCTAssertTrue(model.includeLogs)
        XCTAssertTrue(model.includeBreadcrumbs)
        _ = await model.renderPreview(
            includeLogs: false,
            includeBreadcrumbs: false,
            buildVersion: "1.0 (1)",
            osVersion: "macOS 15",
            deviceModel: "Mac"
        )
        XCTAssertTrue(model.includeLogs, "renderPreview must not mutate includeLogs")
        XCTAssertTrue(model.includeBreadcrumbs, "renderPreview must not mutate includeBreadcrumbs")
        XCTAssertEqual(model.previewText, "", "renderPreview must not write previewText")
    }

    func test_refreshPreview_still_stores_previewText() async {
        let model = makeModel()
        await model.refreshPreview(
            buildVersion: "1.0 (1)",
            osVersion: "macOS 15",
            deviceModel: "Mac"
        )
        XCTAssertFalse(model.previewText.isEmpty,
                       "refreshPreview should populate previewText for the bulk preview sheet")
    }
}

private struct NoopLogFetcher: LogFetching {
    func fetchRecentLines(since: Date, subsystem: String) async throws -> [String] { [] }
}

private actor NoopTransport: CrashReportTransport {
    func send(_ report: CrashReport) async throws {}
}
