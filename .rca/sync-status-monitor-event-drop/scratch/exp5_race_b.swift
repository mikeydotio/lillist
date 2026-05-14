import Foundation

// Experiment 5: Full pipeline race. After dropping Task { register }, is
// Race B (apply-vs-read) still observable when the test reads currentStatus
// after recordEvent + yields?

actor Bridge {
    private var continuations: [UUID: AsyncStream<Int>.Continuation] = [:]

    var eventStream: AsyncStream<Int> {
        AsyncStream { continuation in
            let id = UUID()
            // Synchronous register — no Task wrapper.
            self.register(id: id, continuation: continuation)
        }
    }

    func recordEvent(_ event: Int) {
        for c in continuations.values { c.yield(event) }
    }

    private func register(id: UUID, continuation: AsyncStream<Int>.Continuation) {
        continuations[id] = continuation
    }
}

actor Monitor {
    var current: Int = 0
    private let bridge: Bridge
    private var task: Task<Void, Never>?

    init(bridge: Bridge) { self.bridge = bridge }

    func start() async {
        let s = await bridge.eventStream
        task = Task { [weak self] in
            for await ev in s {
                await self?.apply(ev)
            }
        }
    }

    private func apply(_ ev: Int) {
        current = ev
    }
}

func run() async {
    var fails = 0
    let trials = 200
    for _ in 0..<trials {
        let b = Bridge()
        let m = Monitor(bridge: b)
        await m.start()
        for _ in 0..<5 { await Task.yield() }
        await b.recordEvent(1)
        for _ in 0..<5 { await Task.yield() }
        await b.recordEvent(2)
        for _ in 0..<5 { await Task.yield() }
        let v = await m.current
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
