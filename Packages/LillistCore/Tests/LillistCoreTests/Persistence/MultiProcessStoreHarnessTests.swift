import Testing
import Foundation
@testable import LillistCore

/// The Keystone deliverable for plan 1c: nothing in the pre-existing suite
/// ever opened two `PersistenceController`s against one on-disk store file,
/// which is exactly the cross-process topology `X1`/`X2`/`X5`/`X7`/`X15`/
/// `X20` all live in (per the review's "Structural test gaps" note). This
/// suite proves the write-visibility contract two independent controllers
/// need in order to simulate that topology, and pins every `StoreLocation`
/// role to the identical file path — the direct regression proof for
/// `X1`/`X2`. Reusable as-is by Wave 5b (`widget-snapshot-correctness`).
@Suite("Multi-process store harness (Keystone)")
struct MultiProcessStoreHarnessTests {
    private func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MultiProcessStoreHarnessTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Lillist.sqlite")
    }

    // MARK: - Two controllers, one file: write visibility

    @Test("A write from controller A becomes visible to a fresh fetch on controller B (same on-disk file, two processes simulated)")
    func writeFromA_visibleToB() async throws {
        let storeURL = tempStoreURL()
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        // .localOnly avoids any CloudKit network activity in this SPM test
        // process while still exercising the real on-disk WAL-mode SQLite
        // file two independent NSPersistentCloudKitContainer instances
        // share — the same shape production processes see, minus the
        // CloudKit round-trip.
        let controllerA = try await PersistenceController(
            configuration: .onDisk(url: storeURL, syncMode: .localOnly),
            transactionAuthor: PersistenceController.localTransactionAuthor
        )
        let controllerB = try await PersistenceController(
            configuration: .onDisk(url: storeURL, syncMode: .localOnly),
            transactionAuthor: PersistenceController.cliTransactionAuthor
        )

        let storeA = TaskStore(persistence: controllerA)
        let id = try await storeA.create(title: "written by A")

        // B didn't have this row when it opened — force a coordinator-level
        // refresh (simulating what a second process's next read would see
        // once SQLite's shared file state reflects A's commit) rather than
        // relying on in-process cross-context notifications, which don't
        // fire between two independently-constructed containers the way
        // they would between two contexts of the SAME container.
        await controllerB.container.viewContext.perform {
            controllerB.container.viewContext.refreshAllObjects()
        }
        let storeB = TaskStore(persistence: controllerB)
        let seenByB = try await storeB.fetch(id: id)
        #expect(seenByB.title == "written by A")
    }

    @Test("Round-trip through both controllers converges: B's edit is visible back on A")
    func editFromB_visibleBackOnA() async throws {
        let storeURL = tempStoreURL()
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let controllerA = try await PersistenceController(configuration: .onDisk(url: storeURL, syncMode: .localOnly))
        let controllerB = try await PersistenceController(
            configuration: .onDisk(url: storeURL, syncMode: .localOnly),
            transactionAuthor: PersistenceController.widgetTransactionAuthor
        )

        let storeA = TaskStore(persistence: controllerA)
        let id = try await storeA.create(title: "original")

        await controllerB.container.viewContext.perform {
            controllerB.container.viewContext.refreshAllObjects()
        }
        let storeB = TaskStore(persistence: controllerB)
        try await storeB.update(id: id) { draft in draft.title = "renamed by B" }

        await controllerA.container.viewContext.perform {
            controllerA.container.viewContext.refreshAllObjects()
        }
        let seenByA = try await storeA.fetch(id: id)
        #expect(seenByA.title == "renamed by B")
    }

    // MARK: - Path-pin regression test (X1/X2)

    @Test("Every StoreLocation role resolves to the identical file URL for one App Group container")
    func everyRoleResolvesToIdenticalPath() throws {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("MultiProcessStoreHarnessTests-group-\(UUID().uuidString)", isDirectory: true)

        let urls = try StoreLocation.Role.allCases.map { role in
            try StoreLocation.resolve(role: role, containerProvider: { _ in container }).url
        }

        let distinctPaths = Set(urls.map(\.path))
        #expect(distinctPaths.count == 1, "every role must resolve to the SAME file — got \(distinctPaths)")

        let expected = container
            .appendingPathComponent("Lillist", isDirectory: true)
            .appendingPathComponent("Lillist.sqlite")
        #expect(urls.allSatisfy { $0.path == expected.path })
    }

    @Test("The path-pin holds even when roles resolve in a different order / interleaved with other calls")
    func pathPinHoldsUnderInterleaving() throws {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("MultiProcessStoreHarnessTests-group-\(UUID().uuidString)", isDirectory: true)

        let widget = try StoreLocation.resolve(role: .widget, containerProvider: { _ in container })
        let cli = try StoreLocation.resolve(role: .cli, containerProvider: { _ in container })
        let mainApp = try StoreLocation.resolve(role: .mainApp, containerProvider: { _ in container })
        let extensionProcess = try StoreLocation.resolve(role: .extensionProcess, containerProvider: { _ in container })

        #expect(widget.url == cli.url)
        #expect(cli.url == mainApp.url)
        #expect(mainApp.url == extensionProcess.url)
    }
}
