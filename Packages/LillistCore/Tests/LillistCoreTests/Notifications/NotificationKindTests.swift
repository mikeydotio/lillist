import Testing
@testable import LillistCore

@Suite("NotificationKind")
struct NotificationKindTests {
    @Test("Raw values are stable for persistence")
    func rawValuesStable() {
        #expect(NotificationKind.defaultStart.rawValue == 0)
        #expect(NotificationKind.defaultDeadline.rawValue == 1)
        #expect(NotificationKind.offsetStart.rawValue == 2)
        #expect(NotificationKind.offsetDeadline.rawValue == 3)
        #expect(NotificationKind.nudge.rawValue == 4)
    }

    @Test("All cases enumerable")
    func allCases() {
        #expect(NotificationKind.allCases.count == 5)
    }

    @Test("Anchor classifies kinds by their anchor field")
    func anchor() {
        #expect(NotificationKind.defaultStart.anchor == .start)
        #expect(NotificationKind.offsetStart.anchor == .start)
        #expect(NotificationKind.defaultDeadline.anchor == .deadline)
        #expect(NotificationKind.offsetDeadline.anchor == .deadline)
        #expect(NotificationKind.nudge.anchor == nil)
    }

    @Test("isOffset distinguishes the offset variants")
    func isOffset() {
        #expect(NotificationKind.offsetStart.isOffset == true)
        #expect(NotificationKind.offsetDeadline.isOffset == true)
        #expect(NotificationKind.defaultStart.isOffset == false)
        #expect(NotificationKind.defaultDeadline.isOffset == false)
        #expect(NotificationKind.nudge.isOffset == false)
    }

    @Test("Round-trip through Int16")
    func int16RoundTrip() {
        for kind in NotificationKind.allCases {
            let int16 = Int16(kind.rawValue)
            #expect(NotificationKind(rawValue: Int(int16)) == kind)
        }
    }
}
