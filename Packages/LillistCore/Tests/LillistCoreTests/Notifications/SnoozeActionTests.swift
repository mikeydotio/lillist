import Testing
import Foundation
@testable import LillistCore

@Suite("SnoozeAction")
struct SnoozeActionTests {
    @Test("tenMinutes adds 10 minutes to delivery time")
    func tenMinutes() {
        let action = SnoozeAction.tenMinutes
        let delivered = Date(timeIntervalSince1970: 1_000_000)
        let spec = NotificationSpecStore.SpecRecord(
            id: UUID(), taskID: UUID(), kind: .defaultStart,
            offsetMinutes: nil, fireDate: nil, lastFiredAt: nil,
            snoozedUntil: nil, createdAt: nil
        )
        let result = action.compute(spec, delivered)
        #expect(result.timeIntervalSince(delivered) == 600)
    }

    @Test("oneHour adds 3600 seconds to delivery time")
    func oneHour() {
        let action = SnoozeAction.oneHour
        let delivered = Date(timeIntervalSince1970: 1_000_000)
        let spec = NotificationSpecStore.SpecRecord(
            id: UUID(), taskID: UUID(), kind: .defaultStart,
            offsetMinutes: nil, fireDate: nil, lastFiredAt: nil,
            snoozedUntil: nil, createdAt: nil
        )
        let result = action.compute(spec, delivered)
        #expect(result.timeIntervalSince(delivered) == 3600)
    }

    @Test("tomorrowMorning targets the next day at the given default hour:minute")
    func tomorrowMorning() {
        // Use UTC for a deterministic check.
        let cal = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 15
        components.hour = 22
        components.minute = 0
        components.timeZone = TimeZone(identifier: "UTC")
        let delivered = cal.date(from: components)!

        let action = SnoozeAction.tomorrowMorning(hour: 9, minute: 0, timeZone: TimeZone(identifier: "UTC")!)
        let spec = NotificationSpecStore.SpecRecord(
            id: UUID(), taskID: UUID(), kind: .defaultStart,
            offsetMinutes: nil, fireDate: nil, lastFiredAt: nil,
            snoozedUntil: nil, createdAt: nil
        )
        let result = action.compute(spec, delivered)

        var resultCal = Calendar(identifier: .gregorian)
        resultCal.timeZone = TimeZone(identifier: "UTC")!
        let resultComponents = resultCal.dateComponents([.year, .month, .day, .hour, .minute], from: result)
        #expect(resultComponents.year == 2026)
        #expect(resultComponents.month == 1)
        #expect(resultComponents.day == 16)
        #expect(resultComponents.hour == 9)
        #expect(resultComponents.minute == 0)
    }

    @Test("Action identity for category serialization")
    func identity() {
        #expect(SnoozeAction.tenMinutes.id == "snooze.10m")
        #expect(SnoozeAction.oneHour.id == "snooze.1h")
        #expect(SnoozeAction.tomorrowMorning(hour: 9, minute: 0, timeZone: .current).id == "snooze.tomorrow")
    }
}
