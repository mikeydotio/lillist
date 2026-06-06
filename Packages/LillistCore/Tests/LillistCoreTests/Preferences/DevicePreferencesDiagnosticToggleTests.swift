import XCTest
@testable import LillistCore

final class DevicePreferencesDiagnosticToggleTests: XCTestCase {
    func test_defaults_to_DiagnosticDefaults_when_unset() async {
        let suite = "test.diag.\(UUID().uuidString)"
        let store = DevicePreferencesStore(suiteName: suite)
        let value = await store.diagnosticLoggingEnabled()
        XCTAssertEqual(value, DiagnosticDefaults.enabledByDefault)
    }

    func test_persists_explicit_value() async {
        let suite = "test.diag.\(UUID().uuidString)"
        let store = DevicePreferencesStore(suiteName: suite)
        await store.setDiagnosticLoggingEnabled(false)
        let reread = DevicePreferencesStore(suiteName: suite)
        let value = await reread.diagnosticLoggingEnabled()
        XCTAssertFalse(value)
    }

    func test_explicit_true_overrides_default() async {
        let suite = "test.diag.\(UUID().uuidString)"
        let store = DevicePreferencesStore(suiteName: suite)
        await store.setDiagnosticLoggingEnabled(true)
        let value = await store.diagnosticLoggingEnabled()
        XCTAssertTrue(value)
    }
}
