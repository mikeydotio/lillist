import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge.StoreLocator")
struct StoreLocatorTests {
    @Test("In-memory locator returns a controller")
    func inMemory() async throws {
        let controller = try await CLIBridge.StoreLocator.openInMemory()
        #expect(controller.container.viewContext.persistentStoreCoordinator?.persistentStores.count == 1)
    }

    @Test("App group identifier is the expected value")
    func appGroupID() {
        #expect(CLIBridge.StoreLocator.appGroupIdentifier == "group.com.mikeydotio.lillist")
    }

    @Test("Opening a non-existent app-group container throws storeUnavailable")
    func missingContainer() async {
        do {
            _ = try await CLIBridge.StoreLocator.openAppGroup(identifier: "group.invalid.does-not-exist")
            Issue.record("expected storeUnavailable")
        } catch let LillistError.storeUnavailable(reason) {
            #expect(reason.isEmpty == false)
        } catch {
            Issue.record("expected LillistError.storeUnavailable, got \(error)")
        }
    }
}
