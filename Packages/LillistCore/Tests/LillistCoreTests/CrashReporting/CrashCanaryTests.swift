import Testing
import Foundation
@testable import LillistCore

@Suite("CrashCanary")
struct CrashCanaryTests {
    @Test("Initializer captures all fields")
    func init_capturesFields() {
        let when = Date(timeIntervalSince1970: 1_000_000)
        let canary = CrashCanary(
            pid: 42,
            startedAt: when,
            buildVersion: "0.9.0 (123)",
            hostname: "studio.local"
        )
        #expect(canary.pid == 42)
        #expect(canary.startedAt == when)
        #expect(canary.buildVersion == "0.9.0 (123)")
        #expect(canary.hostname == "studio.local")
    }

    @Test("Codable round-trip preserves all fields")
    func codable_roundTrip() throws {
        let original = CrashCanary(
            pid: 99,
            startedAt: Date(timeIntervalSince1970: 2_000_000),
            buildVersion: "1.0.0 (200)",
            hostname: "phone.local"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CrashCanary.self, from: data)
        #expect(decoded == original)
    }

    @Test("Two distinct canaries are not equal")
    func equatable_distinct() {
        let a = CrashCanary(pid: 1, startedAt: .now, buildVersion: "x", hostname: "h")
        let b = CrashCanary(pid: 2, startedAt: .now, buildVersion: "x", hostname: "h")
        #expect(a != b)
    }
}
