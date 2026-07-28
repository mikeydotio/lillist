import Foundation

/// Runs a possibly-hanging synchronous closure on a background thread and
/// returns `nil` if it doesn't complete within `timeout`.
///
/// The H7 cycle-guard regression tests exercise genuine infinite loops (a
/// pre-existing ancestor/descendant cycle that an unguarded walk spins on
/// forever). `Task` cancellation cannot preempt that — the loop never
/// suspends — so a `withTimeout`-style `async` race is not a real bound.
/// `DispatchSemaphore.wait(timeout:)` is: it returns `.timedOut` on the
/// calling thread regardless of what the background thread is doing. A
/// still-hung background thread is abandoned, not joined; it is reclaimed
/// when the test process exits.
enum HangGuard {
    static func run<T: Sendable>(timeout: TimeInterval = 3, _ work: @escaping @Sendable () -> T) -> T? {
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: T?
        let thread = Thread {
            result = work()
            semaphore.signal()
        }
        thread.start()
        guard semaphore.wait(timeout: .now() + timeout) == .success else { return nil }
        return result
    }
}
