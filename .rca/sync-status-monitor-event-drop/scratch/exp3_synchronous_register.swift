import Foundation

// Experiment 3: With register called synchronously (no Task wrapper),
// does the pre-subscription drop disappear?

actor Bridge {
    private var continuations: [UUID: AsyncStream<Int>.Continuation] = [:]

    var eventStream: AsyncStream<Int> {
        AsyncStream { continuation in
            let id = UUID()
            // SYNCHRONOUS — no Task wrapper
            self.register(id: id, continuation: continuation)
        }
    }

    func recordEvent(_ event: Int) {
        for c in continuations.values { c.yield(event) }
        print("  recordEvent(\(event)) saw \(continuations.count) continuation(s)")
    }

    private func register(id: UUID, continuation: AsyncStream<Int>.Continuation) {
        continuations[id] = continuation
        print("  register ran SYNCHRONOUSLY in getter")
    }
}

func run() async {
    let bridge = Bridge()
    let stream = await bridge.eventStream
    // No yields. Immediately record an event.
    await bridge.recordEvent(999)
    await bridge.recordEvent(888)
    var iter = stream.makeAsyncIterator()
    if let v = await iter.next() { print("first event: \(v)") }
    if let v = await iter.next() { print("second event: \(v)") }
    print("done")
}

let sem = DispatchSemaphore(value: 0)
Task {
    await run()
    sem.signal()
}
sem.wait()
