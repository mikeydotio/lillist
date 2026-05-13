import Foundation
import CoreData

/// Owns the `NSPersistentContainer` and exposes a single shared view context.
///
/// Plan 1 uses the non-CloudKit container; Plan 2 swaps in
/// `NSPersistentCloudKitContainer` without touching downstream callers.
public final class PersistenceController: @unchecked Sendable {
    public let container: NSPersistentContainer

    public init(configuration: StoreConfiguration) async throws {
        let model = Self.loadModel()
        let container = NSPersistentContainer(name: "LillistModel", managedObjectModel: model)

        let description: NSPersistentStoreDescription
        switch configuration {
        case .inMemory:
            description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
            description.type = NSSQLiteStoreType
        case .onDisk(let url):
            description = NSPersistentStoreDescription(url: url)
            description.type = NSSQLiteStoreType
        }
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
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
