import Testing
import Foundation
@testable import LillistCore

@Suite("CrashReportTransport")
struct CrashReportTransportTests {
    private func sampleReport() -> CrashReport {
        CrashReport(
            buildVersion: "1.0 (1)",
            osVersion: "macOS 15",
            deviceModel: "Mac",
            canary: CrashCanary(pid: 1, startedAt: .now, buildVersion: "1.0 (1)", hostname: "h"),
            userDescription: "test",
            logs: ["line one"],
            breadcrumbs: [Breadcrumb(action: "task.create", at: .now, success: true)]
        )
    }

    @Test("RecordingTransport captures the payload on send")
    func recording_captures() async throws {
        let recording = RecordingTransport()
        try await recording.send(sampleReport())
        let captured = await recording.captured
        #expect(captured.count == 1)
        #expect(captured.first?.userDescription == "test")
    }

    @Test("FileSaveTransport writes a .lillistcrash bundle at the destination")
    func fileSave_writesBundle() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("crash-\(UUID()).lillistcrash")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let transport = FileSaveTransport(destination: tmp)
        try await transport.send(sampleReport())
        #expect(FileManager.default.fileExists(atPath: tmp.path))
        let data = try Data(contentsOf: tmp)
        // The bundle is JSON for v1 (a real zip would require a third-
        // party dependency; the design accepts a JSON file as a
        // first-pass implementation of the .lillistcrash format).
        // Use the same date strategy as the transport on encode.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CrashReport.self, from: data)
        #expect(decoded.userDescription == "test")
    }
}
