import Foundation

// Experiment 2: Does AsyncStream's builder closure inherit actor isolation?
// If the enclosing computed property is actor-isolated, can the closure call
// `self.register(...)` synchronously without a Task wrapper?

actor BridgeA {
    private var continuations: [UUID: AsyncStream<Int>.Continuation] = [:]

    // Attempt 1: directly call self.register inside builder closure
    var eventStream: AsyncStream<Int> {
        AsyncStream { continuation in
            let id = UUID()
            self.register(id: id, continuation: continuation)
        }
    }

    private func register(id: UUID, continuation: AsyncStream<Int>.Continuation) {
        continuations[id] = continuation
    }
}
