import Testing
import CoreData
import Foundation
@testable import LillistCore

/// Stress the steady-state store API (`TaskStore.create`/`fetch`) against a
/// live `PersistenceHost.reconfigure` swap running underneath it.
///
/// CLAUDE.md mandates stress repetitions for actor-crossing code; the store
/// swap (`coordinator.remove` + `addPersistentStore`) is the most invasive
/// concurrent mutation in the codebase. The viewContext stays attached to
/// the same coordinator across the swap, so create/fetch must remain
/// coherent: rows written before a completed swap must be readable after it.
///
/// Gated to xcodebuild via `liveSwapAllowed` for the same reason as
/// `StoreLevelModeSwapSpike`: `NSCloudKitMirroringDelegate.dealloc` faults
/// inside the swift-test binary (no `CFBundleIdentifier`). This file is also
/// listed in the `Lillist-iOSAppHostedTests` target so the gated cases
/// actually execute under a real bundle ID. Run with:
///   xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
///     -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
///     -only-testing:Lillist-iOSAppHostedTests/StoreReconfigureConcurrencyTests
@Suite("Store reconfigure concurrency (xcodebuild-gated)", .serialized)
struct StoreReconfigureConcurrencyTests {
    private static let swapCount = 10
    private static let writesPerPhase = 25

    /// True only under a real app-bundle host (xcodebuild test). Mirrors
    /// `StoreLevelModeSwapSpike.liveSwapAllowed`.
    private static var liveSwapAllowed: Bool {
        Bundle.main.bundleIdentifier?.isEmpty == false
    }

    private static func freshStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoreReconfigureConcurrency-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Lillist.sqlite")
    }

    @Test("create/fetch interleaved with reconfigure swaps never crash and preserve committed rows",
          .enabled(if: liveSwapAllowed))
    func createFetchSurvivesReconfigure() async throws {
        let url = Self.freshStoreURL()
        let host = try await PersistenceHost.make(initialMode: .iCloudSync, storeURL: url)
        let store = TaskStore(persistence: await host.controller)

        var committedIDs: [UUID] = []

        for phase in 0..<Self.swapCount {
            // Write a batch and capture IDs (sequentially — TaskStore funnels
            // through the main-queue viewContext, which is the contract).
            for i in 0..<Self.writesPerPhase {
                let id = try await store.create(title: "phase-\(phase)-row-\(i)")
                committedIDs.append(id)
            }

            // Flip the mode. flushAndSwap saves pending writes before the
            // remove+add, so everything committed above must survive.
            let target: SyncMode = (phase % 2 == 0) ? .localOnly : .iCloudSync
            try await host.reconfigure(to: target)

            // After the swap the same viewContext is re-attached to the
            // coordinator; every committed row must still fetch.
            let freshStore = TaskStore(persistence: await host.controller)
            for id in committedIDs {
                let record = try await freshStore.fetch(id: id)
                #expect(record.id == id, "phase \(phase): row \(id) lost across swap to \(target)")
            }
        }

        #expect(committedIDs.count == Self.swapCount * Self.writesPerPhase)
    }

    @Test("Concurrent fetches issued while a reconfigure is in flight do not crash the coordinator",
          .enabled(if: liveSwapAllowed))
    func concurrentFetchDuringReconfigure() async throws {
        let url = Self.freshStoreURL()
        let host = try await PersistenceHost.make(initialMode: .iCloudSync, storeURL: url)
        let store = TaskStore(persistence: await host.controller)

        // Seed a row to fetch.
        let seededID = try await store.create(title: "seed")

        for phase in 0..<Self.swapCount {
            let target: SyncMode = (phase % 2 == 0) ? .localOnly : .iCloudSync

            // Kick a reconfigure and a burst of fetches concurrently. The
            // fetches race the remove+add; none may crash. A fetch landing
            // mid-swap may throw .notFound (no attached store) — that's a
            // tolerable transient, a crash is not. We only assert no crash
            // and that a post-swap fetch succeeds.
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    try? await host.reconfigure(to: target)
                }
                for _ in 0..<Self.writesPerPhase {
                    group.addTask {
                        _ = try? await store.fetch(id: seededID)
                    }
                }
                await group.waitForAll()
            }

            // Once the dust settles, the seeded row is still there.
            let after = try await TaskStore(persistence: await host.controller).fetch(id: seededID)
            #expect(after.id == seededID, "phase \(phase): seeded row vanished after swap to \(target)")
        }
    }
}
