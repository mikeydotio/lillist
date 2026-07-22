import Foundation

/// Watches `ControlInbox` for reset events addressed to this device and
/// applies them (issue #71).
///
/// Wired the same way `RemoteChangeReconciler`/`TaskDuplicateReconciler`
/// are: `start()` registers a `NotificationCenter` observer whose
/// closure spawns a `Task` to do the (potentially `@MainActor`-hopping)
/// work. `apply` is typed as a plain `@Sendable async throws` closure —
/// production wires it to `DataStoreResetService.resetAndRedownload()`,
/// whose own `@MainActor` isolation makes `await`ing it from here hop
/// automatically, no extra annotation needed here.
///
/// ## Apply/acknowledge ordering (crash safety)
///
/// For each pending event: **apply → durably record locally applied →
/// delete the inbox entry.** If the app dies between "apply" and
/// "delete," the next launch sees the entry still present, finds the ID
/// already recorded in `AppliedEventStore`, and just retries the
/// harmless delete — never a duplicate reset. Reversing this order
/// (deleting before recording) would risk the opposite failure: a crash
/// after delete but before recording loses the "already applied" memory
/// — harmless in isolation (the entry's gone either way) but loses the
/// efficiency benefit `AppliedEventStore` exists for.
///
/// `@unchecked Sendable`: the only mutable state (`observer`,
/// `isApplying`) is touched from `start()`/`stop()`/`checkAndApply()`,
/// which production always calls from the main actor
/// (`AppEnvironment.bootstrap()` and the observer's spawned `Task`).
public final class ResetSignalMonitor: @unchecked Sendable {
    private let inbox: ControlInbox
    private let applied: AppliedEventStore
    private let deviceID: String
    private let breadcrumbs: BreadcrumbBuffer?
    private let apply: @Sendable (ResetControlEvent) async throws -> Void

    private var isApplying = false
    private var observer: NSObjectProtocol?

    /// - Parameters:
    ///   - deviceID: this device's stable identifier (`DeviceFingerprint.current()`
    ///     in production).
    ///   - apply: called once per new pending event; production wires
    ///     this to `DataStoreResetService.resetAndRedownload()`. Kept as
    ///     an injected closure (rather than a hard dependency on
    ///     `DataStoreResetService`) to avoid a reference cycle — the
    ///     service is what constructs and starts this monitor.
    public init(
        inbox: ControlInbox,
        applied: AppliedEventStore,
        deviceID: String,
        breadcrumbs: BreadcrumbBuffer? = nil,
        apply: @escaping @Sendable (ResetControlEvent) async throws -> Void
    ) {
        self.inbox = inbox
        self.applied = applied
        self.deviceID = deviceID
        self.breadcrumbs = breadcrumbs
        self.apply = apply
    }

    /// Begin observing `NSUbiquitousKeyValueStore.didChangeExternallyNotification`.
    /// Call once at bootstrap, after an initial `checkAndApply()` catch-up
    /// pass for events that arrived while the app was closed.
    public func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.checkAndApply() }
        }
    }

    /// Stop observing. Optional in production (`[weak self]` makes a
    /// stale token a no-op), but lets tests/teardown be deterministic.
    public func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    deinit { stop() }

    /// Scan for events addressed to this device, apply each one not
    /// already recorded as applied, then acknowledge it. Reentrancy-
    /// guarded — a second tick while one is running is a no-op; the
    /// next notification or launch catch-up picks up anything left
    /// pending. Public so the app can also call it once at launch
    /// (catch-up for events that arrived while not running).
    public func checkAndApply() async {
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }

        for event in inbox.pendingEvents(for: deviceID) {
            if applied.hasApplied(event.id) {
                // Crash-recovery retry: already applied, just finish the ack.
                inbox.acknowledge(eventID: event.id, recipient: deviceID)
                continue
            }
            do {
                try await apply(event)
                applied.markApplied(event.id)
                inbox.acknowledge(eventID: event.id, recipient: deviceID)
                await breadcrumb(
                    "applied reset event \(event.id) from \(event.senderDisplayName)"
                )
            } catch {
                // Leave it pending (not marked applied, not acknowledged) —
                // the next tick retries rather than silently dropping a
                // real failure.
                await breadcrumb(
                    "failed to apply reset event \(event.id): \(error.localizedDescription)",
                    success: false
                )
            }
        }
    }

    private func breadcrumb(_ action: String, success: Bool = true) async {
        guard let breadcrumbs else { return }
        try? await breadcrumbs.record(action: action, success: success)
    }
}
