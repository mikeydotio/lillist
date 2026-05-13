import Testing
import Foundation
@testable import LillistCore

@Suite("CloudKitEventBridge")
struct CloudKitEventBridgeTests {
    @Test("Recorded events appear on the stream in order")
    func eventsStream() async throws {
        let bridge = CloudKitEventBridge()
        var iterator = await bridge.eventStream.makeAsyncIterator()
        // Give the registration task a chance to run before recording.
        await Task.yield()
        await Task.yield()

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
        await Task.yield()
        await Task.yield()

        await bridge.recordEvent(.init(type: .export, started: true, endedAt: nil, error: nil))
        #expect(await aIter.next()?.type == .export)
        #expect(await bIter.next()?.type == .export)
    }
}
