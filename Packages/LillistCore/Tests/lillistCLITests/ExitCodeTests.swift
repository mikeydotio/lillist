import Testing
import Foundation
import LillistCore
@testable import lillist_cli

@Suite("CLI ExitCode mapping")
struct ExitCodeTests {
    @Test("notFound → 3")
    func notFound() {
        #expect(ExitCode.fromLillistError(LillistError.notFound) == 3)
    }
    @Test("ambiguous → 4")
    func ambiguous() {
        #expect(ExitCode.fromLillistError(LillistError.ambiguous([])) == 4)
    }
    @Test("storeUnavailable → 5")
    func storeUnavailable() {
        #expect(ExitCode.fromLillistError(LillistError.storeUnavailable(reason: "x")) == 5)
    }
    @Test("validationFailed → 2")
    func validationFailed() {
        #expect(ExitCode.fromLillistError(LillistError.validationFailed([])) == 2)
    }
    @Test("Other LillistError cases → 1")
    func generic() {
        #expect(ExitCode.fromLillistError(LillistError.migrationRequired) == 1)
    }
}
