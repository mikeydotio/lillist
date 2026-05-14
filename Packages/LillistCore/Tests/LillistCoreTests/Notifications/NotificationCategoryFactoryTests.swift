import Testing
import Foundation
import UserNotifications
@testable import LillistCore

@Suite("NotificationCategoryFactory")
struct NotificationCategoryFactoryTests {
    @Test("Produces one category per NotificationKind")
    func oneCategoryPerKind() async {
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let categories = await NotificationCategoryFactory.makeCategories(registry: registry)
        let ids = Set(categories.map(\.identifier))
        #expect(ids.contains("lillist.defaultStart"))
        #expect(ids.contains("lillist.defaultDeadline"))
        #expect(ids.contains("lillist.offsetStart"))
        #expect(ids.contains("lillist.offsetDeadline"))
        #expect(ids.contains("lillist.nudge"))
    }

    @Test("Each category includes one action per registered snooze action")
    func actionsPerCategory() async {
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let categories = await NotificationCategoryFactory.makeCategories(registry: registry)
        for category in categories where category.identifier != MorningSummary.categoryID {
            #expect(category.actions.count == 3)
            let actionIDs = Set(category.actions.map(\.identifier))
            #expect(actionIDs.contains("snooze.10m"))
            #expect(actionIDs.contains("snooze.1h"))
            #expect(actionIDs.contains("snooze.tomorrow"))
        }
    }

    @Test("Custom snooze additions show up in next factory call")
    func customAction() async {
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        await registry.register(SnoozeAction(id: "snooze.custom", displayName: "Custom") { _, d in d })
        let categories = await NotificationCategoryFactory.makeCategories(registry: registry)
        for category in categories where category.identifier == "lillist.nudge" {
            let actionIDs = Set(category.actions.map(\.identifier))
            #expect(actionIDs.contains("snooze.custom"))
        }
    }

    @Test("Scheduler.bootstrap publishes categories to the center")
    func bootstrapPublishesCategories() async throws {
        let p = try await TestStore.make()
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: .current
        )
        await scheduler.bootstrap()
        let categoryIDs = await fake.categoryIdentifiers()
        #expect(categoryIDs.contains("lillist.defaultStart"))
        #expect(categoryIDs.contains("lillist.defaultDeadline"))
        #expect(categoryIDs.contains("lillist.offsetStart"))
        #expect(categoryIDs.contains("lillist.offsetDeadline"))
        #expect(categoryIDs.contains("lillist.nudge"))
        #expect(categoryIDs.contains(MorningSummary.categoryID))
    }
}
