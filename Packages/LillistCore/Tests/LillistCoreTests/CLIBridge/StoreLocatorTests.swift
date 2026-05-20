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

    @Test("App group identifier matches the apps and extensions entitlement")
    func appGroupIdentifier_matchesAppsAndExtensions() {
        // The CLI must use the same App Group as the iOS / macOS apps and
        // the Share + Shortcuts extensions, otherwise it reads a totally
        // separate (empty) container. The literal lives here intentionally
        // — entitlements were ground truth across the codebase before
        // Plan 21, but the CLI's previous "group.com.mikeydotio.lillist"
        // value was a typo that left the CLI invisible to the apps.
        #expect(CLIBridge.StoreLocator.appGroupIdentifier == "group.io.mikeydotio.Lillist")
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
