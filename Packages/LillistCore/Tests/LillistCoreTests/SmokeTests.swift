import Testing
@testable import LillistCore

@Suite("Smoke")
struct SmokeTests {
    @Test("Package builds and version is set")
    func versionExists() {
        #expect(LillistCore.version == "0.1.0")
    }
}
