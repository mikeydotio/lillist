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
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)

        self.container = container

        let bridge = CloudKitEventBridge()
        if let ckContainer = container as? NSPersistentCloudKitContainer {
            await bridge.attach(to: ckContainer)
        }
        self.cloudKitEventBridge = bridge
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
