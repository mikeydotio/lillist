import Testing
import Foundation
import OSLog
@testable import LillistCore

@Suite("LillistLog taxonomy")
struct LillistLogTests {
    @Test("Logging subsystem equals the crash-reporter subsystem so logs feed the report")
    func subsystemMatchesCrashReporter() {
        // This is the load-bearing contract: OSLogFetcher filters on
        // subsystem == CrashReporting.subsystemIdentifier, so the only
        // way the crash report's "Recent app logs" section is ever
        // non-empty is for production loggers to write on that exact
        // subsystem.
        #expect(LillistLog.subsystem == CrashReporting.subsystemIdentifier)
    }

    @Test("Every category exposes a usable Logger")
    func categoriesAreUsable() {
        // Loggers are value types; we can't read their category back,
        // but exercising each confirms the static members exist and
        // compile against the pinned subsystem.
        LillistLog.sync.debug("test sync")
        LillistLog.store.debug("test store")
        LillistLog.indexing.debug("test indexing")
        LillistLog.app.debug("test app")
        LillistLog.metrics.debug("test metrics")
    }

    @Test("Shared signposter is enabled in this build")
    func signposterEnabled() {
        // An OSSignposter built from a Logger is enabled; the disabled
        // singleton is what `.disabled` returns. We assert ours is not
        // that, so the migration/fetch intervals actually record.
        #expect(LillistLog.signposter.isEnabled)
    }
}
