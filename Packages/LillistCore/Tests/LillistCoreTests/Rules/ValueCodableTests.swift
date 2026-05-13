import Testing
import Foundation
@testable import LillistCore

@Suite("Value Codable")
struct ValueCodableTests {
    private func roundTrip(_ value: Value) throws -> Value {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(Value.self, from: data)
    }

    @Test("string round-trips")
    func string() throws {
        #expect(try roundTrip(.string("hello world")) == .string("hello world"))
    }

    @Test("uuidSet round-trips and is order-insensitive in equality? — sets are unordered")
    func uuidSet() throws {
        let a = UUID(); let b = UUID()
        let v: Value = .uuidSet([a, b])
        let decoded = try roundTrip(v)
        if case .uuidSet(let set) = decoded {
            #expect(set == Set([a, b]))
        } else {
            Issue.record("expected .uuidSet")
        }
    }

    @Test("statusSet round-trips")
    func statusSet() throws {
        let v: Value = .statusSet([.todo, .started])
        let decoded = try roundTrip(v)
        if case .statusSet(let set) = decoded {
            #expect(set == Set([.todo, .started]))
        } else {
            Issue.record("expected .statusSet")
        }
    }

    @Test("bool round-trips")
    func bool() throws {
        #expect(try roundTrip(.bool(true)) == .bool(true))
        #expect(try roundTrip(.bool(false)) == .bool(false))
    }

    @Test("absoluteDate round-trips (within millisecond precision)")
    func absoluteDate() throws {
        let now = Date(timeIntervalSince1970: 1_715_500_000)
        let decoded = try roundTrip(.absoluteDate(now))
        if case .absoluteDate(let d) = decoded {
            #expect(abs(d.timeIntervalSince(now)) < 0.001)
        } else {
            Issue.record("expected .absoluteDate")
        }
    }

    @Test("relativeDate round-trips")
    func relativeDate() throws {
        #expect(try roundTrip(.relativeDate(.daysFromNow(7))) == .relativeDate(.daysFromNow(7)))
        #expect(try roundTrip(.relativeDate(.endOfWeek)) == .relativeDate(.endOfWeek))
    }

    @Test("dayCount round-trips")
    func dayCount() throws {
        #expect(try roundTrip(.dayCount(14)) == .dayCount(14))
    }

    @Test("attachmentKind round-trips with and without ofKind")
    func attachmentKind() throws {
        #expect(try roundTrip(.attachmentKind(.init(present: true))) == .attachmentKind(.init(present: true)))
        #expect(try roundTrip(.attachmentKind(.init(present: true, kind: .image))) == .attachmentKind(.init(present: true, kind: .image)))
    }

    @Test("JSON output uses a stable 'kind' discriminator")
    func discriminator() throws {
        let data = try JSONEncoder().encode(Value.string("hi"))
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"kind\""))
        #expect(json.contains("\"string\""))
    }

    @Test("Unknown discriminator throws")
    func unknownDiscriminator() {
        let bogus = #"{"kind":"unicorn","value":1}"#.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Value.self, from: bogus)
        }
    }
}
