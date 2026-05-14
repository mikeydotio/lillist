import Foundation

// Experiment 9: Compare CURRENT (Task { register }) vs PROPOSED (sync register)
// under cooperative-pool contention.

actor BridgeCurrent {
    private var continuations: [UUID: AsyncStream<Int>.Continuation] = [:]
    var eventStream: AsyncStream<Int> {
        AsyncStream { continuation in
            let id = UUID()
            Task { self.register(id: id, continuation: continuation) }
        }
    }
    func recordEvent(_ ev: Int) {
        for c in continuations.values { c.yield(ev) }
    }
    private func register(id: UUID, continuation: AsyncStream<Int>.Continuation) {
        continuations[id] = continuation
    }
}

actor BridgeSync {
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

actor Monitor<B> {
    var current: Int = 0
    private var task: Task<Void, Never>?
    func start(stream: AsyncStream<Int>) {
        task = Task { [weak self] in
            for await ev in stream { await self?.apply(ev) }
        }
    }
    private func apply(_ ev: Int) { current = ev }
}

func runCurrent(under loadTasks: Int) async -> Int {
    var fails = 0
    let trials = 500
    // Spin background tasks to contend cooperative pool
    let load = (0..<loadTasks).map { _ in Task.detached(priority: .background) {
        while !Task.isCancelled {
            await Task.yield()
        }
    } }
    for _ in 0..<trials {
        let b = BridgeCurrent()
        let m = Monitor<BridgeCurrent>()
        let s = await b.eventStream
        await m.start(stream: s)
        for _ in 0..<5 { await Task.yield() }
        await b.recordEvent(1)
        for _ in 0..<5 { await Task.yield() }
        await b.recordEvent(2)
        for _ in 0..<5 { await Task.yield() }
        let v = await m.current
        if v != 2 { fails += 1 }
    }
    for t in load { t.cancel() }
    return fails
}

func runSync(under loadTasks: Int) async -> Int {
    var fails = 0
    let trials = 500
    let load = (0..<loadTasks).map { _ in Task.detached(priority: .background) {
        while !Task.isCancelled {
            await Task.yield()
        }
    } }
    for _ in 0..<trials {
        let b = BridgeSync()
        let m = Monitor<BridgeSync>()
        let s = await b.eventStream
        await m.start(stream: s)
        for _ in 0..<5 { await Task.yield() }
        await b.recordEvent(1)
        for _ in 0..<5 { await Task.yield() }
        await b.recordEvent(2)
        for _ in 0..<5 { await Task.yield() }
        let v = await m.current
        if v != 2 { fails += 1 }
    }
    for t in load { t.cancel() }
    return fails
}

func run() async {
    print("=== no load ===")
    print("CURRENT fails: \(await runCurrent(under: 0)) / 500")
    print("SYNC    fails: \(await runSync(under: 0)) / 500")
    print("=== load=8 ===")
    print("CURRENT fails: \(await runCurrent(under: 8)) / 500")
    print("SYNC    fails: \(await runSync(under: 8)) / 500")
    print("=== load=32 ===")
    print("CURRENT fails: \(await runCurrent(under: 32)) / 500")
    print("SYNC    fails: \(await runSync(under: 32)) / 500")
}

let sem = DispatchSemaphore(value: 0)
Task { await run(); sem.signal() }
sem.wait()
