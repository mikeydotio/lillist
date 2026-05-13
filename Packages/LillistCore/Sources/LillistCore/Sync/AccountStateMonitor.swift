import Foundation
import CloudKit

/// Testable seam around `CKContainer.accountStatus(_:)`.
public protocol AccountStatusProviding: Sendable {
    func accountStatus() async throws -> CKAccountStatus
}

/// Production implementation that asks the real `CKContainer`.
public struct CloudKitAccountStatusProvider: AccountStatusProviding {
    public let container: CKContainer
    public init(container: CKContainer) { self.container = container }
    public func accountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }
}

/// Observes the iCloud account state and publishes changes (design Section 8).
///
/// The monitor is an actor so concurrent observers can subscribe to the
/// stream without races. It depends on an `AccountStatusProviding` so tests
/// can inject controlled values without touching real CloudKit.
public actor AccountStateMonitor {
    public private(set) var currentState: iCloudAccountState = .noAccount

    private let provider: AccountStatusProviding
    private var continuations: [UUID: AsyncStream<iCloudAccountState>.Continuation] = [:]

    public init(provider: AccountStatusProviding) {
        self.provider = provider
    }

    /// Fetches the current `CKAccountStatus`, maps it to `iCloudAccountState`,
    /// updates `currentState`, and notifies stream subscribers.
    public func refresh() async throws {
        let status = try await provider.accountStatus()
        let mapped = iCloudAccountState.from(ckAccountStatus: status)
        publish(mapped)
    }

    /// Called from the `CKAccountChanged` notification handler — sets the
    /// state to `.accountChanged` regardless of the underlying status, since
    /// the app's quarantine flow needs explicit confirmation before
    /// continuing.
    public func simulateAccountChange() {
        publish(.accountChanged)
    }

    /// An async stream of state changes. Each call returns a fresh stream
    /// scoped to its caller; closing the stream removes the continuation.
    public var stateStream: AsyncStream<iCloudAccountState> {
        AsyncStream { continuation in
            let id = UUID()
            // Outer Task inherits this actor's isolation, so the call is
            // same-actor and synchronous — no `await` needed. The Task
            // inside `onTermination` (a @Sendable closure) does NOT inherit
            // isolation and must keep its `await`.
            Task { self.register(id: id, continuation: continuation) }
            continuation.onTermination = { _ in
                Task { await self.unregister(id: id) }
            }
        }
    }

    private func register(id: UUID, continuation: AsyncStream<iCloudAccountState>.Continuation) {
        continuations[id] = continuation
        // Replay the latest known state so late subscribers see it immediately.
        continuation.yield(currentState)
    }

    private func unregister(id: UUID) {
        continuations[id] = nil
    }

    private func publish(_ state: iCloudAccountState) {
        currentState = state
        for continuation in continuations.values {
            continuation.yield(state)
        }
    }
}
