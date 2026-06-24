import Testing
@testable import LillistCore

@Suite("CrashReporting smoke")
struct CrashReportingSmokeTests {
    @Test("Namespace exists and exposes a stable version tag")
    func namespaceExists() {
        #expect(CrashReporting.subsystemIdentifier == "app.lillist.crash")
    }
}
