import Foundation

/// A `ResetControlEvent` this device auto-discarded without ever surfacing
/// it as a pending decision (data-sync-hardening `S10`) — informational,
/// so the UI can show a "why didn't I get asked?" note rather than the
/// event just silently vanishing.
public struct ResetEventDiscardNotice: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        /// `requestedAt` is older than `ResetSignalMonitor.expiryWindowDays`
        /// — a pure hygiene bound, not a safety mechanism (apply is always
        /// user-confirmed regardless of age).
        case expired
        /// This device is in `.localOnly` mode — there is no CloudKit
        /// connection to converge to, so applying would just throw
        /// immediately. Nothing to decide; nothing was lost by discarding.
        case notSyncing
    }

    public let event: ResetControlEvent
    public let reason: Reason
    public let discardedAt: Date

    public init(event: ResetControlEvent, reason: Reason, discardedAt: Date) {
        self.event = event
        self.reason = reason
        self.discardedAt = discardedAt
    }
}

/// Watches `ControlInbox` for reset events addressed to this device and
/// surfaces them as a pending decision the user must explicitly confirm
/// before anything is applied (issue #71; data-sync-hardening `S10`).
///
/// ## The always-prompt product decision
///
/// Remote reset events are **never** auto-applied, regardless of age.
/// `refreshPendingDecision()` — called at bootstrap catch-up and on every
/// live `NSUbiquitousKeyValueStore.didChangeExternallyNotification` — only
/// ever classifies and surfaces; the *only* path that ever invokes the
/// injected `apply` closure is `confirmApply()`, called exclusively from
/// explicit UI confirmation. See the plan doc
/// (`docs/superpowers/plans/2026-07-28-plan-3b-reset-propagation-safety.md`)
/// for the full state diagram.
///
/// Every event a scan pass finds resolves to exactly one of four terminal
/// fates:
/// - **pending** — decodable, not yet applied, within the expiry window,
///   and this device is currently `.iCloudSync` — surfaced via
///   `pendingDecision`/`pendingDecisionStream`.
/// - **expired** — `requestedAt` is older than
///   `ResetSignalMonitor.expiryWindowDays` (180 — data-sync-hardening `S10`
///   council decision, `.council/reset-event-expiry-window/DECISION.md`) —
///   acknowledged and discarded silently (a diagnostic breadcrumb only), a
///   pure hygiene bound since apply is always confirmed either way.
/// - **not syncing** — this device is `.localOnly`, so there is nothing to
///   converge to — acknowledged and discarded, surfaced via
///   `discardNotice`/`discardNoticeStream` so the UI can show a real
///   "why didn't I get asked" note rather than a silent drop.
/// - **dead-lettered** — undecodable payload — quarantined via
///   `ControlInbox.undecodableKeys(for:)`/`discardUndecodable(key:)` into a
///   `ResetEventDeadLetterStore` (data-sync-hardening `S22`) instead of
///   sitting in the KVS store forever with nothing to ever notice it.
///
/// "Decline" (the dialog's "Not Now" button) has **no dedicated method** —
/// it's purely a UI-local dismiss. The event stays un-acknowledged in
/// `ControlInbox`; the next scan re-evaluates it from scratch (expiry and
/// sync-mode are re-checked, nothing about "declined" is persisted). This
/// extends the `S3`-established precedent that a non-blocking resolution
/// dialog "must stay genuinely persistent... rather than silently
/// disappearing across launches."
///
/// ## Apply/acknowledge ordering (crash safety)
///
/// For each event `confirmApply()` applies: **apply → durably record
/// locally applied → delete the inbox entry.** If the app dies between
/// "apply" and "delete," the next launch's scan sees the entry still
/// present, finds the ID already recorded in `AppliedEventStore`, and just
/// retries the harmless delete — never a duplicate reset.
///
/// A single successful `apply` call satisfies **every** currently-pending
/// event, not just the one shown — they all resolve to the identical
/// "converge to current iCloud state" action regardless of which specific
/// event triggered it (see `ResetControlEvent.Kind`'s own doc comment), so
/// requiring N separate confirmations for N queued broadcasts would be
/// needless friction.
///
/// `actor`-isolated (data-sync-hardening `S22`: replaces the prior
/// `@unchecked Sendable` class with a hand-rolled, unsynchronized
/// `isApplying` bool touched from nonisolated `Task`s — a real race,
/// closed here by construction rather than by careful discipline).
public actor ResetSignalMonitor {
    /// Data-sync-hardening `S10` council decision — see this type's own
    /// header doc and `.council/reset-event-expiry-window/DECISION.md` for
    /// the full rationale. A pure hygiene bound: apply is always
    /// user-confirmed regardless of an event's age, so this cannot be
    /// tightened or loosened for safety reasons, only for "how stale is
    /// too stale to keep offering as a live decision."
    public static let expiryWindowDays = 180

    private let inbox: ControlInbox
    private let applied: AppliedEventStore
    private let deviceID: String
    private let breadcrumbs: BreadcrumbBuffer?
    private let apply: @Sendable (ResetControlEvent) async throws -> Void
    private let currentSyncMode: @Sendable () async -> SyncMode
    private let deadLetters: ResetEventDeadLetterStore?
    private let clock: @Sendable () -> Date

    private var observer: NSObjectProtocol?
    /// Every currently-decodable, not-yet-applied, not-expired,
    /// currently-actionable event addressed to this device, oldest first.
    /// `pendingDecision` is simply `actionablePending.first`.
    private var actionablePending: [ResetControlEvent] = []
    private var lastDiscardNotice: ResetEventDiscardNotice?
    private var pendingContinuations: [UUID: AsyncStream<ResetControlEvent?>.Continuation] = [:]
    private var noticeContinuations: [UUID: AsyncStream<ResetEventDiscardNotice?>.Continuation] = [:]

    /// - Parameters:
    ///   - deviceID: this device's stable identifier (`DeviceFingerprint.current()`
    ///     in production).
    ///   - currentSyncMode: this device's live sync mode, consulted once per
    ///     scan to decide whether an otherwise-actionable event can be
    ///     surfaced at all (data-sync-hardening `S10` — a `.localOnly`
    ///     device has nothing to converge to). Defaults to `{ .iCloudSync }`
    ///     (permissive — matches this program's `AccountStateProviding`
    ///     "unknown → proceed" convention) so every existing test/legacy
    ///     construction is unaffected.
    ///   - deadLetters: quarantine target for undecodable payloads
    ///     (data-sync-hardening `S22`). `nil` (the default) still discards
    ///     them from the live inbox — only the diagnostic copy is skipped.
    ///   - clock: injected for deterministic expiry-boundary testing.
    ///   - apply: called only from `confirmApply()`, never automatically.
    ///     Production wires this to `DataStoreResetService
    ///     .resetAndRedownload()`. Kept as an injected closure (rather than
    ///     a hard dependency on `DataStoreResetService`) to avoid a
    ///     reference cycle — the service is what constructs and starts this
    ///     monitor.
    public init(
        inbox: ControlInbox,
        applied: AppliedEventStore,
        deviceID: String,
        breadcrumbs: BreadcrumbBuffer? = nil,
        currentSyncMode: @escaping @Sendable () async -> SyncMode = { .iCloudSync },
        deadLetters: ResetEventDeadLetterStore? = nil,
        clock: @escaping @Sendable () -> Date = Date.init,
        apply: @escaping @Sendable (ResetControlEvent) async throws -> Void
    ) {
        self.inbox = inbox
        self.applied = applied
        self.deviceID = deviceID
        self.breadcrumbs = breadcrumbs
        self.currentSyncMode = currentSyncMode
        self.deadLetters = deadLetters
        self.clock = clock
        self.apply = apply
    }

    /// Begin observing `NSUbiquitousKeyValueStore.didChangeExternallyNotification`.
    /// Call once at bootstrap, after an initial `refreshPendingDecision()`
    /// catch-up pass for events that arrived while the app was closed.
    public func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.refreshPendingDecision() }
        }
    }

    /// Stop observing. Optional in production (`[weak self]` makes a stale
    /// token a no-op even if never explicitly removed), but lets
    /// tests/teardown be deterministic. No `deinit` counterpart: an actor's
    /// `deinit` is nonisolated and cannot touch actor-isolated stored
    /// state (including this non-`Sendable` `NSObjectProtocol` token)
    /// without an `await` it has no way to perform — the same
    /// `[weak self]`-makes-a-stale-token-harmless guarantee this method's
    /// own doc comment already relies on covers the deinit case too.
    public func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    /// The oldest currently-actionable, undecided event, or `nil` if
    /// nothing is pending. Mirrors `AccountStateMonitor.currentState`'s
    /// dual (property + stream) access shape.
    public var pendingDecision: ResetControlEvent? { actionablePending.first }

    /// The most recent auto-discarded event (expired or not-syncing), or
    /// `nil` if nothing has been discarded this session.
    public var discardNotice: ResetEventDiscardNotice? { lastDiscardNotice }

    /// Streams every change to `pendingDecision` (including back to `nil`
    /// once `confirmApply()` clears it). Mirrors
    /// `AccountStateMonitor.stateStream`'s shape.
    public var pendingDecisionStream: AsyncStream<ResetControlEvent?> {
        AsyncStream { continuation in
            let id = UUID()
            pendingContinuations[id] = continuation
            continuation.yield(actionablePending.first)
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { await self?.removePendingContinuation(id) }
            }
        }
    }

    /// Streams every new discard notice.
    public var discardNoticeStream: AsyncStream<ResetEventDiscardNotice?> {
        AsyncStream { continuation in
            let id = UUID()
            noticeContinuations[id] = continuation
            continuation.yield(lastDiscardNotice)
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { await self?.removeNoticeContinuation(id) }
            }
        }
    }

    private func removePendingContinuation(_ id: UUID) {
        pendingContinuations[id] = nil
    }

    private func removeNoticeContinuation(_ id: UUID) {
        noticeContinuations[id] = nil
    }

    private func emitPendingDecision() {
        let current = actionablePending.first
        for continuation in pendingContinuations.values {
            continuation.yield(current)
        }
    }

    private func emitDiscardNotice() {
        for continuation in noticeContinuations.values {
            continuation.yield(lastDiscardNotice)
        }
    }

    /// Scan `ControlInbox` for events addressed to this device and
    /// classify each one — never applies anything. Replaces the prior
    /// `checkAndApply()`, which auto-applied every pending event; see this
    /// type's header doc for the always-prompt state diagram. Reentrancy
    /// is free here (actor-isolated, no explicit guard needed) — a second
    /// concurrent call simply re-scans, which is idempotent.
    public func refreshPendingDecision() async {
        // S22: quarantine undecodable payloads first, so they never linger
        // and never confuse the decodable-events pass below.
        for key in inbox.undecodableKeys(for: deviceID) {
            inbox.discardUndecodable(key: key)
            deadLetters?.record(key: key, discardedAt: clock())
            await breadcrumb("quarantined an undecodable reset event", success: false)
        }

        let mode = await currentSyncMode()
        let now = clock()
        var stillActionable: [ResetControlEvent] = []

        for event in inbox.pendingEvents(for: deviceID).sorted(by: { $0.requestedAt < $1.requestedAt }) {
            if applied.hasApplied(event.id) {
                // Crash-recovery retry: already applied, just finish the ack.
                inbox.acknowledge(eventID: event.id, recipient: deviceID)
                continue
            }
            if Self.isExpired(event, now: now) {
                inbox.acknowledge(eventID: event.id, recipient: deviceID)
                lastDiscardNotice = ResetEventDiscardNotice(event: event, reason: .expired, discardedAt: now)
                await breadcrumb(
                    "discarded expired reset event \(event.id) from \(event.senderDisplayName) (requested \(event.requestedAt))"
                )
                continue
            }
            if mode != .iCloudSync {
                inbox.acknowledge(eventID: event.id, recipient: deviceID)
                lastDiscardNotice = ResetEventDiscardNotice(event: event, reason: .notSyncing, discardedAt: now)
                await breadcrumb(
                    "discarded reset event \(event.id) from \(event.senderDisplayName): device is not in iCloud Sync mode"
                )
                continue
            }
            stillActionable.append(event)
        }

        actionablePending = stillActionable
        emitPendingDecision()
        emitDiscardNotice()
    }

    /// `true` once `event.requestedAt` is `expiryWindowDays` or more in the
    /// past. `Calendar`-based day math per this repo's house rule (date
    /// math through `Calendar`, never `Date.addingTimeInterval`/raw-seconds
    /// multiplication) — see `RecurrenceExpander` for the established
    /// precedent. The boundary is inclusive: exactly `expiryWindowDays`
    /// days old counts as expired.
    static func isExpired(_ event: ResetControlEvent, now: Date) -> Bool {
        guard let expiryDate = Calendar.current.date(
            byAdding: .day, value: expiryWindowDays, to: event.requestedAt
        ) else { return false }
        return now >= expiryDate
    }

    /// Apply the currently pending decision. The **only** call site that
    /// ever invokes the injected `apply` closure — see this type's header
    /// doc for why every other path only ever classifies and surfaces.
    /// A no-op if nothing is currently pending. On success, every
    /// currently-actionable event is acknowledged and marked applied (not
    /// just the anchor) since one convergence satisfies all of them. On
    /// failure, every one of them stays pending/un-acknowledged so the
    /// next confirmation (or scan) can retry — the error propagates for
    /// the UI to surface inline.
    public func confirmApply() async throws {
        guard let anchor = actionablePending.first else { return }
        try await apply(anchor)
        for event in actionablePending {
            applied.markApplied(event.id)
            inbox.acknowledge(eventID: event.id, recipient: deviceID)
        }
        await breadcrumb("applied reset event \(anchor.id) from \(anchor.senderDisplayName)")
        actionablePending = []
        emitPendingDecision()
    }

    private func breadcrumb(_ action: String, success: Bool = true) async {
        guard let breadcrumbs else { return }
        try? await breadcrumbs.record(action: action, success: success)
    }
}
