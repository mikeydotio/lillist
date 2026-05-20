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

    @Test("LocalOnly on-disk configuration has no CloudKit container options")
    func description_localOnly_hasNoCloudKitOptions() {
        let url = URL(fileURLWithPath: "/tmp/Lillist-fake.sqlite")
        let cfg = StoreConfiguration.onDisk(url: url, syncMode: .localOnly)
        let desc = PersistenceController.makeStoreDescription(for: cfg)
        #expect(desc.cloudKitContainerOptions == nil)
        // Persistent-history + remote-change flags stay enabled even in
        // LocalOnly so the description stays mode-swappable without
        // recreating the store file.
        #expect(desc.isOptionTrue(NSPersistentHistoryTrackingKey))
        #expect(desc.isOptionTrue(NSPersistentStoreRemoteChangeNotificationPostOptionKey))
    }

    @Test("iCloudSync on-disk configuration carries the private-scope container options")
    func description_iCloudSync_hasCloudKitOptions() {
        let url = URL(fileURLWithPath: "/tmp/Lillist-fake.sqlite")
        let cfg = StoreConfiguration.onDisk(url: url, syncMode: .iCloudSync)
        let desc = PersistenceController.makeStoreDescription(for: cfg)
        #expect(desc.cloudKitContainerOptions != nil)
        #expect(desc.cloudKitContainerOptions?.containerIdentifier == StoreConfiguration.defaultCloudKitContainerIdentifier)
        #expect(desc.cloudKitContainerOptions?.databaseScope == .private)
    }

    @Test("On-disk containers are always NSPersistentCloudKitContainer regardless of mode")
    func container_onDisk_isAlwaysCloudKitSubclass_regardlessOfMode() throws {
        let url = URL(fileURLWithPath: "/tmp/Lillist-mode.sqlite")
        let local = try PersistenceController.makeContainer(for: .onDisk(url: url, syncMode: .localOnly))
        let cloud = try PersistenceController.makeContainer(for: .onDisk(url: url, syncMode: .iCloudSync))
        #expect(local is NSPersistentCloudKitContainer)
        #expect(cloud is NSPersistentCloudKitContainer)
    }
}

private extension NSPersistentStoreDescription {
    func isOptionTrue(_ key: String) -> Bool {
        (options[key] as? NSNumber)?.boolValue == true
    }
}
