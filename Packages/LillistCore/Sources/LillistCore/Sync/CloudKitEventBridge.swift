import Foundation
import CoreData

/// Lillist's internal mirror of `NSPersistentCloudKitContainer.Event`.
///
/// We mirror the upstream type so tests can construct and drive events
/// directly without depending on Apple's API surface (which is hard to
/// instantiate from outside Core Data).
public struct CloudKitSyncEvent: Sendable, Equatable {
    public enum EventType: Sendable, Equatable {
        case setup
        case `import`
        case export
    }
    public var type: EventType
    public var started: Bool
    public var endedAt: Date?
    public var error: LillistError?

    public init(type: EventType, started: Bool, endedAt: Date?, error: LillistError?) {
        self.type = type
        self.started = started
        self.endedAt = endedAt
        self.error = error
    }
}

/// Bridges `NSPersistentCloudKitContainer.eventChangedNotification` into a
/// testable async stream.
///
/// In production, `attach(to:)` registers a `NotificationCenter` observer
/// that translates Apple's events to `CloudKitSyncEvent`. In tests, callers
/// invoke `recordEvent(_:)` directly to drive the stream without touching
/// the notification center.
public actor CloudKitEventBridge {
    private var continuations: [UUID: AsyncStream<CloudKitSyncEvent>.Continuation] = [:]
    private var observerToken: NSObjectProtocol?

    public init() {}

    /// Stop listening for `eventChangedNotification`. Optional in production
    /// (the `[weak self]` in the observer closure makes a stale token a
    /// no-op once the actor deallocates), but tests can call it explicitly
    /// to make cleanup deterministic.
    public func detach() {
        if let token = observerToken {
            NotificationCenter.default.removeObserver(token)
            observerToken = nil
        }
    }

    public var eventStream: AsyncStream<CloudKitSyncEvent> {
        AsyncStream { continuation in
            let id = UUID()
            // The builder closure runs synchronously on this actor's
            // executor (the getter is actor-isolated and Swift 6
            // isolation inference carries that into the closure), so
            // `register` is a direct same-actor call. Calling it
            // synchronously here — rather than deferring via Task —
            // guarantees the continuation is in `continuations` before
            // the stream is returned, closing the pre-subscription
            // drop race documented in .rca/sync-status-monitor-event-drop/.
            //
            // The `onTermination` closure below IS @Sendable and does
            // not inherit isolation, so its Task with `await` is genuine.
            self.register(id: id, continuation: continuation)
            continuation.onTermination = { _ in
                Task { await self.unregister(id: id) }
            }
        }
    }

    /// Test seam — drive an event directly without involving NotificationCenter.
    public func recordEvent(_ event: CloudKitSyncEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    /// Production seam — register a NotificationCenter observer that
    /// converts `NSPersistentCloudKitContainer.Event` to `CloudKitSyncEvent`.
    public func attach(to container: NSPersistentCloudKitContainer) {
        let name = NSPersistentCloudKitContainer.eventChangedNotification
        let token = NotificationCenter.default.addObserver(forName: name, object: container, queue: nil) { [weak self] notification in
            guard let self else { return }
            guard let ckEvent = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
            let translated = Self.translate(ckEvent)
            Task { await self.recordEvent(translated) }
        }
        // `setObserverToken` is a same-actor call inside actor-isolated
        // `attach(to:)`. Calling it synchronously (instead of inside a
        // Task) guarantees the token is recorded before this method
        // returns, so a caller that calls `detach()` immediately after
        // `attach(to:)` cannot race past a deferred write and leak the
        // observer.
        self.setObserverToken(token)
    }

    private func setObserverToken(_ token: NSObjectProtocol) {
        observerToken = token
    }

    private func register(id: UUID, continuation: AsyncStream<CloudKitSyncEvent>.Continuation) {
        continuations[id] = continuation
    }

    private func unregister(id: UUID) {
        continuations[id] = nil
    }

    static func translate(_ event: NSPersistentCloudKitContainer.Event) -> CloudKitSyncEvent {
        let type: CloudKitSyncEvent.EventType
        switch event.type {
        case .setup: type = .setup
        case .import: type = .import
        case .export: type = .export
        @unknown default: type = .setup
        }
        let started = event.endDate == nil
        let mapped: LillistError? = event.error.map { CloudKitErrorClassifier.classify($0) }
        return CloudKitSyncEvent(type: type, started: started, endedAt: event.endDate, error: mapped)
    }
}
