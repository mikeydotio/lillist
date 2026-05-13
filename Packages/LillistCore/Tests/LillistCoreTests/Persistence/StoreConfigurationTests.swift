import Testing
import Foundation
@testable import LillistCore

@Suite("StoreConfiguration")
struct StoreConfigurationTests {
    @Test("Default CloudKit container ID matches the design")
    func defaultContainerID() {
        let cfg = StoreConfiguration.inMemory
        #expect(cfg.cloudKitContainerIdentifier == "iCloud.com.mikeydotio.lillist")
    }

    @Test("Custom container ID is preserved")
    func customContainerID() {
        let cfg = StoreConfiguration.inMemory.withCloudKitContainer("iCloud.example.test")
        #expect(cfg.cloudKitContainerIdentifier == "iCloud.example.test")
    }

    @Test("Custom container ID is preserved for on-disk too")
    func customContainerIDOnDisk() {
        let url = URL(fileURLWithPath: "/tmp/Lillist.sqlite")
        let cfg = StoreConfiguration.onDisk(url: url).withCloudKitContainer("iCloud.example.test")
        #expect(cfg.cloudKitContainerIdentifier == "iCloud.example.test")
        if case .onDisk(let returnedURL) = cfg.storeKind {
            #expect(returnedURL == url)
        } else {
            Issue.record("storeKind should remain onDisk after container override")
        }
    }
}
