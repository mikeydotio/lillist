import Foundation

// Experiment 4: Two tasks enqueue awaits on the same actor in clear order.
// Does the actor honor enqueue order?

actor M {
    var log: [String] = []
    func a() { log.append("a"); print("a ran") }
    func b() { log.append("b"); print("b ran") }
    func snapshot() -> [String] { log }
}

func run() async {
    // 1000 iterations to see if any reorder shows up.
    var reorders = 0
    for trial in 0..<1000 {
        let m = M()
        // Two distinct tasks. We want to enqueue them in a clear sequence.
        // We start task1, then immediately start task2, hoping task1's hop
        // enqueues first.
        let t1 = Task { await m.a() }
        let t2 = Task { await m.b() }
        _ = await t1.value
        _ = await t2.value
        let s = await m.snapshot()
        if s != ["a", "b"] {
            reorders += 1
            if reorders <= 3 {
                print("trial \(trial): \(s)")
            }
        }
    }
    print("reorders observed: \(reorders) / 1000")
}

let sem = DispatchSemaphore(value: 0)
Task {
    await run()
    sem.signal()
}
sem.wait()
