import Testing
import Foundation
@testable import LillistCore

@Suite("BreadcrumbBuffer stress")
struct BreadcrumbBufferStressTests {
    /// Concurrently hammer the actor from many child tasks. The actor
    /// must serialize every `record` (no lost append, no over-count) and
    /// honor the 200-entry capacity. Run several outer repetitions so a
    /// rare interleaving has a chance to surface.
    @Test("Concurrent records never exceed capacity and never crash")
    func concurrentRecords_respectCapacity() async throws {
        for _ in 0..<20 {
            let buffer = BreadcrumbBuffer()
            await withThrowingTaskGroup(of: Void.self) { group in
                for i in 0..<1_000 {
                    group.addTask {
                        // Action strings are PII-clean verbs (no UUID,
                        // no "@", no "/") so record() never rejects.
                        try await buffer.record(action: "step.\(i)", success: i.isMultiple(of: 2))
                    }
                }
            }
            let snap = await buffer.snapshot()
            // 1_000 records into a 200-capacity ring: the buffer caps at
            // exactly 200 and never overflows or loses the invariant.
            #expect(snap.count == BreadcrumbBuffer.capacity)
        }
    }

    /// Records and snapshots interleaved concurrently. Each snapshot is a
    /// value copy, so it must never be larger than capacity regardless of
    /// when it is taken relative to the writers.
    @Test("Concurrent snapshots are always a bounded immutable copy")
    func concurrentSnapshots_bounded() async throws {
        let buffer = BreadcrumbBuffer()
        // `try` because the `for try await … in group` below makes this
        // trailing closure a throwing context, so the group call rethrows.
        try await withThrowingTaskGroup(of: Int.self) { group in
            for i in 0..<500 {
                group.addTask {
                    try await buffer.record(action: "w.\(i)", success: true)
                    return 0
                }
            }
            for _ in 0..<500 {
                group.addTask {
                    await buffer.snapshot().count
                }
            }
            for try await observed in group {
                #expect(observed <= BreadcrumbBuffer.capacity)
            }
        }
    }
}
