import Testing
@testable import LillistUI

@Suite("QuickCaptureParser")
struct QuickCaptureParserTests {
    @Test("Strips #tags and returns them separately")
    func tags() {
        let r = QuickCaptureParser.parse("Buy milk #errands #personal")
        #expect(r.title == "Buy milk")
        #expect(r.tags == ["errands", "personal"])
    }

    @Test("Strips ^datePhrase and parses to a relative DSL token")
    func date() {
        let r = QuickCaptureParser.parse("Call Alice ^tomorrow")
        #expect(r.title == "Call Alice")
        #expect(r.dateToken == "tomorrow")
    }

    @Test("Plain text — no tokens")
    func plain() {
        let r = QuickCaptureParser.parse("Just a task")
        #expect(r.title == "Just a task")
        #expect(r.tags.isEmpty)
        #expect(r.dateToken == nil)
    }
}
