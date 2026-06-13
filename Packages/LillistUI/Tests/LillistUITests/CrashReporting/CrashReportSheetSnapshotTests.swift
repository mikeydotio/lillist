#if os(macOS)
import XCTest
import SwiftUI
import SnapshotTesting
import LillistCore
@testable import LillistUI

@MainActor
final class CrashReportSheetSnapshotTests: RecordableSnapshotTestCase {

    private func makeModel(description: String = "") -> CrashReportViewModel {
        let canary = CrashCanary(pid: 1, startedAt: Date(timeIntervalSince1970: 0), buildVersion: "1.0", hostname: "h")
        let reporter = CrashReporter(
            canaryFile: CanaryFile(url: FileManager.default.temporaryDirectory.appendingPathComponent("snap-\(UUID()).json")),
            buildVersion: "1.0 (1)",
            osVersion: "macOS 15",
            deviceModel: "Mac",
            hostname: "host",
            logFetcher: NoopLogFetcher(),
            breadcrumbs: BreadcrumbBuffer(),
            transport: NoopTransport()
        )
        let model = CrashReportViewModel(pending: canary, reporter: reporter)
        model.userDescription = description
        return model
    }

    private func host(_ view: some View, colorScheme: ColorScheme, size: CGSize = CGSize(width: 480, height: 640)) -> NSView {
        makeHostingView(
            SnapshotHost(colorScheme: colorScheme) { view },
            size: size
        )
    }

    func test_light_emptyDescription() {
        let view = CrashReportSheet(model: makeModel(), buildVersion: "1.0 (1)", osVersion: "macOS 15", deviceModel: "Mac")
        assertSnapshot(of: host(view, colorScheme: .light), as: .image(size: CGSize(width: 480, height: 640)))
    }

    func test_dark_emptyDescription() {
        let view = CrashReportSheet(model: makeModel(), buildVersion: "1.0 (1)", osVersion: "macOS 15", deviceModel: "Mac")
        assertSnapshot(of: host(view, colorScheme: .dark), as: .image(size: CGSize(width: 480, height: 640)))
    }

    func test_light_filledDescription() {
        let view = CrashReportSheet(model: makeModel(description: "I was reorganizing tags."), buildVersion: "1.0 (1)", osVersion: "macOS 15", deviceModel: "Mac")
        assertSnapshot(of: host(view, colorScheme: .light), as: .image(size: CGSize(width: 480, height: 640)))
    }

    func test_dark_filledDescription() {
        let view = CrashReportSheet(model: makeModel(description: "I was reorganizing tags."), buildVersion: "1.0 (1)", osVersion: "macOS 15", deviceModel: "Mac")
        assertSnapshot(of: host(view, colorScheme: .dark), as: .image(size: CGSize(width: 480, height: 640)))
    }

    func test_previewSheet_renderedPayload() {
        let body = """
        Lillist crash report
        ====================

        Build: 1.0 (1)
        OS: macOS 15
        Device: Mac
        """
        let view = CrashReportPreviewSheet(body: body)
        assertSnapshot(of: host(view, colorScheme: .light), as: .image(size: CGSize(width: 480, height: 640)))
    }
}

private struct NoopLogFetcher: LogFetching {
    func fetchRecentLines(since: Date, subsystem: String) async throws -> [String] { [] }
}

private actor NoopTransport: CrashReportTransport {
    func send(_ report: CrashReport) async throws {}
}
#endif
