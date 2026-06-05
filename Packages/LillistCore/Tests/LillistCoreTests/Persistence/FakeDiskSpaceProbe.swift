import Foundation
@testable import LillistCore

/// Shared test double for `DiskSpaceProbing`, kept in its own file so it
/// can be co-compiled into both the LillistCore SPM test target and the
/// `Lillist-iOSAppHostedTests` target (which co-compiles
/// `MigrationCoordinatorTests`, where the disk-full pre-flight test
/// references this double). Mirrors the `FakePersistenceReconfigurer` /
/// `FakeUserNotificationCenter` shared-helper pattern.
struct FakeDiskSpaceProbe: DiskSpaceProbing {
    var availableBytes: Int64
    var footprintBytes: Int64
    func availableCapacity(forVolumeContaining url: URL) throws -> Int64 { availableBytes }
    func footprint(of storeURL: URL) throws -> Int64 { footprintBytes }
}
