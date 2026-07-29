import Testing
@testable import LillistCore

@Suite("DrainGate")
struct DrainGateTests {
    @Test("The first tryAcquire wins and becomes the owning drainer")
    func firstAcquireWins() async {
        let gate = DrainGate()
        #expect(await gate.tryAcquire() == true)
    }

    @Test("A second tryAcquire while draining fails and requests a coalesced rerun")
    func secondAcquireWhileDrainingFails() async {
        let gate = DrainGate()
        #expect(await gate.tryAcquire() == true)
        #expect(await gate.tryAcquire() == false, "a drain is already in flight — must not acquire concurrently")
    }

    @Test("finishOrRerun reports a pending rerun exactly once, then reports none")
    func finishOrRerunConsumesTheRerunFlagOnce() async {
        let gate = DrainGate()
        _ = await gate.tryAcquire()
        _ = await gate.tryAcquire()   // requests a rerun
        #expect(await gate.finishOrRerun() == true, "a request arrived mid-drain — the owner must sweep again")
        #expect(await gate.finishOrRerun() == false, "no further request arrived — the gate must release")
    }

    @Test("finishOrRerun with no pending request releases the gate immediately")
    func finishOrRerunWithNoRequestReleases() async {
        let gate = DrainGate()
        _ = await gate.tryAcquire()
        #expect(await gate.finishOrRerun() == false)
        // The gate is released — a fresh caller can now become the owner.
        #expect(await gate.tryAcquire() == true)
    }

    @Test("After a full acquire/finish cycle, a new drain can be acquired again")
    func gateIsReusableAcrossCycles() async {
        let gate = DrainGate()
        _ = await gate.tryAcquire()
        _ = await gate.finishOrRerun()
        #expect(await gate.tryAcquire() == true)
        #expect(await gate.tryAcquire() == false)
        _ = await gate.finishOrRerun()
    }

    @Test("Many concurrent tryAcquire calls yield exactly one owner and coalesce every other caller into a single rerun")
    func concurrentAcquiresYieldExactlyOneOwner() async {
        let gate = DrainGate()

        // Fire many concurrent tryAcquire calls before anyone finishes —
        // actor isolation serializes the calls themselves, but their
        // ARRIVAL order relative to each other is not fixed. Exactly one
        // must observe `true`; every other caller observes `false` and, per
        // the actor's own serialization, coalesces into the same single
        // pending rerun (finishOrRerun consumes it exactly once, proven
        // above) rather than requesting one rerun per failed caller.
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0..<50 { group.addTask { await gate.tryAcquire() } }
            var out: [Bool] = []
            for await result in group { out.append(result) }
            return out
        }

        #expect(results.filter { $0 }.count == 1, "exactly one caller must become the owning drainer")
        #expect(results.filter { !$0 }.count == 49)

        // The coalesced rerun collapses to exactly one extra pass, not 49.
        #expect(await gate.finishOrRerun() == true, "at least one late caller's request must be honored with a rerun")
        #expect(await gate.finishOrRerun() == false, "the coalesced rerun must not itself fan out into more reruns")
    }
}
