import Foundation
import CoreData
import CloudKit

/// Owns the Core Data container and exposes a single shared view context.
///
/// Plan 1 used `NSPersistentContainer` everywhere. Plan 2 promotes the
/// on-disk (production) path to `NSPersistentCloudKitContainer` so it mirrors
/// to iCloud per design Section 3. The in-memory (`/dev/null`) path used by
/// tests and previews continues to use plain `NSPersistentContainer`:
/// instantiating `NSPersistentCloudKitContainer` 90+ times in parallel test
/// workers triggers internal races in `_loadStoreDescriptions` /
/// `PFCloudKitSetupAssistant` that crash the test process. Production never
/// uses the in-memory path, so this asymmetry is safe. CloudKit-specific
/// behavior is verified through static factories that build descriptions and
/// containers without loading the stores.
public final class PersistenceController: @unchecked Sendable {
    public let container: NSPersistentContainer
    public let configuration: StoreConfiguration
    /// The event bridge that translates
    /// `NSPersistentCloudKitContainer.eventChangedNotification` into a
    /// testable async stream. Attached automatically after the persistent
    /// stores load. Always non-nil; the bridge is harmless when the
    /// underlying container is plain (no events ever fire).
    public let cloudKitEventBridge: CloudKitEventBridge

    /// Transaction author stamped on every `viewContext` write. Lets the
    /// persistent-history diff in `RemoteChangeReconciler` ignore
    /// self-originated transactions and react only to CloudKit imports
    /// (which carry Core Data's reserved import author). Value is an opaque
    /// stable string, not the device fingerprint — per-device identity isn't
    /// needed here, only "this app vs. the CloudKit mirror".
    public static let localTransactionAuthor = "Lillist.app"

    public init(configuration: StoreConfiguration) async throws {
        self.configuration = configuration
        let container = try Self.makeContainer(for: configuration)
        let description = Self.makeStoreDescription(for: configuration)
        container.persistentStoreDescriptions = [description]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { _, error in
                if let error {
                    continuation.resume(throwing: LillistError.storeUnavailable(reason: error.localizedDescription))
                } else {
                    continuation.resume(returning: ())
                }
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        // Store-wide conflict policy. `mergeByPropertyObjectTrump` keeps the
        // *in-memory* (just-written) value when a CloudKit import collides on a
        // property — last-writer-on-this-device wins per attribute. This is the
        // pragmatic default for a single-user multi-device account: edits made
        // here while offline survive a re-pull. The known cost (review persist-5)
        // is that a *concurrent edit on another device* to the same property is
        // silently discarded on merge; per-record field-level CRDT reconciliation
        // is out of scope (YAGNI) until a real conflict report appears. Documented
        // in engineering-notes.md so the choice is explicit, not inherited.
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        // Attribute every write made through `viewContext` so the persistent-history
        // stream can distinguish our own local transactions from CloudKit imports
        // (whose author is the reserved `NSCloudKitMirroringDelegate.import`).
        // `RemoteChangeReconciler` keys off this author to skip self-originated
        // history when deciding which tasks to reconcile after a remote pull.
        container.viewContext.transactionAuthor = Self.localTransactionAuthor
        container.viewContext.name = Self.localTransactionAuthor

        self.container = container

        let bridge = CloudKitEventBridge()
        if let ckContainer = container as? NSPersistentCloudKitContainer {
            await bridge.attach(to: ckContainer)
        }
        self.cloudKitEventBridge = bridge
    }

    /// Count user-visible (non-trashed) task rows in the local store.
    ///
    /// Used by the migration precondition (sync-7): the irreversible
    /// "replace iCloud with local" erase must refuse to run against an
    /// empty local store, or it would wipe iCloud and leave the user
    /// with nothing. The count runs on the view-context's own queue and
    /// **fails closed** — any thrown error returns `0`, which the
    /// coordinator treats as "empty" and uses to *block* the erase. An
    /// uncertain count must never bypass the guard. Keeping the
    /// `LillistTask` fetch here honors the module boundary: no
    /// `NSManagedObject` escapes `LillistCore`.
    public func localTaskRowCount() async -> Int {
        let context = container.viewContext
        return await context.perform {
            let request = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            request.predicate = NSPredicate(format: "deletedAt == nil")
            return (try? context.count(for: request)) ?? 0
        }
    }

    /// A dedicated private-queue context for bulk work (export, import,
    /// Trash purge) that would otherwise block the main-queue
    /// `viewContext`. The single shared `viewContext` remains the default
    /// for all interactive mutations — it is the context
    /// `NSPersistentCloudKitContainer` merges remote changes into via
    /// `automaticallyMergesChangesFromParent`. This vends a *separate*
    /// context so a 10k-row export never freezes the UI.
    ///
    /// `automaticallyMergesChangesFromParent` is ON so this context sees
    /// concurrent `viewContext` edits, and its saves propagate up to the
    /// `viewContext` (which auto-merges them) so callers don't have to
    /// refetch after an import. The merge policy matches `viewContext`'s
    /// store-wide trump policy so a background save never silently loses
    /// to a concurrent main-queue edit.
    public func makeBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        // Attribute background writes with the same author as the viewContext
        // so `RemoteChangeReconciler`'s local-vs-foreign history filter
        // (change.author != localAuthor) correctly classifies bulk-import /
        // purge writes as local, not as foreign CloudKit changes.
        context.transactionAuthor = Self.localTransactionAuthor
        return context
    }

    /// Build the `NSPersistentContainer` (or `NSPersistentCloudKitContainer`)
    /// for a given configuration without loading the stores.
    ///
    /// - In-memory configurations return a plain `NSPersistentContainer`.
    /// - On-disk configurations return an `NSPersistentCloudKitContainer` so
    ///   Core Data can mirror to iCloud (design Section 3).
    /// - Throws: `LillistError.modelUnavailable` if the compiled managed-object
    ///   model cannot be located in the resource bundle.
    public static func makeContainer(for configuration: StoreConfiguration) throws -> NSPersistentContainer {
        let model = try sharedModel()
        switch configuration.storeKind {
        case .inMemory:
            return NSPersistentContainer(name: "LillistModel", managedObjectModel: model)
        case .onDisk:
            return NSPersistentCloudKitContainer(name: "LillistModel", managedObjectModel: model)
        }
    }

    /// Build the `NSPersistentStoreDescription` for a given configuration.
    ///
    /// Exposed as a static factory so tests can verify the description's
    /// CloudKit options, persistent-history flag, and remote-change-notification
    /// flag without instantiating a real container.
    ///
    /// Plan 21: CloudKit options are attached only when both the store
    /// is on-disk and the configuration's `syncMode == .iCloudSync`.
    /// LocalOnly on-disk stores keep persistent-history tracking and
    /// remote-change notifications enabled (they're required for
    /// CloudKit and harmless on plain stores) so the mode swap is a
    /// pure description mutation, never a structural one.
    public static func makeStoreDescription(for configuration: StoreConfiguration) -> NSPersistentStoreDescription {
        let description: NSPersistentStoreDescription
        let canAttachCloudKitOptions: Bool
        switch configuration.storeKind {
        case .inMemory:
            description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
            description.type = NSSQLiteStoreType
            canAttachCloudKitOptions = false
        case .onDisk(let url):
            description = NSPersistentStoreDescription(url: url)
            description.type = NSSQLiteStoreType
            canAttachCloudKitOptions = true
        }
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true

        // Required for NSPersistentCloudKitContainer (and harmless on plain).
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        // CloudKit options — private database, single custom zone (design Section 3).
        if canAttachCloudKitOptions && configuration.syncMode == .iCloudSync {
            let options = NSPersistentCloudKitContainerOptions(containerIdentifier: configuration.cloudKitContainerIdentifier)
            options.databaseScope = CKDatabase.Scope.private
            description.cloudKitContainerOptions = options
        }
        return description
    }

    /// The compiled Core Data managed-object model.
    ///
    /// Tries Xcode's DataModelCompile output first (`LillistModel.momd`,
    /// produced in workspace builds), then falls back to the SPM
    /// build-tool plugin's output (`LillistModel.spm.momd`, produced in
    /// standalone `swift build` / `swift test`). The plugin uses a
    /// distinct filename to avoid colliding with Xcode's auto-compile in
    /// workspace builds; see `CompileCoreDataModel.swift` and the Plan 9
    /// engineering note.
    ///
    /// The result is cached on first call so successive
    /// `PersistenceController` constructions reuse a single
    /// `NSManagedObjectModel`. Loading the model afresh every time
    /// makes Core Data emit a runtime warning of the form
    /// `<Entity> from NSManagedObjectModel <addr> claims <Entity>` for
    /// every entity in every parallel test worker — the framework
    /// detects that the same Swift class is registered to multiple
    /// model instances. `NSManagedObjectModel` is effectively immutable
    /// once compiled, so the shared instance is safe to read from any
    /// thread.
    ///
    /// - Throws: `LillistError.modelUnavailable` listing the filenames
    ///   that were searched if no model bundle is found, or the single
    ///   resolved filename if the bundle exists but fails to parse.
    public static func sharedModel() throws -> NSManagedObjectModel {
        try cachedModelResult.get()
    }

    nonisolated(unsafe) private static let cachedModelResult: Result<NSManagedObjectModel, LillistError> = {
        let searched = ["LillistModel.momd", "LillistModel.spm.momd"]
        var foundURL: URL?
        for name in searched {
            let stem = (name as NSString).deletingPathExtension
            if let url = Bundle.module.url(forResource: stem, withExtension: "momd") {
                foundURL = url
                break
            }
        }
        guard let url = foundURL else {
            return .failure(.modelUnavailable(searchedFilenames: searched))
        }
        guard let model = NSManagedObjectModel(contentsOf: url) else {
            return .failure(.modelUnavailable(searchedFilenames: [url.lastPathComponent]))
        }
        return .success(model)
    }()
}
