import Testing
import CoreData
import Foundation
@testable import LillistCore

@Suite("PersistenceController (CloudKit)")
struct PersistenceControllerCloudKitTests {
    @Test("On-disk configuration produces an NSPersistentCloudKitContainer")
    func onDiskMakesCloudKitContainer() throws {
        let url = URL(fileURLWithPath: "/tmp/Lillist-fake.sqlite")
        let container = try PersistenceController.makeContainer(for: .onDisk(url: url))
        #expect(container is NSPersistentCloudKitContainer)
    }

    @Test("In-memory configuration produces a plain NSPersistentContainer (test/preview path)")
    func inMemoryMakesPlainContainer() throws {
        let container = try PersistenceController.makeContainer(for: .inMemory)
        #expect((container is NSPersistentCloudKitContainer) == false)
    }

    @Test("On-disk description carries CloudKit container options with the configured identifier")
    func cloudKitOptionsPresentOnDisk() {
        let url = URL(fileURLWithPath: "/tmp/Lillist-fake.sqlite")
        let cfg = StoreConfiguration.onDisk(url: url).withCloudKitContainer("iCloud.example.test")
        let desc = PersistenceController.makeStoreDescription(for: cfg)
        #expect(desc.cloudKitContainerOptions != nil)
        #expect(desc.cloudKitContainerOptions?.containerIdentifier == "iCloud.example.test")
        #expect(desc.cloudKitContainerOptions?.databaseScope == .private)
    }

    @Test("On-disk description enables persistent history tracking and remote-change notifications")
    func onDiskHistoryAndRemoteChangesEnabled() {
        let url = URL(fileURLWithPath: "/tmp/Lillist-fake.sqlite")
        let desc = PersistenceController.makeStoreDescription(for: .onDisk(url: url))
        #expect(desc.isOptionTrue(NSPersistentHistoryTrackingKey))
        #expect(desc.isOptionTrue(NSPersistentStoreRemoteChangeNotificationPostOptionKey))
    }

    @Test("In-memory store loads with persistent history tracking + remote-change notifications enabled")
    func inMemoryHistoryAndRemoteChangesEnabled() async throws {
        let controller = try await PersistenceController(configuration: .inMemory)
        let desc = controller.container.persistentStoreDescriptions.first!
        #expect(desc.isOptionTrue(NSPersistentHistoryTrackingKey))
        #expect(desc.isOptionTrue(NSPersistentStoreRemoteChangeNotificationPostOptionKey))
    }

    @Test("Default merge policy remains object-property-trump after CloudKit upgrade")
    func mergePolicyPreserved() async throws {
        let controller = try await PersistenceController(configuration: .inMemory)
        let policy = controller.container.viewContext.mergePolicy as? NSMergePolicy
        #expect(policy != nil)
        let trump = NSMergePolicy.mergeByPropertyObjectTrump
        #expect(controller.container.viewContext.mergePolicy as AnyObject === trump as AnyObject ||
                policy?.mergeType == .mergeByPropertyObjectTrumpMergePolicyType)
    }

    @Test("PersistenceController exposes a CloudKitEventBridge")
    func bridgeExposed() async throws {
        let controller = try await PersistenceController(configuration: .inMemory)
        _ = controller.cloudKitEventBridge
    }

    @Test("Attachment.data attribute keeps allowsExternalBinaryDataStorage so CloudKit converts to CKAsset")
    func externalStorageFlagPreserved() async throws {
        let controller = try await PersistenceController(configuration: .inMemory)
        let model = controller.container.managedObjectModel
        guard let entity = model.entitiesByName["Attachment"] else {
            Issue.record("Attachment entity missing")
            return
        }
        guard let attr = entity.attributesByName["data"] else {
            Issue.record("Attachment.data attribute missing")
            return
        }
        #expect(attr.allowsExternalBinaryDataStorage == true)
    }
}

private extension NSPersistentStoreDescription {
    func isOptionTrue(_ key: String) -> Bool {
        (options[key] as? NSNumber)?.boolValue == true
    }
}
