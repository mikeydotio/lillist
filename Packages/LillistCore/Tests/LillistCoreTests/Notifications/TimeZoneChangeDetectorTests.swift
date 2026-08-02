import Testing
import Foundation
@testable import LillistCore

/// `LIL-83` — detecting travel and offering to re-anchor reminders.
///
/// The design rule these enforce: **offer, never act unasked.** Keeping a 9am
/// New York reminder at 9am New York after you fly to California is a defensible
/// default, and so is moving it to 9am California. The app cannot know which the
/// user means, so it asks — and silence must change nothing.
@Suite("Time zone change — detection and re-anchoring")
struct TimeZoneChangeDetectorTests {

    private let newYork = TimeZone(identifier: "America/New_York")!
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

    private func suite() -> String { "TZDetectorTests-\(UUID().uuidString)" }

    private struct Harness {
        let controller: PersistenceController
        let tasks: TaskStore
        let specs: NotificationSpecStore
        let prefs: DevicePreferencesStore
        let detector: TimeZoneChangeDetector
    }

    private func harness() async throws -> Harness {
        let controller = try await TestStore.make()
        let specs = NotificationSpecStore(persistence: controller)
        let prefs = DevicePreferencesStore(suiteName: suite())
        return Harness(
            controller: controller,
            tasks: TaskStore(persistence: controller),
            specs: specs,
            prefs: prefs,
            detector: TimeZoneChangeDetector(
                persistence: controller, specStore: specs, devicePreferences: prefs
            )
        )
    }

    /// A task with a future start, plus one reminder anchored to `zone`.
    @discardableResult
    private func futureReminder(
        _ h: Harness,
        zone: TimeZone,
        startingIn interval: TimeInterval = 86_400
    ) async throws -> UUID {
        let taskID = try await h.tasks.create(title: "Take medication")
        try await h.tasks.update(id: taskID) { d in
            d.start = Date().addingTimeInterval(interval)
            d.startHasTime = false
        }
        return try await h.specs.add(
            taskID: taskID, kind: .defaultStart, offsetMinutes: nil, fireDate: nil,
            scheduledTimeZoneID: zone.identifier
        )
    }

    // MARK: - Detection

    @Test("The first ever observation records the zone and stays silent")
    func firstObservationIsSilent() async throws {
        let h = try await harness()
        try await futureReminder(h, zone: newYork)

        let change = try await h.detector.check(current: newYork)

        #expect(change == nil, "there is no 'from' zone yet, so there is nothing coherent to offer")
        #expect(await h.prefs.lastKnownTimeZoneID() == newYork.identifier)
    }

    @Test("Staying in the same zone offers nothing")
    func noChangeNoOffer() async throws {
        let h = try await harness()
        try await futureReminder(h, zone: newYork)
        _ = try await h.detector.check(current: newYork)

        #expect(try await h.detector.check(current: newYork) == nil)
    }

    @Test("Moving zones with a future reminder produces an offer")
    func travelProducesOffer() async throws {
        let h = try await harness()
        let specID = try await futureReminder(h, zone: newYork)
        _ = try await h.detector.check(current: newYork)

        let change = try #require(try await h.detector.check(current: losAngeles))

        #expect(change.from == newYork)
        #expect(change.to == losAngeles)
        #expect(change.affectedSpecIDs == [specID])
    }

    @Test("Moving zones with nothing to move accepts the new zone silently")
    func travelWithNoRemindersIsSilent() async throws {
        let h = try await harness()
        _ = try await h.detector.check(current: newYork)

        #expect(try await h.detector.check(current: losAngeles) == nil, "no question worth asking")
        #expect(await h.prefs.lastKnownTimeZoneID() == losAngeles.identifier)
    }

    // MARK: - Which reminders are eligible

    @Test("An already-fired reminder is never re-anchored")
    func firedRemindersAreExcluded() async throws {
        let h = try await harness()
        let specID = try await futureReminder(h, zone: newYork)
        try await h.specs.recordLastFired(id: specID, at: Date())
        _ = try await h.detector.check(current: newYork)

        // Moving it would re-arm a reminder that already did its job.
        #expect(try await h.detector.check(current: losAngeles) == nil)
    }

    @Test("A past-anchored reminder is never re-anchored")
    func pastRemindersAreExcluded() async throws {
        let h = try await harness()
        try await futureReminder(h, zone: newYork, startingIn: -86_400)
        _ = try await h.detector.check(current: newYork)

        #expect(try await h.detector.check(current: losAngeles) == nil)
    }

    @Test("A trashed task's reminder is never re-anchored")
    func trashedTasksAreExcluded() async throws {
        let h = try await harness()
        let taskID = try await h.tasks.create(title: "Take medication")
        try await h.tasks.update(id: taskID) { $0.start = Date().addingTimeInterval(86_400) }
        _ = try await h.specs.add(
            taskID: taskID, kind: .defaultStart, offsetMinutes: nil, fireDate: nil,
            scheduledTimeZoneID: newYork.identifier
        )
        try await h.tasks.softDelete(id: taskID)
        _ = try await h.detector.check(current: newYork)

        #expect(try await h.detector.check(current: losAngeles) == nil)
    }

    // MARK: - Accept / decline

    @Test("Accepting re-anchors every affected reminder and stops the prompt recurring")
    func acceptReanchors() async throws {
        let h = try await harness()
        let specID = try await futureReminder(h, zone: newYork)
        _ = try await h.detector.check(current: newYork)
        let change = try #require(try await h.detector.check(current: losAngeles))

        let moved = try await h.detector.accept(change)

        #expect(moved == 1)
        #expect(try await h.specs.fetch(id: specID).scheduledTimeZoneID == losAngeles.identifier)
        #expect(try await h.detector.check(current: losAngeles) == nil, "the same move must not be offered twice")
    }

    @Test("Declining leaves every reminder on its original zone and stops the prompt recurring")
    func declineChangesNothing() async throws {
        let h = try await harness()
        let specID = try await futureReminder(h, zone: newYork)
        _ = try await h.detector.check(current: newYork)
        let change = try #require(try await h.detector.check(current: losAngeles))

        await h.detector.decline(change)

        #expect(
            try await h.specs.fetch(id: specID).scheduledTimeZoneID == newYork.identifier,
            "silence must change nothing — declining is a real answer, not a deferral"
        )
        #expect(try await h.detector.check(current: losAngeles) == nil)
    }

    @Test("Travelling onward after declining offers again, from the declined zone")
    func onwardTravelOffersAgain() async throws {
        let h = try await harness()
        try await futureReminder(h, zone: newYork)
        _ = try await h.detector.check(current: newYork)
        let first = try #require(try await h.detector.check(current: losAngeles))
        await h.detector.decline(first)

        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let second = try #require(try await h.detector.check(current: tokyo))

        // `from` is where the device was, not where the reminders are anchored:
        // the user is being asked about *this* move.
        #expect(second.from == losAngeles)
        #expect(second.to == tokyo)
    }

    @Test("Accepting re-anchors every affected reminder, not just the first")
    func acceptMovesAll() async throws {
        let h = try await harness()
        let a = try await futureReminder(h, zone: newYork)
        let b = try await futureReminder(h, zone: newYork)
        _ = try await h.detector.check(current: newYork)
        let change = try #require(try await h.detector.check(current: losAngeles))

        #expect(change.affectedSpecIDs.count == 2)
        #expect(try await h.detector.accept(change) == 2)
        #expect(try await h.specs.fetch(id: a).scheduledTimeZoneID == losAngeles.identifier)
        #expect(try await h.specs.fetch(id: b).scheduledTimeZoneID == losAngeles.identifier)
    }
}
