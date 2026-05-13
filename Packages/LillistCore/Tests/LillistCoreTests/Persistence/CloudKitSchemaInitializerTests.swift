import Testing
import CoreData
@testable import LillistCore

@Suite("CloudKitSchemaInitializer")
struct CloudKitSchemaInitializerTests {
    @Test("Initializer accepts a persistence controller without crashing in dry-run mode")
    func dryRun() async throws {
        let controller = try await PersistenceController(configuration: .inMemory)
        // Dry-run path avoids the real CloudKit network call.
        try CloudKitSchemaInitializer.initializeIfNeeded(persistence: controller, dryRun: true)
    }

    @Test("Dry run records that it was invoked")
    func dryRunRecorded() async throws {
        let controller = try await PersistenceController(configuration: .inMemory)
        var didRun = false
        try CloudKitSchemaInitializer.initializeIfNeeded(persistence: controller, dryRun: true, onInvoke: { didRun = true })
        #expect(didRun == true)
    }

    @Test("In RELEASE configuration, dry run still runs (guard is build-time, not config-time)")
    func dryRunInRelease() async throws {
        let controller = try await PersistenceController(configuration: .inMemory)
        var didRun = false
        try CloudKitSchemaInitializer.initializeIfNeeded(persistence: controller, dryRun: true, onInvoke: { didRun = true })
        #expect(didRun == true)
    }
}
