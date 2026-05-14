import Testing
@testable import LillistUI

@Suite("LillistUI Smoke")
struct SmokeTests {
    @Test("Package builds and version is set")
    func versionExists() {
        #expect(LillistUI.version == "0.1.0")
    }
}
