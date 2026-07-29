import Testing
import Foundation
@testable import LillistCore

/// `StoreLocation` is the canonical, single-authority resolver for X1/X2/X15:
/// every process (main app, extension, widget, CLI) must resolve the
/// identical App-Group file path, and only `.mainApp` may arm CloudKit
/// mirroring. `containerProvider` stands in for
/// `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`, which
/// requires real App Group entitlements no unsigned `swift test` process
/// has — and which, unsandboxed, appears to always succeed regardless of
/// group ID (confirmed by the pre-existing `StoreLocatorTests`/
/// `GatedPersistenceResolverTests`, which pass today using made-up group
/// IDs against the real API) — so the "container unreachable" branch is
/// only testable through this seam.
@Suite("StoreLocation")
struct StoreLocationTests {
    private func tempContainer() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("StoreLocationTests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("Every role resolves to the identical file URL for the same App Group container (X1/X2 path-pin)")
    func allRolesResolveToIdenticalPath() throws {
        let container = tempContainer()
        let urls = try StoreLocation.Role.allCases.map { role in
            try StoreLocation.resolve(role: role, containerProvider: { _ in container }).url
        }
        #expect(Set(urls).count == 1)
        #expect(urls.first == container.appendingPathComponent("Lillist", isDirectory: true).appendingPathComponent("Lillist.sqlite"))
    }

    @Test("Resolving creates the Lillist directory inside the App Group container")
    func resolveCreatesDirectory() throws {
        let container = tempContainer()
        _ = try StoreLocation.resolve(role: .mainApp, containerProvider: { _ in container })
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: container.appendingPathComponent("Lillist", isDirectory: true).path,
            isDirectory: &isDirectory
        )
        #expect(exists)
        #expect(isDirectory.boolValue)
    }

    @Test("Only mainApp may arm CloudKit mirroring")
    func onlyMainAppMirrors() {
        #expect(StoreLocation.Role.mainApp.mayArmCloudKitMirroring == true)
        #expect(StoreLocation.Role.extensionProcess.mayArmCloudKitMirroring == false)
        #expect(StoreLocation.Role.widget.mayArmCloudKitMirroring == false)
        #expect(StoreLocation.Role.cli.mayArmCloudKitMirroring == false)
    }

    @Test("Container-unreachable throws storeUnavailable for every role")
    func containerUnreachableThrows() {
        for role in StoreLocation.Role.allCases {
            #expect(throws: LillistError.self) {
                _ = try StoreLocation.resolve(role: role, containerProvider: { _ in nil })
            }
        }
    }

    @Test("CLI's container-unreachable message keeps its install hint")
    func cliUnreachableMessageMentionsInstall() {
        do {
            _ = try StoreLocation.resolve(role: .cli, containerProvider: { _ in nil })
            Issue.record("expected storeUnavailable")
        } catch let LillistError.storeUnavailable(reason) {
            #expect(reason.contains("Install"))
        } catch {
            Issue.record("expected LillistError.storeUnavailable, got \(error)")
        }
    }

    @Test("Non-CLI roles get a generic container-unreachable message")
    func nonCLIUnreachableMessageIsGeneric() {
        for role in [StoreLocation.Role.mainApp, .extensionProcess, .widget] {
            do {
                _ = try StoreLocation.resolve(role: role, containerProvider: { _ in nil })
                Issue.record("expected storeUnavailable for \(role)")
            } catch let LillistError.storeUnavailable(reason) {
                #expect(reason.isEmpty == false)
                #expect(reason.contains("Install") == false)
            } catch {
                Issue.record("expected LillistError.storeUnavailable, got \(error)")
            }
        }
    }

    @Test("Default App Group identifier matches the entitlement shared by every process")
    func defaultAppGroupIdentifier() {
        #expect(StoreLocation.defaultAppGroupIdentifier == "group.app.lillist")
    }

    @Test("makeConfiguration carries the resolved URL and requested syncMode")
    func makeConfigurationCarriesURLAndSyncMode() throws {
        let container = tempContainer()
        let location = try StoreLocation.resolve(role: .mainApp, containerProvider: { _ in container })
        let config = location.makeConfiguration(syncMode: .localOnly)
        #expect(config.syncMode == .localOnly)
        if case .onDisk(let url) = config.storeKind {
            #expect(url == location.url)
        } else {
            Issue.record("expected onDisk storeKind")
        }
    }

    @Test("makeConfiguration sets armsCloudKitMirroring from the role, mainApp true")
    func makeConfigurationMirroringMainApp() throws {
        let container = tempContainer()
        let location = try StoreLocation.resolve(role: .mainApp, containerProvider: { _ in container })
        #expect(location.makeConfiguration(syncMode: .iCloudSync).armsCloudKitMirroring == true)
    }

    @Test("makeConfiguration sets armsCloudKitMirroring from the role, non-mainApp false", arguments: [
        StoreLocation.Role.extensionProcess, .widget, .cli
    ])
    func makeConfigurationMirroringNonMainApp(role: StoreLocation.Role) throws {
        let container = tempContainer()
        let location = try StoreLocation.resolve(role: role, containerProvider: { _ in container })
        #expect(location.makeConfiguration(syncMode: .iCloudSync).armsCloudKitMirroring == false)
    }

    @Test("makeConfiguration defaults the CloudKit container identifier to the design's production container")
    func makeConfigurationDefaultContainerIdentifier() throws {
        let container = tempContainer()
        let location = try StoreLocation.resolve(role: .mainApp, containerProvider: { _ in container })
        #expect(location.makeConfiguration(syncMode: .iCloudSync).cloudKitContainerIdentifier == StoreConfiguration.defaultCloudKitContainerIdentifier)
    }
}
