import Foundation

// Experiment 1: Can AsyncStream.continuation.yield(...) called BEFORE any
// subscriber/iterator runs be received by a late iterator? Does the unbounded
// buffer hold pre-subscription yields?

func run() async {
    print("--- Test A: yield inside builder synchronously, then iterate ---")
    let stream = AsyncStream<Int> { continuation in
        continuation.yield(1)
        continuation.yield(2)
        continuation.yield(3)
        // do NOT finish — keep stream open
    }
    var iter = stream.makeAsyncIterator()
    if let v1 = await iter.next() { print("got v1: \(v1)") }
    if let v2 = await iter.next() { print("got v2: \(v2)") }
    if let v3 = await iter.next() { print("got v3: \(v3)") }
    print("done test A")

    print("--- Test B: yield from a Task spawned in builder, then iterate ---")
    let stream2 = AsyncStream<Int> { continuation in
        Task {
            continuation.yield(10)
            continuation.yield(20)
        }
    }
    for _ in 0..<5 { await Task.yield() }
    var iter2 = stream2.makeAsyncIterator()
    if let v = await iter2.next() { print("got: \(v)") } else { print("got nil") }
    if let v = await iter2.next() { print("got: \(v)") } else { print("got nil") }
    print("done test B")

    print("--- Test C: capture continuation, yield after, iterate ---")
    let stream3 = AsyncStream<Int> { continuation in
        Holder.shared.cont = continuation
    }
    Holder.shared.cont?.yield(100)
    Holder.shared.cont?.yield(200)
    var iter3 = stream3.makeAsyncIterator()
    if let v = await iter3.next() { print("got: \(v)") } else { print("got nil") }
    if let v = await iter3.next() { print("got: \(v)") } else { print("got nil") }
    print("done test C")

    print("--- Test D: BRIDGE SHAPE — defer register via Task, recordEvent runs before register ---")
    // Mimic the bridge: continuation gets stored inside an actor-state dictionary
    // by a deferred Task. recordEvent iterates the dict; if empty, no yield.
    let bridge = Bridge()
    let s4 = await bridge.eventStream
    // intentionally do NOT yield to let register Task run
    await bridge.recordEvent(999)
    // now allow register Task to run
    for _ in 0..<10 { await Task.yield() }
    // ALSO record another event AFTER registration
    await bridge.recordEvent(888)
    var iter4 = s4.makeAsyncIterator()
    // Race: was 999 dropped? Was 888 received?
    if let v = await iter4.next() { print("first event: \(v)") }
    print("done test D")
}

final class Holder: @unchecked Sendable {
    static let shared = Holder()
    var cont: AsyncStream<Int>.Continuation?
}

actor Bridge {
    private var continuations: [UUID: AsyncStream<Int>.Continuation] = [:]

    var eventStream: AsyncStream<Int> {
        AsyncStream { continuation in
            let id = UUID()
            Task { self.register(id: id, continuation: continuation) }
        }
    }

    func recordEvent(_ event: Int) {
        for c in continuations.values { c.yield(event) }
        print("  recordEvent(\(event)) saw \(continuations.count) continuation(s)")
    }

    private func register(id: UUID, continuation: AsyncStream<Int>.Continuation) {
        continuations[id] = continuation
        print("  register ran")
    }
}

let sem = DispatchSemaphore(value: 0)
Task {
    await run()
    sem.signal()
}
sem.wait()
