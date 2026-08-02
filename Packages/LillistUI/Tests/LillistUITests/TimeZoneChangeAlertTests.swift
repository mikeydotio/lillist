import Testing
import Foundation
@testable import LillistUI

/// `LIL-83` — the travel prompt's copy.
///
/// Worth testing because the strings carry the meaning: the user has to
/// understand, from one alert, that *both* answers are legitimate and what each
/// one does to their reminders. A vague message here turns a considered choice
/// into a coin flip.
@Suite("TimeZoneChangeAlert — copy")
struct TimeZoneChangeAlertTests {

    private func offer(count: Int) -> TimeZoneChangeAlert.Offer {
        .init(fromName: "New York", toName: "Los Angeles", count: count)
    }

    @Test("The action names the destination zone, so neither button is the vague one")
    func actionTitleNamesDestination() {
        #expect(TimeZoneChangeAlert.rescheduleTitle(offer(count: 3)) == "Use Los Angeles Times")
    }

    @Test("The message names both zones and the count")
    func messageIsSpecific() {
        let text = TimeZoneChangeAlert.message(offer(count: 3))
        #expect(text.contains("New York"))
        #expect(text.contains("Los Angeles"))
        #expect(text.contains("3"))
    }

    @Test("A single reminder reads grammatically")
    func singularGrammar() {
        let text = TimeZoneChangeAlert.message(offer(count: 1))
        #expect(text.contains("1 upcoming reminder is set"))
        #expect(text.contains("reminders") == false)
    }

    @Test("Several reminders read grammatically")
    func pluralGrammar() {
        let text = TimeZoneChangeAlert.message(offer(count: 4))
        #expect(text.contains("4 upcoming reminders are set"))
    }

    @Test("The message states both outcomes, not just the change")
    func bothOutcomesStated() {
        let text = TimeZoneChangeAlert.message(offer(count: 2))
        // "Keep" must be as visible as "move" — the prompt exists because the
        // app cannot know which the user means.
        #expect(text.lowercased().contains("keep"))
        #expect(text.lowercased().contains("move"))
    }
}
