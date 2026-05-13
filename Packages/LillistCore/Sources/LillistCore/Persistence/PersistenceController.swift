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
        let container = Self.makeContainer(for: configuration)
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
    public static func makeContainer(for configuration: StoreConfiguration) -> NSPersistentContainer {
        let model = loadModel()
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
    public static func makeStoreDescription(for configuration: StoreConfiguration) -> NSPersistentStoreDescription {
        let description: NSPersistentStoreDescription
        let attachCloudKitOptions: Bool
        switch configuration.storeKind {
        case .inMemory:
            description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
            description.type = NSSQLiteStoreType
            attachCloudKitOptions = false
        case .onDisk(let url):
            description = NSPersistentStoreDescription(url: url)
            description.type = NSSQLiteStoreType
            attachCloudKitOptions = true
        }
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true

        // Required for NSPersistentCloudKitContainer (and harmless on plain).
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        // CloudKit options — private database, single custom zone (design Section 3).
        if attachCloudKitOptions {
            let options = NSPersistentCloudKitContainerOptions(containerIdentifier: configuration.cloudKitContainerIdentifier)
            options.databaseScope = CKDatabase.Scope.private
            description.cloudKitContainerOptions = options
        }
        return description
    }

    nonisolated(unsafe) private static let sharedModel: NSManagedObjectModel = {
        guard let url = Bundle.module.url(forResource: "LillistModel", withExtension: "momd") else {
            preconditionFailure("LillistModel.momd not found in bundle")
        }
        guard let model = NSManagedObjectModel(contentsOf: url) else {
            preconditionFailure("Failed to load NSManagedObjectModel from \(url)")
        }
        return model
    }()

    private static func loadModel() -> NSManagedObjectModel {
        sharedModel
    }
}
