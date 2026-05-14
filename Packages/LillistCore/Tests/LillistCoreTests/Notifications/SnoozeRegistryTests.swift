import Testing
import Foundation
@testable import LillistCore

@Suite("SnoozeRegistry")
struct SnoozeRegistryTests {
    @Test("Default registry contains tenMinutes, oneHour, tomorrowMorning")
    func defaults() async {
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let ids = await registry.actions.map(\.id)
        #expect(ids.contains("snooze.10m"))
        #expect(ids.contains("snooze.1h"))
        #expect(ids.contains("snooze.tomorrow"))
        #expect(ids.count == 3)
    }

    @Test("register appends a custom action")
    func registerCustom() async {
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let custom = SnoozeAction(id: "snooze.custom", displayName: "Custom") { _, d in d }
        await registry.register(custom)
        let ids = await registry.actions.map(\.id)
        #expect(ids.contains("snooze.custom"))
        #expect(ids.count == 4)
    }

    @Test("register replaces an action with the same id")
    func registerReplaces() async {
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let replacement = SnoozeAction(id: "snooze.10m", displayName: "Custom 10m") { _, d in d }
        await registry.register(replacement)
        let actions = await registry.actions
        let tenMinAction = actions.first { $0.id == "snooze.10m" }
        #expect(tenMinAction?.displayName == "Custom 10m")
        #expect(actions.count == 3)
    }

    @Test("action(id:) looks up a registered action")
    func lookupByID() async {
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let action = await registry.action(id: "snooze.10m")
        #expect(action?.id == "snooze.10m")
        let missing = await registry.action(id: "nope")
        #expect(missing == nil)
    }
}
