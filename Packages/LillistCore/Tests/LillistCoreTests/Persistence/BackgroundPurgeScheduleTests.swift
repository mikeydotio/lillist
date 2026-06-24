import Testing
import Foundation
@testable import LillistCore

@Suite("BackgroundPurgeSchedule")
struct BackgroundPurgeScheduleTests {
    @Test("Task identifier is the stable, bundle-prefixed string")
    func identifierIsStable() {
        // The iOS Info.plist BGTaskSchedulerPermittedIdentifiers entry and
        // the BGProcessingTaskRequest must use exactly this string.
        #expect(BackgroundPurgeSchedule.taskIdentifier == "io.mikey.lillist.autopurge")
    }

    @Test("Earliest-begin interval is one day")
    func earliestBeginIsOneDay() {
        #expect(BackgroundPurgeSchedule.earliestBeginInterval == 24 * 60 * 60)
    }
}
