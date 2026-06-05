import XCTest
import LillistCore

/// `IntentSupport` (co-compiled into this bundle) is the App Intents
/// entry point that resolves the shared store through the MigrationGate.
/// The deep gate-branch behavior is covered by LillistCore's
/// `GatedPersistenceResolverTests`; this test pins that the iOS-side
/// wrapper targets the canonical App Group and that the gate-resolution
/// seam it uses degrades to a typed error rather than crashing.
final class IntentSupportGateTests: XCTestCase {
    func test_usesCanonicalAppGroupID() {
        XCTAssertEqual(IntentSupport.appGroupID, "group.io.mikeydotio.Lillist")
    }

    func test_canonicalGroupResolvesConfigOrDegradesGracefully() async {
        // IntentSupport.makePersistence() resolves through the gate and then
        // *builds* a PersistenceController. With the App Group present and
        // syncMode == .cloudKit that build stands up an
        // NSPersistentCloudKitContainer whose async CloudKit mirroring setup
        // TRAPS in this headless, un-entitled test bundle (EXC_BREAKPOINT in
        // -[PFCloudKitContainerProvider containerWithIdentifier:options:] on a
        // background queue — residual #11). So we exercise the wrapper's
        // gate-resolution seam directly: resolveStoreConfiguration() returns a
        // value-type StoreConfiguration (no container, no CloudKit), and must
        // either yield a config or degrade to a typed storeUnavailable error —
        // never crash. The live container build is exercised in the entitled
        // app-hosted target; the deep gate abort/allow branches are covered by
        // GatedPersistenceResolverTests.
        guard let resolver = GatedPersistenceResolver(appGroupID: IntentSupport.appGroupID) else {
            return  // App Group not provisioned in this environment — graceful nil, no crash.
        }
        do {
            _ = try await resolver.resolveStoreConfiguration()
            // Gate allowed — a StoreConfiguration was produced (no container built).
        } catch LillistError.storeUnavailable {
            // Gate aborted (e.g. a migration in flight) — typed error, no crash.
        } catch {
            XCTFail("resolveStoreConfiguration threw an unexpected error type: \(error)")
        }
    }
}
