import Testing
import Foundation
@testable import LillistCore

@Suite("CrashReport Codable")
struct CrashReportCodableTests {
    private func sampleCanary() -> CrashCanary {
        CrashCanary(pid: 42, startedAt: Date(timeIntervalSince1970: 1_000_000), buildVersion: "1.0 (1)", hostname: "host")
    }

    @Test("Round-trips with all sections present")
    func full_roundTrip() throws {
        let report = CrashReport(
            buildVersion: "1.0 (1)",
            osVersion: "macOS 15.4",
            deviceModel: "MacBookPro18,4",
            canary: sampleCanary(),
            userDescription: "I clicked the new-task button",
            logs: ["redacted line 1", "redacted line 2"],
            breadcrumbs: [Breadcrumb(action: "task.create", at: .now, success: true)]
        )
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(CrashReport.self, from: data)
        #expect(decoded.buildVersion == report.buildVersion)
        #expect(decoded.osVersion == report.osVersion)
        #expect(decoded.deviceModel == report.deviceModel)
        #expect(decoded.canary == report.canary)
        #expect(decoded.userDescription == report.userDescription)
        #expect(decoded.logs == report.logs)
        #expect(decoded.breadcrumbs?.count == 1)
    }

    @Test("Round-trips with logs and breadcrumbs both nil")
    func minimal_roundTrip() throws {
        let report = CrashReport(
            buildVersion: "1.0",
            osVersion: "iOS 18",
            deviceModel: "iPhone17,1",
            canary: sampleCanary(),
            userDescription: nil,
            logs: nil,
            breadcrumbs: nil
        )
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(CrashReport.self, from: data)
        #expect(decoded.logs == nil)
        #expect(decoded.breadcrumbs == nil)
        #expect(decoded.userDescription == nil)
    }

    @Test("Round-trips with logs present, breadcrumbs nil")
    func logsOnly_roundTrip() throws {
        let report = CrashReport(
            buildVersion: "1.0",
            osVersion: "macOS 15",
            deviceModel: "Mac",
            canary: sampleCanary(),
            userDescription: nil,
            logs: ["line"],
            breadcrumbs: nil
        )
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(CrashReport.self, from: data)
        #expect(decoded.logs == ["line"])
        #expect(decoded.breadcrumbs == nil)
    }

    @Test("Round-trips with breadcrumbs present, logs nil")
    func breadcrumbsOnly_roundTrip() throws {
        let report = CrashReport(
            buildVersion: "1.0",
            osVersion: "macOS 15",
            deviceModel: "Mac",
            canary: sampleCanary(),
            userDescription: nil,
            logs: nil,
            breadcrumbs: [Breadcrumb(action: "a", at: .now, success: false)]
        )
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(CrashReport.self, from: data)
        #expect(decoded.logs == nil)
        #expect(decoded.breadcrumbs?.count == 1)
    }

    @Test("renderedAsPlainText is deterministic across runs")
    func plainText_stable() {
        let report = CrashReport(
            buildVersion: "1.0 (1)",
            osVersion: "macOS 15",
            deviceModel: "Mac",
            canary: sampleCanary(),
            userDescription: "did a thing",
            logs: ["log line"],
            breadcrumbs: [Breadcrumb(action: "task.create", at: Date(timeIntervalSince1970: 0), success: true)]
        )
        let a = report.renderedAsPlainText()
        let b = report.renderedAsPlainText()
        #expect(a == b)
        #expect(a.contains("Build: 1.0 (1)"))
        #expect(a.contains("did a thing"))
        #expect(a.contains("log line"))
        #expect(a.contains("task.create"))
    }
}
