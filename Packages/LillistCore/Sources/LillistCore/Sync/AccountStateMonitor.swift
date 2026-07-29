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
    /// Data-sync-hardening `S3`: optional identity comparison consulted on
    /// every `refresh()` when the base `CKAccountStatus` maps to
    /// `.available`. `nil` preserves the exact pre-`S3` behavior (every
    /// existing single-argument `init(provider:)` call site, including
    /// every earlier test in this file, is unaffected). This is what makes
    /// `.accountChanged` reachable in production for the first time — see
    /// the plan doc `2026-07-28-plan-3a-account-identity-and-status.md`.
    private let identityStore: AccountIdentityStore?
    private var continuations: [UUID: AsyncStream<iCloudAccountState>.Continuation] = [:]
    /// `S13`: token for the `CKAccountChanged` NotificationCenter observer.
    /// `nil` when not currently observing.
    private var systemObserverToken: NSObjectProtocol?

    public init(provider: AccountStatusProviding, identityStore: AccountIdentityStore? = nil) {
        self.provider = provider
        self.identityStore = identityStore
    }

    /// Fetches the current `CKAccountStatus`, maps it to `iCloudAccountState`,
    /// overrides to `.accountChanged` when an injected `identityStore`
    /// detects a real mismatch (`S3`), updates `currentState`, and notifies
    /// stream subscribers.
    ///
    /// The identity check only runs when the base status is `.available` —
    /// a genuinely signed-out or restricted device must never be promoted
    /// to `.accountChanged` by a stale stored identity; `.noAccount`/
    /// `.restricted` already have their own, correct pause-reason handling.
    /// A storage read failure inside `check()` is swallowed here (`try?`):
    /// this method feeds a *status display*, not the launch-time mirroring
    /// gate (`AppEnvironment.make()` calls `AccountIdentityStore.check()`
    /// directly and fails closed on a throw — see the plan doc §2):
    /// misreporting "your account changed" for what's actually a damaged
    /// cache file would be actively misleading.
    public func refresh() async throws {
        let status = try await provider.accountStatus()
        var mapped = iCloudAccountState.from(ckAccountStatus: status)
        if mapped == .available, let identityStore,
           let result = try? identityStore.check(), result == .mismatch {
            mapped = .accountChanged
        }
        publish(mapped)
    }

    /// `S13`: register a `NotificationCenter` observer for CloudKit's
    /// `CKAccountChanged` notification — posted whenever the device's
    /// iCloud account situation may have changed (sign in/out, account
    /// switch, restriction change). Calling `refresh()` in response is the
    /// documented reaction to this notification; combined with the
    /// `identityStore` override above, a mid-session account switch is now
    /// detected without waiting for the next cold launch. Idempotent — a
    /// second call while already observing is a no-op.
    public func startObservingSystemAccountChanges() {
        guard systemObserverToken == nil else { return }
        let token = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { try? await self.refresh() }
        }
        systemObserverToken = token
    }

    /// Stop observing `CKAccountChanged`. Optional in production (a stale
    /// token is a harmless no-op once the actor deallocates), but tests
    /// call it explicitly for deterministic cleanup — mirrors
    /// `CloudKitEventBridge.detach()`.
    public func stopObservingSystemAccountChanges() {
        if let token = systemObserverToken {
            NotificationCenter.default.removeObserver(token)
            systemObserverToken = nil
        }
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
            // Synchronous same-actor registration — see CloudKitEventBridge.eventStream
            // for the full rationale. Calling `register` directly (rather
            // than via Task) ensures the initial-replay yield inside
            // `register` lands before the getter returns, so the next
            // `iterator.next()` is guaranteed to receive it.
            self.register(id: id, continuation: continuation)
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
