import Testing
import Foundation
@testable import LillistCore

@Suite("RecurrenceRule coding")
struct RecurrenceRuleCodingTests {
    @Test("Round-trip daily calendar rule")
    func dailyRoundTrip() throws {
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(RecurrenceRule.self, from: data)
        #expect(decoded == rule)
    }

    @Test("Round-trip weekly with byDay")
    func weeklyByDay() throws {
        let rule = RecurrenceRule.calendar(.init(
            freq: .weekly,
            interval: 2,
            byDay: [.monday, .wednesday, .friday]
        ))
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(RecurrenceRule.self, from: data)
        #expect(decoded == rule)
    }

    @Test("Round-trip monthly with byMonthDay + bySetPos + count")
    func monthlyComplex() throws {
        let rule = RecurrenceRule.calendar(.init(
            freq: .monthly,
            interval: 1,
            byMonthDay: [15],
            bySetPos: [1],
            count: 12
        ))
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(RecurrenceRule.self, from: data)
        #expect(decoded == rule)
    }

    @Test("Round-trip yearly with until")
    func yearlyUntil() throws {
        let until = Date(timeIntervalSince1970: 1_800_000_000)
        let rule = RecurrenceRule.calendar(.init(freq: .yearly, interval: 1, until: until))
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(RecurrenceRule.self, from: data)
        #expect(decoded == rule)
    }

    @Test("Round-trip after-completion rule")
    func afterCompletionRoundTrip() throws {
        let rule = RecurrenceRule.afterCompletion(.init(interval: 86_400 * 3))
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(RecurrenceRule.self, from: data)
        #expect(decoded == rule)
    }

    @Test("Type discriminator is stable across encodes")
    func discriminatorStable() throws {
        let cal = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        let after = RecurrenceRule.afterCompletion(.init(interval: 60))
        let calJSON = String(data: try JSONEncoder().encode(cal), encoding: .utf8)!
        let afterJSON = String(data: try JSONEncoder().encode(after), encoding: .utf8)!
        #expect(calJSON.contains("\"type\":\"calendar\""))
        #expect(afterJSON.contains("\"type\":\"afterCompletion\""))
    }

    @Test("Unknown type discriminator rejects with decoding error")
    func unknownTypeRejected() {
        let bogus = "{\"type\":\"never-heard-of-it\"}"
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                RecurrenceRule.self,
                from: Data(bogus.utf8)
            )
        }
    }
}
