import Foundation
import CoreData

/// Seam for reloading widget timelines after a snapshot rebuild.
///
/// **`LillistCore` never imports WidgetKit** — it's linked by the headless
/// `lillist-cli`, which can't link WidgetKit (see
/// `docs/engineering-notes.md`, 2026-07-01). The app/extension target
/// supplies the one conformance that actually calls
/// `WidgetCenter.shared.reloadAllTimelines()`; everything upstream of that
/// call (detecting a change, debouncing, rebuilding the snapshot cache) is
/// plain `LillistCore` and testable without WidgetKit.
public protocol WidgetTimelineReloading: Sendable {
    func reloadAllTimelines()
}

/// Watches everything that can change what a widget should show — this
/// process's own local saves *and* cross-process/CloudKit remote imports —
/// and debounces a burst of either into one snapshot rebuild + one timeline
/// reload.
///
/// data-sync-hardening `X6`: the predecessor this type replaces
/// (`WidgetRefreshCoordinator`, duplicated byte-for-byte in both app
/// targets) was driven only by `.NSPersistentStoreRemoteChange`, and both
/// apps' bootstrap code carried a comment asserting that notification
/// "fires for local writes and CloudKit imports alike." That's false for
/// this codebase: `.NSPersistentStoreRemoteChange` reflects changes this
/// process didn't just make on its own `viewContext` — it does not fire for
/// a task completed in-app. The widget was left permanently stale in
/// `.localOnly` mode (no CloudKit imports ever arrive to trigger it) and,
/// even with sync on, stale until the next remote change happened to land;
/// the 30-minute timeline backstop just re-renders the same stale JSON, it
/// doesn't rebuild it.
///
/// Fixed by observing `.NSManagedObjectContextDidSave` on `viewContext`
/// alongside the existing remote-change observer — the identical mechanism
/// `LocalBackupCoordinator` already uses to track the same two entities
/// (`LillistTask`, `SmartFilter`) these snapshots are built from. Every
/// `LillistCore` store's mutating methods save through
/// `context = persistence.container.viewContext` (see `TaskStore.context`),
/// so this one observer catches every local mutation that could change
/// widget content, with nothing to keep in sync as new mutation methods are
/// added.
///
/// `@MainActor final class`, matching `LocalBackupCoordinator`'s exact
/// concurrency shape (not an `actor`): an `actor`'s `deinit` cannot touch
/// its own actor-isolated `NSObjectProtocol` observer tokens under strict
/// concurrency (the type isn't `Sendable`, and actor deinits are
/// nonisolated) — discovered while implementing this, not anticipated in
/// the plan doc's §4 sketch, which is corrected here in place. Self-
/// registers its own `NotificationCenter` observers, each hopping onto
/// `@MainActor` before touching `pending` — the same pattern `AppEnvironment`
/// used to wire manually for the predecessor this replaces, just now owned
/// by the type itself instead of duplicated per app.
///
/// Every regenerate-triggering path here calls
/// ``WidgetSnapshotBuilder/regenerateAuthoritatively()`` — this type *is*
/// "the app's own process" that method's doc comment grants prune authority
/// to; there is no other caller anywhere in the codebase.
@MainActor
public final class WidgetRefreshController {
    private let persistence: PersistenceController
    private let builder: WidgetSnapshotBuilder
    private let reloader: WidgetTimelineReloading
    private let debounce: Duration

    private var didSaveObserver: NSObjectProtocol?
    private var remoteObserver: NSObjectProtocol?
    private var pending: Task<Void, Never>?

    public init(
        persistence: PersistenceController,
        builder: WidgetSnapshotBuilder,
        reloader: WidgetTimelineReloading,
        debounce: Duration = .milliseconds(1500)
    ) {
        self.persistence = persistence
        self.builder = builder
        self.reloader = reloader
        self.debounce = debounce
    }

    // MARK: - Lifecycle

    /// Begin observing local saves and remote CloudKit changes. Idempotent.
    public func start() {
        guard didSaveObserver == nil else { return }
        let center = NotificationCenter.default
        didSaveObserver = center.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: persistence.container.viewContext,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleRefresh() }
        }
        remoteObserver = center.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistence.container.persistentStoreCoordinator,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleRefresh() }
        }
    }

    /// Stop observing. `[weak self]` makes a stale token a no-op in
    /// production; explicit for deterministic test teardown.
    public func stop() {
        let center = NotificationCenter.default
        if let didSaveObserver { center.removeObserver(didSaveObserver) }
        if let remoteObserver { center.removeObserver(remoteObserver) }
        didSaveObserver = nil
        remoteObserver = nil
        pending?.cancel()
        pending = nil
    }

    isolated deinit {
        let center = NotificationCenter.default
        if let didSaveObserver { center.removeObserver(didSaveObserver) }
        if let remoteObserver { center.removeObserver(remoteObserver) }
    }

    // MARK: - Refresh

    /// Coalesce a burst of either signal (local saves, remote changes, or
    /// both) into one rebuild + one timeline reload.
    public func scheduleRefresh() {
        pending?.cancel()
        let builder = self.builder
        let reloader = self.reloader
        let debounce = self.debounce
        pending = Task {
            try? await Task.sleep(for: debounce)
            if Task.isCancelled { return }
            await builder.regenerateAuthoritatively()
            reloader.reloadAllTimelines()
        }
    }

    /// Regenerate immediately (no debounce). Used once at bootstrap to warm
    /// the cache so a freshly added widget renders without waiting for a
    /// change.
    public func refreshNow() {
        pending?.cancel()
        let builder = self.builder
        let reloader = self.reloader
        pending = Task {
            await builder.regenerateAuthoritatively()
            reloader.reloadAllTimelines()
        }
    }

    /// Data-sync-hardening `X11`: wipes the cache, regenerates against the
    /// current (likely now-empty or freshly-reseeded) store state, and
    /// reloads every timeline — called after a destructive store
    /// reset/rebuild so a stale, now-erased task can never render with a
    /// dangling deep link in the gap before the next natural regenerate.
    /// Unlike `scheduleRefresh()`/`refreshNow()`, callers driving a
    /// destructive reset `await` this directly for deterministic
    /// sequencing (matching the `backupReconciler`/`historyWatermarksReset`
    /// calls it's wired alongside in `AppEnvironment`).
    public func resetAfterDestructiveOp() async {
        pending?.cancel()
        pending = nil
        builder.clearCache()
        await builder.regenerateAuthoritatively()
        reloader.reloadAllTimelines()
    }
}
