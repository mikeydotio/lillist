import Foundation

// Experiment 7: attach(to:) production race.
// Could removing Task { setObserverToken(token) } break anything?
//
// CURRENT:
//   Task { self.setObserverToken(token) }
// PROPOSED:
//   self.setObserverToken(token)   // direct call inside actor-isolated method
//
// Since attach(to:) IS actor-isolated on the bridge, a direct call to
// setObserverToken (also actor-isolated) is fine. The only nuance: in CURRENT
// design, the NotificationCenter observer closure can already fire (it's a
// @Sendable closure registered with NotificationCenter synchronously on line
// 75 BEFORE we even reach line 84). That observer closure does:
//   Task { await self.recordEvent(translated) }
// If a notification fires between line 75 and the recordEvent Task being
// scheduled/run, the recordEvent Task awaits the bridge actor's reentrancy
// queue. It will run when the bridge is next available.
//
// In CURRENT design, attach(to:) returns when the synchronous body (lines
// 73-85) finishes. setObserverToken Task is enqueued but may run later.
// In PROPOSED design, setObserverToken would run inline before attach
// returns. No semantic difference for the observer firing — that observer
// is live the moment addObserver returns.
//
// Conclusion: dropping Task { setObserverToken } is safe. The Task wrapper
// is purely deferring a same-actor synchronous call.

actor BridgeProposed {
    private var observerToken: NSObjectProtocol?
    private var continuations: [UUID: AsyncStream<Int>.Continuation] = [:]

    var eventStream: AsyncStream<Int> {
        AsyncStream { continuation in
            let id = UUID()
            // direct sync call — works because the closure body is inside
            // an actor-isolated computed property getter
            self.register(id: id, continuation: continuation)
        }
    }

    func attach() {
        // simulate NSPersistentCloudKitContainer notification setup
        // simulate: get a token
        let token: NSObjectProtocol = NSObject() as NSObjectProtocol
        // PROPOSED: direct call
        self.setObserverToken(token)
        print("attach returned; observerToken set: \(observerToken != nil)")
    }

    func detach() {
        if observerToken != nil {
            observerToken = nil
            print("detach removed observer")
        }
    }

    func recordEvent(_ e: Int) {
        for c in continuations.values { c.yield(e) }
    }

    private func register(id: UUID, continuation: AsyncStream<Int>.Continuation) {
        continuations[id] = continuation
    }

    private func setObserverToken(_ t: NSObjectProtocol) {
        observerToken = t
    }
}

func run() async {
    let b = BridgeProposed()
    await b.attach()
    await b.detach()
    print("done")
}

let sem = DispatchSemaphore(value: 0)
Task { await run(); sem.signal() }
sem.wait()
