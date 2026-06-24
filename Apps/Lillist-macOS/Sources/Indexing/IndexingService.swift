import CoreSpotlight
import Foundation
import LillistCore

/// Plan 15 Task 24: pushes Lillist tasks into the system Spotlight
/// index. Each task becomes a `CSSearchableItem` under the
/// `app.lillist.task` domain identifier (see
/// `IndexingMappers.domainIdentifier`), so the user can find their
/// tasks from any Spotlight search and the system can optionally
/// surface them in `Show More From Lillist…`.
///
/// `start()` is idempotent: it subscribes once to Core Data save
/// notifications and re-indexes any modified tasks; on first invocation
/// it also performs a full reindex if the signature key in
/// UserDefaults is stale.
@MainActor
final class IndexingService {
    /// UserDefaults key marking the index format version. Bump when
    /// the attribute-set shape changes to trigger a full reindex.
    private static let indexSignatureKey = "lillist.spotlight.indexSignature"
    private static let currentIndexSignature = "v1"

    private let environment: AppEnvironment
    private var saveObserver: NSObjectProtocol?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func start() async {
        let defaults = UserDefaults.standard
        let stored = defaults.string(forKey: Self.indexSignatureKey)
        if stored != Self.currentIndexSignature {
            await reindexAll()
            defaults.set(Self.currentIndexSignature, forKey: Self.indexSignatureKey)
        }
        installSaveObserver()
    }

    func stop() {
        if let observer = saveObserver {
            NotificationCenter.default.removeObserver(observer)
            saveObserver = nil
        }
    }

    private func installSaveObserver() {
        saveObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.indexChangedTasks() }
        }
    }

    /// Re-indexes every non-trashed task. Called on first launch (or
    /// after a signature bump). Tasks in the trash are removed from
    /// the index via `deleteSearchableItems(withIdentifiers:)`.
    func reindexAll() async {
        do {
            let live = try await environment.taskStore.children(of: nil)
            let trashed = try await environment.taskStore.trashed()
            let items = live.map { IndexingMappers.searchableItem(for: $0, tagNames: []) }
            try await CSSearchableIndex.default().indexSearchableItems(items)
            let trashedIDs = trashed.map(\.id.uuidString)
            if !trashedIDs.isEmpty {
                try await CSSearchableIndex.default()
                    .deleteSearchableItems(withIdentifiers: trashedIDs)
            }
        } catch {
            // Log the error TYPE only as .public (per the LillistLog privacy
            // contract): a full localizedDescription can carry Core Data
            // attribute values / the store path into the crash-collected
            // subsystem, and the redactor only partially covers those.
            LillistLog.indexing.error(
                "reindexAll failed: \(String(describing: type(of: error)), privacy: .public)"
            )
        }
    }

    /// Refreshes the index for whatever the last Core Data save
    /// touched. We don't have per-save deltas, so the cheap-and-correct
    /// option is to re-push the same items — `indexSearchableItems`
    /// is upsert-shaped and Spotlight de-duplicates by
    /// `uniqueIdentifier`. A future optimization is to subscribe to
    /// the `NSManagedObjectContextObjectsDidChange` notification and
    /// push only the inserted/updated objects.
    private func indexChangedTasks() async {
        await reindexAll()
    }
}
