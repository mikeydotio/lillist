import Testing
import CoreData
@testable import LillistCore

@Suite("PersistenceController")
struct PersistenceControllerTests {
    @Test("In-memory store loads successfully")
    func inMemoryLoads() async throws {
        let controller = try await PersistenceController(configuration: .inMemory)
        #expect(controller.container.viewContext.persistentStoreCoordinator?.persistentStores.count == 1)
    }

    @Test("Two in-memory controllers are isolated")
    func isolation() async throws {
        let a = try await PersistenceController(configuration: .inMemory)
        let b = try await PersistenceController(configuration: .inMemory)
        let entity = NSEntityDescription.insertNewObject(forEntityName: "LillistTask", into: a.container.viewContext)
        entity.setValue(UUID(), forKey: "id")
        entity.setValue("a", forKey: "title")
        try a.container.viewContext.save()

        let req = NSFetchRequest<NSManagedObject>(entityName: "LillistTask")
        let aCount = try a.container.viewContext.count(for: req)
        let bCount = try b.container.viewContext.count(for: req)
        #expect(aCount == 1)
        #expect(bCount == 0)
    }

    @Test("Model contains all expected entities")
    func entitiesPresent() async throws {
        let controller = try await PersistenceController(configuration: .inMemory)
        let names = Set(controller.container.managedObjectModel.entities.compactMap(\.name))
        #expect(names.contains("LillistTask"))
        #expect(names.contains("Tag"))
        #expect(names.contains("JournalEntry"))
        #expect(names.contains("Attachment"))
        #expect(names.contains("AppPreferences"))
        #expect(names.contains("SmartFilter"))
    }

    @Test("Model contains SmartFilter entity with expected attributes")
    func smartFilterEntityShape() async throws {
        let controller = try await PersistenceController(configuration: .inMemory)
        let model = controller.container.managedObjectModel
        guard let entity = model.entitiesByName["SmartFilter"] else {
            Issue.record("SmartFilter entity missing")
            return
        }
        let attrs = Set(entity.attributesByName.keys)
        for required in ["id", "name", "predicateGroupJSON", "tintColor",
                         "sortFieldRaw", "sortAscending", "isPinned", "position",
                         "createdAt", "modifiedAt"] {
            #expect(attrs.contains(required), "missing attribute \(required)")
        }
        // CloudKit rule: every attribute must be optional at the schema level.
        for (_, attr) in entity.attributesByName {
            #expect(attr.isOptional == true, "\(attr.name) must be optional")
        }
    }
}
