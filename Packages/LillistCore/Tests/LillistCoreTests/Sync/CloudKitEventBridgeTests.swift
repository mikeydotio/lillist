import Testing
import Foundation
@testable import LillistCore

@Suite("CloudKitEventBridge")
struct CloudKitEventBridgeTests {
    @Test("Recorded events appear on the stream in order")
    func eventsStream() async throws {
        let bridge = CloudKitEventBridge()
        var iterator = await bridge.eventStream.makeAsyncIterator()

        // No yields needed: continuation is registered synchronously in
        // the actor-isolated `eventStream` getter, so any event recorded
        // after the iterator is constructed is guaranteed to be yielded
        // into the stream's buffer.
        await bridge.recordEvent(.init(type: .setup, started: true, endedAt: nil, error: nil))
        let first = await iterator.next()
        #expect(first?.type == .setup)
        #expect(first?.started == true)

        await bridge.recordEvent(.init(type: .import, started: false, endedAt: Date(timeIntervalSince1970: 1_000_000), error: nil))
        let second = await iterator.next()
        #expect(second?.type == .import)
        #expect(second?.endedAt == Date(timeIntervalSince1970: 1_000_000))
    }

    @Test("Multiple subscribers each get all events independently")
    func fanOut() async throws {
        let bridge = CloudKitEventBridge()
        var aIter = await bridge.eventStream.makeAsyncIterator()
        var bIter = await bridge.eventStream.makeAsyncIterator()

        await bridge.recordEvent(.init(type: .export, started: true, endedAt: nil, error: nil))
        #expect(await aIter.next()?.type == .export)
        #expect(await bIter.next()?.type == .export)
    }

    @Test("Event recorded before any iterator next() is buffered until consumed")
    func preSubscriptionEventBuffering() async throws {
        // Race-A regression test. Pre-fix, this would have failed: the
        // bridge's deferred `Task { register }` meant `recordEvent` could
        // run with `continuations` empty and the event would be silently
        // dropped. Post-fix, the eventStream getter registers the
        // continuation synchronously, so this event MUST be delivered.
        let bridge = CloudKitEventBridge()
        var iterator = await bridge.eventStream.makeAsyncIterator()
        // Immediately record — no yields, no waiting. The continuation is
        // already in `continuations` because the getter is synchronous.
        await bridge.recordEvent(.init(type: .setup, started: true, endedAt: nil, error: nil))
        let event = await iterator.next()
        #expect(event?.type == .setup)
        #expect(event?.started == true)
    }
}
