import Testing
import Foundation
@testable import LillistCore

@Suite("RecurrenceRule interval normalization")
struct RecurrenceRuleNormalizationTests {
    static let allFrequencies: [RecurrenceRule.Frequency] = [.daily, .weekly, .monthly, .yearly]

    // MARK: - Memberwise init boundary

    @Test("init clamps interval 0 to 1 across all frequencies")
    func initClampsZero() throws {
        for freq in Self.allFrequencies {
            let rule = RecurrenceRule.CalendarRule(freq: freq, interval: 0)
            #expect(rule.interval == 1)
        }
    }

    @Test("init clamps negative interval to 1 across all frequencies")
    func initClampsNegative() throws {
        for freq in Self.allFrequencies {
            let rule = RecurrenceRule.CalendarRule(freq: freq, interval: -1)
            #expect(rule.interval == 1)
        }
    }

    @Test("init preserves a valid positive interval")
    func initPreservesValid() throws {
        for freq in Self.allFrequencies {
            let rule = RecurrenceRule.CalendarRule(freq: freq, interval: 3)
            #expect(rule.interval == 3)
        }
    }

    // MARK: - JSON decode boundary (CloudKit / Importer / CLI surface)

    /// Builds raw JSON matching `RecurrenceRule`'s discriminator layout with an
    /// arbitrary (possibly invalid) interval, bypassing the memberwise init.
    private func calendarJSON(freq: RecurrenceRule.Frequency, interval: Int) -> Data {
        let json = """
        {"type":"calendar","rule":{"freq":"\(freq.rawValue)","interval":\(interval)}}
        """
        return Data(json.utf8)
    }

    @Test("decode clamps interval 0 to 1 across all frequencies")
    func decodeClampsZero() throws {
        for freq in Self.allFrequencies {
            let decoded = try JSONDecoder().decode(
                RecurrenceRule.self,
                from: calendarJSON(freq: freq, interval: 0)
            )
            guard case .calendar(let cal) = decoded else {
                Issue.record("expected .calendar for \(freq)")
                continue
            }
            #expect(cal.interval == 1)
            #expect(cal.freq == freq)
        }
    }

    @Test("decode clamps negative interval to 1 across all frequencies")
    func decodeClampsNegative() throws {
        for freq in Self.allFrequencies {
            let decoded = try JSONDecoder().decode(
                RecurrenceRule.self,
                from: calendarJSON(freq: freq, interval: -1)
            )
            guard case .calendar(let cal) = decoded else {
                Issue.record("expected .calendar for \(freq)")
                continue
            }
            #expect(cal.interval == 1)
        }
    }

    @Test("decode preserves a valid positive interval")
    func decodePreservesValid() throws {
        let decoded = try JSONDecoder().decode(
            RecurrenceRule.self,
            from: calendarJSON(freq: .weekly, interval: 2)
        )
        guard case .calendar(let cal) = decoded else {
            Issue.record("expected .calendar")
            return
        }
        #expect(cal.interval == 2)
    }

    @Test("decode preserves byDay/count/until while clamping interval")
    func decodePreservesOtherFieldsWhileClamping() throws {
        // Weekday's Codable raw values are the RFC-5545 codes ("MO", "FR"),
        // not the case names — see Weekday.swift.
        let json = """
        {"type":"calendar","rule":{"freq":"weekly","interval":0,"byDay":["MO","FR"],"count":5}}
        """
        let decoded = try JSONDecoder().decode(RecurrenceRule.self, from: Data(json.utf8))
        guard case .calendar(let cal) = decoded else {
            Issue.record("expected .calendar")
            return
        }
        #expect(cal.interval == 1)
        #expect(cal.byDay == [.monday, .friday])
        #expect(cal.count == 5)
    }
}
