import XCTest
import LillistCore

/// `IntentSupport` (co-compiled into this bundle) is the App Intents
/// entry point that resolves the shared store through the MigrationGate.
/// The deep gate-branch behavior is covered by LillistCore's
/// `GatedPersistenceResolverTests`; this test pins that the iOS-side
/// wrapper still targets the canonical App Group and surfaces a
/// storeUnavailable error rather than crashing when the group is absent.
final class IntentSupportGateTests: XCTestCase {
    func test_usesCanonicalAppGroupID() {
        XCTAssertEqual(IntentSupport.appGroupID, "group.io.mikeydotio.Lillist")
    }

    func test_resolverConstructibleForCanonicalGroup_orThrowsStoreUnavailable() async {
        // In the headless test bundle the real App Group may or may not be
        // reachable. Either way makePersistence must not crash: it either
        // resolves a controller or throws a typed storeUnavailable error.
        do {
            _ = try await IntentSupport.makePersistence()
            // App Group reachable in this environment — acceptable.
        } catch LillistError.storeUnavailable {
            // App Group not provisioned for the headless bundle — the
            // wrapper degraded gracefully to the typed error. Acceptable.
        } catch {
            XCTFail("makePersistence threw an unexpected error type: \(error)")
        }
    }
}
