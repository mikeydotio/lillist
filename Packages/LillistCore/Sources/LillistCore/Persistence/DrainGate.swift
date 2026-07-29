import Foundation

/// Serializes and coalesces concurrent drains of an append-only stream —
/// every `NSPersistentStoreRemoteChange` consumer in this codebase watches
/// the notification, reads a watermark, fetches everything since it, does
/// some work, then advances the watermark; a burst of notifications spawns
/// several concurrent `Task { await drain() }` calls with no serialization on
/// their own.
///
/// At most one drain runs at a time. A call that arrives while a drain is
/// already in flight does not run concurrently — it requests exactly one
/// coalesced follow-up pass and returns immediately, so a burst of N
/// notifications produces the owning drain plus at most a small, bounded
/// number of reruns, never N independent passes. This also makes a split
/// read-modify-write watermark (read inside a `ctx.perform`, advance after an
/// intervening `await`) atomic with respect to other drains, since only one
/// owner is ever mid-sequence at a time.
///
/// Extracted from `DiagnosticHistoryObserver`'s original private nested
/// actor (data-sync-hardening M3) so `RemoteChangeReconciler` and
/// `TaskDuplicateReconciler` — which both spawned one unstructured `Task {}`
/// per notification with no serialization at all — can adopt the identical,
/// already-proven guarantee instead of each maintaining a divergent copy.
///
/// Each consumer wraps its own "one pass" body in the same four-line
/// acquire/loop shape:
///
/// ```swift
/// func drain() async {
///     guard await drainGate.tryAcquire() else { return }
///     while true {
///         await drainOnce()
///         if await drainGate.finishOrRerun() { continue }
///         return
///     }
/// }
/// ```
///
/// An actor, not a lock, because every call site is `async` and there is no
/// `NSLock.lock()` equivalent across a suspension point. One `DrainGate`
/// instance per consumer instance — never shared across unrelated consumers,
/// which would serialize their unrelated work against each other for no
/// reason.
public actor DrainGate {
    private var isDraining = false
    private var rerunRequested = false

    public init() {}

    /// `true` if the caller becomes the owning drainer and must run a pass;
    /// `false` if a drain is already in flight — a coalesced rerun has been
    /// requested on the caller's behalf, and the caller must return without
    /// running its own pass.
    public func tryAcquire() -> Bool {
        if isDraining { rerunRequested = true; return false }
        isDraining = true
        return true
    }

    /// Call after completing one pass. Returns `true` if the owner must sweep
    /// again (a request arrived mid-drain and was coalesced); `false` once
    /// there is nothing left to do, at which point the gate is released.
    public func finishOrRerun() -> Bool {
        if rerunRequested { rerunRequested = false; return true }
        isDraining = false
        return false
    }
}
