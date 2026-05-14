import Testing
import Foundation
@testable import LillistCore

@Suite("BreadcrumbBuffer")
struct BreadcrumbBufferTests {
    @Test("Empty buffer snapshot is empty")
    func empty_snapshotEmpty() async {
        let buffer = BreadcrumbBuffer()
        let snap = await buffer.snapshot()
        #expect(snap.isEmpty)
    }

    @Test("Recording a breadcrumb appends it")
    func record_appends() async throws {
        let buffer = BreadcrumbBuffer()
        try await buffer.record(action: "task.create", success: true)
        let snap = await buffer.snapshot()
        #expect(snap.count == 1)
        #expect(snap.first?.action == "task.create")
        #expect(snap.first?.success == true)
    }

    @Test("Capacity is 200; the 201st record evicts the first")
    func capacity_evictsOldest() async throws {
        let buffer = BreadcrumbBuffer()
        for i in 0..<201 {
            try await buffer.record(action: "step.\(i)", success: true)
        }
        let snap = await buffer.snapshot()
        #expect(snap.count == 200)
        #expect(snap.first?.action == "step.1")
        #expect(snap.last?.action == "step.200")
    }

    @Test("Rejects breadcrumb containing a UUID")
    func rejects_uuidInAction() async {
        let buffer = BreadcrumbBuffer()
        await #expect(throws: BreadcrumbBuffer.RecordError.self) {
            try await buffer.record(
                action: "task.create 12345678-1234-1234-1234-1234567890AB",
                success: true
            )
        }
    }

    @Test("Rejects breadcrumb containing an email")
    func rejects_emailInAction() async {
        let buffer = BreadcrumbBuffer()
        await #expect(throws: BreadcrumbBuffer.RecordError.self) {
            try await buffer.record(action: "user mikeyward@gmail.com", success: true)
        }
    }

    @Test("Rejects breadcrumb containing a path-like substring")
    func rejects_pathInAction() async {
        let buffer = BreadcrumbBuffer()
        await #expect(throws: BreadcrumbBuffer.RecordError.self) {
            try await buffer.record(action: "loaded /Users/mikey/file", success: true)
        }
    }

    @Test("Snapshot returns immutable copy; subsequent records do not mutate it")
    func snapshot_isImmutable() async throws {
        let buffer = BreadcrumbBuffer()
        try await buffer.record(action: "a", success: true)
        let snap = await buffer.snapshot()
        try await buffer.record(action: "b", success: true)
        #expect(snap.count == 1)
    }
}
