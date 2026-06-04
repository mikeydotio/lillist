import Testing
import Foundation
@testable import LillistCore

/// N-concurrent-subscriber stress for `CloudKitEventBridge`'s fan-out
/// `AsyncStream`. Guards three real properties under contention:
///   1. every one of N concurrent subscribers receives every event in
///      order (no drops, no reordering) while events are produced
///      concurrently;
///   2. terminating a subscriber unregisters its continuation so later
///      `recordEvent` calls don't yield into a dead slot or leak it;
///   3. rapid subscribe/terminate churn never wedges or deadlocks the actor.
///
/// NOTE — what this does NOT test: it does not detect a regression that
/// reverts the synchronous continuation registration to a deferred
/// `Task { register }`. That "pre-subscription drop" (Race A in
/// `.rca/sync-status-monitor-event-drop/`) is a latent *production* hazard
/// on the NotificationCenter-driven path; via the `recordEvent` test seam
/// every `await` lets the deferred registration Task run first, so the drop
/// is masked by actor scheduling (verified: all tests pass against the
/// revert). Synchronous registration is held by the iterator-pattern design
/// + code review, not by an executing canary here. See engineering-notes.
@Suite("CloudKitEventBridge — concurrent subscribers", .serialized)
struct CloudKitEventBridgeConcurrentSubscriberTests {
    private static let subscriberCount = 12
    private static let eventsPerSubscriber = 20

    @Test("Every concurrent subscriber observes every event, in order, with no drops")
    func allSubscribersReceiveAllEventsInOrder() async throws {
        let bridge = CloudKitEventBridge()

        // Acquire N streams up front (synchronous registration puts every
        // continuation in place before the getter returns). Hold AsyncStream
        // values — they are Sendable; AsyncIterator is not, so each consuming
        // task makes its own iterator from its stream.
        var streams: [AsyncStream<CloudKitSyncEvent>] = []
        for _ in 0..<Self.subscriberCount {
            streams.append(await bridge.eventStream)
        }

        // endedAt doubles as a monotonic sequence marker so each subscriber
        // can assert it received the full sequence in order.
        let events: [CloudKitSyncEvent] = (0..<Self.eventsPerSubscriber).map { i in
            CloudKitSyncEvent(
                type: .import,
                started: false,
                endedAt: Date(timeIntervalSince1970: TimeInterval(i)),
                error: nil
            )
        }

        // Consume on N concurrent tasks while a producer Task fans the events
        // out concurrently — the contended fan-out this suite guards. The
        // unbounded buffer + synchronous registration guarantee no subscriber
        // drops or reorders an event.
        try await withThrowingTaskGroup(of: [Date].self) { group in
            for stream in streams {
                group.addTask {
                    var received: [Date] = []
                    var iterator = stream.makeAsyncIterator()
                    for _ in 0..<Self.eventsPerSubscriber {
                        guard let e = await iterator.next() else { break }
                        received.append(try #require(e.endedAt))
                    }
                    return received
                }
            }

            let producer = Task {
                for e in events { await bridge.recordEvent(e) }
            }
            await producer.value

            for try await received in group {
                let expected = events.map { $0.endedAt! }
                #expect(received == expected, "a subscriber dropped or reordered events: \(received)")
            }
        }
    }

    @Test("Terminating a subscriber unregisters it; survivors still receive every later event")
    func terminatedSubscriberDoesNotStarveSurvivors() async throws {
        let bridge = CloudKitEventBridge()

        // Two long-lived survivors that drain everything.
        var survivorA = await bridge.eventStream.makeAsyncIterator()
        var survivorB = await bridge.eventStream.makeAsyncIterator()

        // A transient subscriber that we drop after one event. Taking the
        // first event then letting the stream value deinit triggers the
        // continuation's onTermination → unregister(id:).
        do {
            var transient = await bridge.eventStream.makeAsyncIterator()
            await bridge.recordEvent(.init(type: .setup, started: true, endedAt: nil, error: nil))
            #expect(await transient.next()?.type == .setup)
            // Drain that first event on the survivors too so the buffers align.
            #expect(await survivorA.next()?.type == .setup)
            #expect(await survivorB.next()?.type == .setup)
            _ = transient // transient deinits at end of scope → onTermination fires
        }

        // Give the onTermination Task a happens-before barrier: yield through
        // the actor by recording + draining a marker event the survivors see.
        await bridge.recordEvent(.init(type: .export, started: true, endedAt: nil, error: nil))
        #expect(await survivorA.next()?.type == .export)
        #expect(await survivorB.next()?.type == .export)

        // Survivors must still receive a full burst with the transient gone.
        let burst: [CloudKitSyncEvent] = (0..<Self.eventsPerSubscriber).map { i in
            CloudKitSyncEvent(type: .import, started: false,
                              endedAt: Date(timeIntervalSince1970: TimeInterval(i)), error: nil)
        }
        for e in burst { await bridge.recordEvent(e) }

        for expected in burst {
            #expect(await survivorA.next()?.endedAt == expected.endedAt)
            #expect(await survivorB.next()?.endedAt == expected.endedAt)
        }
    }

    @Test("Subscribers attaching and detaching concurrently never crash or deadlock the actor")
    func churnedSubscribersStayConsistent() async throws {
        let bridge = CloudKitEventBridge()

        // One stable subscriber proves the actor stays live and ordered
        // through the churn.
        var stable = await bridge.eventStream.makeAsyncIterator()

        await withTaskGroup(of: Void.self) { group in
            // Churn: many short-lived subscribers attach, take one event, drop.
            for _ in 0..<Self.subscriberCount {
                group.addTask {
                    var it = await bridge.eventStream.makeAsyncIterator()
                    await bridge.recordEvent(.init(type: .setup, started: true, endedAt: nil, error: nil))
                    _ = await it.next()
                    // it deinits → unregister
                }
            }
            await group.waitForAll()
        }

        // The stable subscriber buffered every churn-driven event (unbounded
        // buffer). We don't assert an exact count — task interleaving makes it
        // nondeterministic — only that draining doesn't hang and the actor is
        // still usable for a final, deterministic event.
        await bridge.recordEvent(.init(type: .export, started: false,
                                       endedAt: Date(timeIntervalSince1970: 999), error: nil))
        // Drain until we reach the sentinel export event (or run dry).
        var sawSentinel = false
        for _ in 0..<(Self.subscriberCount + 2) {
            guard let e = await stable.next() else { break }
            if e.type == .export, e.endedAt == Date(timeIntervalSince1970: 999) {
                sawSentinel = true
                break
            }
        }
        #expect(sawSentinel, "stable subscriber never received the post-churn sentinel — actor wedged or dropped")
    }
}
