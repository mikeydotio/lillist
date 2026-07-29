import Testing
import Foundation
@testable import LillistCore

@Suite("DestructiveOpGate (S11)")
struct DestructiveOpGateTests {
    @Test("An unheld gate acquires cleanly and records the owner")
    @MainActor
    func acquireWhenFree() throws {
        let gate = DestructiveOpGate()
        #expect(gate.currentOwner == nil)
        try gate.acquire(for: .migration(.disableNow))
        #expect(gate.currentOwner == .migration(.disableNow))
    }

    @Test("A second acquire while held throws, naming both operations")
    @MainActor
    func acquireWhileHeldThrows() throws {
        let gate = DestructiveOpGate()
        try gate.acquire(for: .reset("resetAndRedownload"))
        do {
            try gate.acquire(for: .migration(.disableNow))
            Issue.record("expected acquire to throw while held")
        } catch let error as LillistError {
            guard case .storeUnavailable(let reason) = error else {
                Issue.record("unexpected error case \(error)")
                return
            }
            #expect(reason.contains("disableNow"))
            #expect(reason.contains("resetAndRedownload"))
        }
        // The gate is still held by the original owner — a rejected
        // acquire must not clobber it.
        #expect(gate.currentOwner == .reset("resetAndRedownload"))
    }

    @Test("Release clears the owner and lets a new acquire succeed")
    @MainActor
    func releaseThenReacquire() throws {
        let gate = DestructiveOpGate()
        try gate.acquire(for: .restore)
        gate.release()
        #expect(gate.currentOwner == nil)
        try gate.acquire(for: .migration(.replaceLocalWithICloud))
        #expect(gate.currentOwner == .migration(.replaceLocalWithICloud))
    }

    @Test("Release on an already-free gate is a harmless no-op")
    @MainActor
    func releaseWhenFreeIsNoop() {
        let gate = DestructiveOpGate()
        gate.release()
        #expect(gate.currentOwner == nil)
    }

    @Test("Owner descriptions name the operation for diagnosable errors")
    @MainActor
    func ownerDescriptions() {
        #expect(DestructiveOpGate.Owner.migration(.replaceICloudWithLocal).description.contains("replaceICloudWithLocal"))
        #expect(DestructiveOpGate.Owner.reset("resetEverywhereToEmpty").description.contains("resetEverywhereToEmpty"))
        #expect(DestructiveOpGate.Owner.restore.description.contains("restore"))
    }

    @Test("acquire/release pairs cleanly via defer even when the body throws")
    @MainActor
    func deferredReleaseRunsOnThrow() throws {
        let gate = DestructiveOpGate()
        struct BodyFailure: Error {}

        func runGuarded(as owner: DestructiveOpGate.Owner, thenThrow: Bool) throws {
            try gate.acquire(for: owner)
            defer { gate.release() }
            if thenThrow { throw BodyFailure() }
        }

        #expect(throws: BodyFailure.self) {
            try runGuarded(as: .migration(.disableNow), thenThrow: true)
        }
        // The defer released the gate even though the body threw — a
        // fresh acquire must succeed immediately, not see a leaked owner.
        #expect(gate.currentOwner == nil)
        try runGuarded(as: .reset("resetAllData"), thenThrow: false)
        #expect(gate.currentOwner == nil)
    }
}
