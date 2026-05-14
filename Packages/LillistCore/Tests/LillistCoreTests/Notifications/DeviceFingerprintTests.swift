import Testing
import Foundation
@testable import LillistCore

@Suite("DeviceFingerprint")
struct DeviceFingerprintTests {
    @Test("First read generates and persists a value")
    func generatesAndPersists() {
        let defaults = UserDefaults(suiteName: "test.devicefp.\(UUID().uuidString)")!
        let fp1 = DeviceFingerprint.current(defaults: defaults)
        let fp2 = DeviceFingerprint.current(defaults: defaults)
        #expect(fp1.isEmpty == false)
        #expect(fp1 == fp2)
    }

    @Test("Different defaults containers produce different fingerprints")
    func differentContainers() {
        let a = UserDefaults(suiteName: "test.devicefp.\(UUID().uuidString)")!
        let b = UserDefaults(suiteName: "test.devicefp.\(UUID().uuidString)")!
        let fpA = DeviceFingerprint.current(defaults: a)
        let fpB = DeviceFingerprint.current(defaults: b)
        #expect(fpA != fpB)
    }

    @Test("Fingerprint is URL-safe (no #, no spaces)")
    func urlSafe() {
        let defaults = UserDefaults(suiteName: "test.devicefp.\(UUID().uuidString)")!
        let fp = DeviceFingerprint.current(defaults: defaults)
        #expect(fp.contains("#") == false)
        #expect(fp.contains(" ") == false)
    }
}
