import Foundation

/// Serializes every destructive operation that mutates the shared
/// `PersistenceHost` — a sync-mode migration (`MigrationCoordinator`), a
/// data-store reset (`DataStoreResetService`), or a crash-recovery restore
/// (`MigrationCoordinator.restoreFromBackup`) — so at most one runs at a
/// time, regardless of which type or which call site (Settings UI,
/// `ResetSignalMonitor`'s automatic peer-reset application, crash-recovery
/// restore) initiated it.
///
/// Before this type, `MigrationCoordinator` and `DataStoreResetService`
/// each closed their *own* reentrancy window with a private `@MainActor`
/// boolean flag, but nothing stopped the two types running concurrently
/// against the same host — `data-sync-hardening` finding `S11`.
///
/// `@MainActor final class`, not an `actor`: every caller is already
/// `@MainActor`-isolated, and `acquire(for:)` must be synchronous —
/// settable *before* the caller's first `await` — to close the exact
/// same-process reentrancy window the single-flag guards it replaces
/// existed to close (two `begin*` calls enqueued back-to-back on the
/// MainActor must have the *first* one's acquire visible to the second
/// one's synchronous check, before either suspends). An `actor`'s `async`
/// acquire would reopen that window.
@MainActor
public final class DestructiveOpGate {
    /// Identifies which destructive operation currently holds the gate,
    /// for diagnosable "already in progress" error messages.
    public enum Owner: Sendable, Equatable, CustomStringConvertible {
        /// A `MigrationCoordinator` sync-mode transition.
        case migration(ModeTransitionOp)
        /// A `DataStoreResetService` reset. The label names the specific
        /// entry point (`"resetAllData"`, `"resetAndRedownload"`,
        /// `"resetEverywhereToEmpty"`, `"resetAndReseedFromThisDevice"`)
        /// so a blocked caller's error message is diagnosable.
        case reset(String)
        /// `MigrationCoordinator.restoreFromBackup`.
        case restore

        public var description: String {
            switch self {
            case .migration(let op):
                return "a sync-mode migration (\(op.rawValue))"
            case .reset(let label):
                return "a data-store reset (\(label))"
            case .restore:
                return "a backup restore"
            }
        }
    }

    public private(set) var currentOwner: Owner?

    public init() {}

    /// Claim the gate for `owner`. Throws `LillistError.storeUnavailable`
    /// naming both the requested and the currently-holding operation when
    /// the gate is already held. Synchronous — no suspension point, so a
    /// caller can call this as the very first statement of an `async`
    /// function to close the same-process reentrancy window before any
    /// `await`.
    public func acquire(for owner: Owner) throws {
        if let currentOwner {
            throw LillistError.storeUnavailable(
                reason: "Can't start \(owner): \(currentOwner) is already in progress."
            )
        }
        currentOwner = owner
    }

    /// Release the gate unconditionally. Every caller pairs this with
    /// `acquire(for:)` via `defer`, so there is never a legitimate
    /// "wrong owner" release to guard against.
    public func release() {
        currentOwner = nil
    }
}
