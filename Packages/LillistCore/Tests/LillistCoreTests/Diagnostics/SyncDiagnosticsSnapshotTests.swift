import XCTest
@testable import LillistCore

/// Pins `SyncDiagnosticsSnapshot` — the CloudKit environment/provenance
/// signal added for issue #54. `resolveEnvironment` never touches real
/// entitlements in tests; `DictionaryEntitlementReader` stands in for
/// `SelfEntitlementReader` (which returns `nil` for everything under
/// unsigned `swift test`, so asserting against it would be meaningless).
final class SyncDiagnosticsSnapshotTests: XCTestCase {
    private struct DictionaryEntitlementReader: EntitlementReading {
        let values: [String: String]
        func stringValue(forEntitlement key: String) -> String? { values[key] }
    }

    // MARK: - resolveEnvironment: icloud-container-environment key

    func test_resolveEnvironment_iCloudKey_development() {
        let reader = DictionaryEntitlementReader(values: [
            SyncDiagnosticsSnapshot.iCloudEnvironmentEntitlementKey: "Development"
        ])
        XCTAssertEqual(SyncDiagnosticsSnapshot.resolveEnvironment(using: reader), .development)
    }

    func test_resolveEnvironment_iCloudKey_production() {
        let reader = DictionaryEntitlementReader(values: [
            SyncDiagnosticsSnapshot.iCloudEnvironmentEntitlementKey: "Production"
        ])
        XCTAssertEqual(SyncDiagnosticsSnapshot.resolveEnvironment(using: reader), .production)
    }

    func test_resolveEnvironment_iCloudKey_isCaseInsensitive() {
        let reader = DictionaryEntitlementReader(values: [
            SyncDiagnosticsSnapshot.iCloudEnvironmentEntitlementKey: "development"
        ])
        XCTAssertEqual(SyncDiagnosticsSnapshot.resolveEnvironment(using: reader), .development)
    }

    // MARK: - resolveEnvironment: aps-environment fallback (iOS has no iCloud key)

    func test_resolveEnvironment_fallsBackTo_apsEnvironment_iOSKey_development() {
        let reader = DictionaryEntitlementReader(values: [
            SyncDiagnosticsSnapshot.apsEnvironmentEntitlementKeyiOS: "development"
        ])
        XCTAssertEqual(SyncDiagnosticsSnapshot.resolveEnvironment(using: reader), .development)
    }

    func test_resolveEnvironment_fallsBackTo_apsEnvironment_iOSKey_production() {
        let reader = DictionaryEntitlementReader(values: [
            SyncDiagnosticsSnapshot.apsEnvironmentEntitlementKeyiOS: "production"
        ])
        XCTAssertEqual(SyncDiagnosticsSnapshot.resolveEnvironment(using: reader), .production)
    }

    func test_resolveEnvironment_fallsBackTo_apsEnvironment_macOSKey() {
        let reader = DictionaryEntitlementReader(values: [
            SyncDiagnosticsSnapshot.apsEnvironmentEntitlementKeymacOS: "production"
        ])
        XCTAssertEqual(SyncDiagnosticsSnapshot.resolveEnvironment(using: reader), .production)
    }

    // MARK: - Precedence: explicit iCloud key wins over the APS proxy

    func test_resolveEnvironment_iCloudKey_takesPrecedenceOver_apsEnvironment() {
        let reader = DictionaryEntitlementReader(values: [
            SyncDiagnosticsSnapshot.iCloudEnvironmentEntitlementKey: "Production",
            SyncDiagnosticsSnapshot.apsEnvironmentEntitlementKeyiOS: "development"
        ])
        XCTAssertEqual(SyncDiagnosticsSnapshot.resolveEnvironment(using: reader), .production)
    }

    // MARK: - Absent / unrecognized

    func test_resolveEnvironment_noEntitlementsPresent_isUnknown() {
        let reader = DictionaryEntitlementReader(values: [:])
        XCTAssertEqual(SyncDiagnosticsSnapshot.resolveEnvironment(using: reader), .unknown)
    }

    func test_resolveEnvironment_unrecognizedValue_isUnknown() {
        let reader = DictionaryEntitlementReader(values: [
            SyncDiagnosticsSnapshot.iCloudEnvironmentEntitlementKey: "Sandbox"
        ])
        XCTAssertEqual(SyncDiagnosticsSnapshot.resolveEnvironment(using: reader), .unknown)
    }

    // MARK: - SelfEntitlementReader under an unsigned test host

    func test_selfEntitlementReader_returnsNil_whenUnsigned() {
        // `swift test` runs unsigned, so every key must read back nil —
        // this is the exact seam that keeps production-path assertions out
        // of unit tests (see class doc).
        let reader = SelfEntitlementReader()
        XCTAssertNil(reader.stringValue(forEntitlement: SyncDiagnosticsSnapshot.iCloudEnvironmentEntitlementKey))
    }

    // MARK: - Codable round-trip

    func test_codable_roundTrip_preservesAllFields() throws {
        let original = SyncDiagnosticsSnapshot(
            cloudKitEnvironment: .production,
            cloudKitContainerIdentifier: "iCloud.app.lillist",
            accountStatusLabel: "available",
            syncMode: .iCloudSync,
            mirroredCount: 0,
            localCount: 22
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncDiagnosticsSnapshot.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_codable_roundTrip_everyEnvironmentCase() throws {
        for env: CloudKitEnvironment in [.development, .production, .unknown] {
            let snapshot = SyncDiagnosticsSnapshot(
                cloudKitEnvironment: env, cloudKitContainerIdentifier: "iCloud.app.lillist",
                accountStatusLabel: "available", syncMode: .localOnly,
                mirroredCount: 0, localCount: 0
            )
            let data = try JSONEncoder().encode(snapshot)
            let decoded = try JSONDecoder().decode(SyncDiagnosticsSnapshot.self, from: data)
            XCTAssertEqual(decoded.cloudKitEnvironment, env)
        }
    }

    // MARK: - make(...) assembly

    func test_make_assemblesFromInjectedReaderAndCounts() {
        let reader = DictionaryEntitlementReader(values: [
            SyncDiagnosticsSnapshot.iCloudEnvironmentEntitlementKey: "Development"
        ])
        let snapshot = SyncDiagnosticsSnapshot.make(
            reader: reader,
            containerIdentifier: "iCloud.app.lillist",
            accountState: .available,
            syncMode: .iCloudSync,
            counts: .init(local: 22, mirrored: 0)
        )
        XCTAssertEqual(snapshot.cloudKitEnvironment, .development)
        XCTAssertEqual(snapshot.cloudKitContainerIdentifier, "iCloud.app.lillist")
        XCTAssertEqual(snapshot.accountStatusLabel, "available")
        XCTAssertEqual(snapshot.syncMode, .iCloudSync)
        XCTAssertEqual(snapshot.localCount, 22)
        XCTAssertEqual(snapshot.mirroredCount, 0)
    }

    // MARK: - iCloudAccountState.diagnosticLabel

    func test_diagnosticLabel_everyCase() {
        XCTAssertEqual(iCloudAccountState.available.diagnosticLabel, "available")
        XCTAssertEqual(iCloudAccountState.noAccount.diagnosticLabel, "noAccount")
        XCTAssertEqual(iCloudAccountState.restricted.diagnosticLabel, "restricted")
        XCTAssertEqual(iCloudAccountState.accountChanged.diagnosticLabel, "accountChanged")
    }
}
