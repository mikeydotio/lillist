import Foundation

// Experiment 6: Same race scenario, but using statusStream iterator.next()
// as the sync point instead of Task.yield + currentStatus read.

actor Bridge {
    private var continuations: [UUID: AsyncStream<Int>.Continuation] = [:]
    var eventStream: AsyncStream<Int> {
        AsyncStream { continuation in
            let id = UUID()
            self.register(id: id, continuation: continuation)
        }
    }
    func recordEvent(_ ev: Int) {
        for c in continuations.values { c.yield(ev) }
    }
    private func register(id: UUID, continuation: AsyncStream<Int>.Continuation) {
        continuations[id] = continuation
    }
}

actor Monitor {
    var current: Int = 0
    private let bridge: Bridge
    private var task: Task<Void, Never>?
    private var statusContinuations: [UUID: AsyncStream<Int>.Continuation] = [:]

    init(bridge: Bridge) { self.bridge = bridge }

    func start() async {
        let s = await bridge.eventStream
        task = Task { [weak self] in
            for await ev in s {
                await self?.apply(ev)
            }
        }
    }

    var statusStream: AsyncStream<Int> {
        AsyncStream { continuation in
            let id = UUID()
            self.registerStatus(id: id, continuation: continuation)
        }
    }

    private func registerStatus(id: UUID, continuation: AsyncStream<Int>.Continuation) {
        statusContinuations[id] = continuation
        continuation.yield(current)
    }

    private func apply(_ ev: Int) {
        current = ev
        for c in statusContinuations.values { c.yield(ev) }
    }
}

func run() async {
    var fails = 0
    let trials = 200
    for _ in 0..<trials {
        let b = Bridge()
        let m = Monitor(bridge: b)
        await m.start()
        var iter = await m.statusStream.makeAsyncIterator()
        _ = await iter.next()  // initial replay
        await b.recordEvent(1)
        _ = await iter.next()
        await b.recordEvent(2)
        let v = await iter.next() ?? -1
        if v != 2 { fails += 1 }
    }
    print("fails: \(fails) / \(trials)")
}

let sem = DispatchSemaphore(value: 0)
Task {
    await run()
    sem.signal()
}
sem.wait()
