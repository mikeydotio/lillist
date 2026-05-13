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
            Task { await self.register(id: id, continuation: continuation) }
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
        Task { await self.setObserverToken(token) }
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
        let mapped: LillistError? = event.error.map { LillistError.syncFailure(underlying: ($0 as NSError).localizedDescription) }
        return CloudKitSyncEvent(type: type, started: started, endedAt: event.endDate, error: mapped)
    }
}
