import Testing
@testable import LillistCore

@Suite("Smoke")
struct SmokeTests {
    @Test("Package builds and version is set")
    func versionExists() {
        #expect(LillistCoreInfo.version == "0.2.0")
    }
}
