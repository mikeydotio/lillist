import Foundation
import Testing
@testable import LillistCore

@Suite("Op")
struct OpTests {
    @Test("Raw values are stable")
    func rawValuesStable() {
        #expect(Op.contains.rawValue == "contains")
        #expect(Op.equals.rawValue == "equals")
        #expect(Op.startsWith.rawValue == "startsWith")
        #expect(Op.includesAny.rawValue == "includesAny")
        #expect(Op.includesAll.rawValue == "includesAll")
        #expect(Op.excludesAll.rawValue == "excludesAll")
        #expect(Op.is.rawValue == "is")
        #expect(Op.isNot.rawValue == "isNot")
        #expect(Op.before.rawValue == "before")
        #expect(Op.after.rawValue == "after")
        #expect(Op.on.rawValue == "on")
        #expect(Op.withinLastDays.rawValue == "withinLastDays")
        #expect(Op.withinNextDays.rawValue == "withinNextDays")
        #expect(Op.isSet.rawValue == "isSet")
        #expect(Op.isUnset.rawValue == "isUnset")
        #expect(Op.equalsModifiedAt.rawValue == "equalsModifiedAt")
        #expect(Op.isDescendantOf.rawValue == "isDescendantOf")
        #expect(Op.isAncestorOf.rawValue == "isAncestorOf")
    }

    @Test("All design Section 5 operators enumerated")
    func allCases() {
        #expect(Op.allCases.count == 18)
    }

    @Test("Codable round-trips")
    func codable() throws {
        for op in Op.allCases {
            let data = try JSONEncoder().encode(op)
            let decoded = try JSONDecoder().decode(Op.self, from: data)
            #expect(decoded == op)
        }
    }
}
