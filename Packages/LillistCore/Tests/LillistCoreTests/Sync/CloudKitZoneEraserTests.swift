import Testing
import Foundation
import CloudKit
@testable import LillistCore

/// In-memory fake. Records every call so `MigrationCoordinator`
/// tests can assert on order + arguments without round-tripping
/// CloudKit.
actor FakeCloudKitZoneEraser: CloudKitZoneEraser {
    private(set) var callCount: Int = 0
    private(set) var lastContainerID: String?
    var stubbedSummary: CloudKitEraseSummary = CloudKitEraseSummary(zoneIDs: [])

    func setStubbedSummary(_ summary: CloudKitEraseSummary) {
        stubbedSummary = summary
    }

    nonisolated func eraseManagedZones(
        in containerIdentifier: String,
        progress: @Sendable (Double) async -> Void
    ) async throws -> CloudKitEraseSummary {
        await record(containerID: containerIdentifier)
        await progress(0)
        await progress(1)
        return await stubbedSummary
    }

    private func record(containerID: String) {
        callCount += 1
        lastContainerID = containerID
    }
}

@Suite("CloudKitZoneEraser (fake)")
struct CloudKitZoneEraserFakeTests {
    @Test("Fake records calls and reports completion progress")
    func fakeRecordsCalls() async throws {
        let fake = FakeCloudKitZoneEraser()
        await fake.setStubbedSummary(CloudKitEraseSummary(zoneIDs: [CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)]))
        let progressCollector = ProgressCollector()
        let summary = try await fake.eraseManagedZones(in: "iCloud.test") { fraction in
            await progressCollector.append(fraction)
        }
        #expect(await fake.callCount == 1)
        #expect(await fake.lastContainerID == "iCloud.test")
        #expect(summary.zoneIDs.count == 1)
        #expect(await progressCollector.values == [0, 1])
    }
}

actor ProgressCollector {
    private(set) var values: [Double] = []
    func append(_ value: Double) { values.append(value) }
}

/// Plan 21 Wave 7 / Risk Register: live integration test guarded by
/// env vars. Skipped unless `LILLIST_CK_TEST_CONTAINER` is set; the
/// real container delete is destructive and must not run in CI.
@Suite("CloudKitZoneEraser (live)", .disabled(if: !shouldRunLiveCloudKitTests))
struct CloudKitZoneEraserLiveTests {
    @Test("Live deletion removes the managed zone")
    func liveDeleteRemovesZone() async throws {
        let containerID = ProcessInfo.processInfo.environment["LILLIST_CK_TEST_CONTAINER"]!
        let eraser = LiveCloudKitZoneEraser()
        _ = try await eraser.eraseManagedZones(in: containerID) { _ in }
    }
}

private var shouldRunLiveCloudKitTests: Bool {
    ProcessInfo.processInfo.environment["LILLIST_CK_TEST_CONTAINER"]?.isEmpty == false
}
