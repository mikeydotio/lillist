import Testing
import Foundation
@testable import LillistCore

@Suite("Predicate Codable")
struct PredicateCodableTests {
    @Test("Leaf round-trips")
    func leafRoundTrip() throws {
        let leaf = Leaf(field: .title, op: .contains, value: .string("design"))
        let data = try JSONEncoder().encode(leaf)
        let decoded = try JSONDecoder().decode(Leaf.self, from: data)
        #expect(decoded == leaf)
    }

    @Test("Flat group with two leaves round-trips")
    func flatGroupRoundTrip() throws {
        let g = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .title, op: .contains, value: .string("foo"))),
            .leaf(.init(field: .status, op: .is, value: .statusSet([.todo])))
        ])
        let data = try JSONEncoder().encode(g)
        let decoded = try JSONDecoder().decode(PredicateGroup.self, from: data)
        #expect(decoded.combinator == .all)
        #expect(decoded.predicates.count == 2)
    }

    @Test("Predicate with nested group round-trips")
    func nestedGroupRoundTrip() throws {
        let p: LillistCore.Predicate = .group(.init(combinator: .all, predicates: [
            .leaf(.init(field: .title, op: .contains, value: .string("a"))),
            .group(.init(combinator: .any, predicates: [
                .leaf(.init(field: .status, op: .is, value: .statusSet([.todo]))),
                .leaf(.init(field: .status, op: .is, value: .statusSet([.started])))
            ]))
        ]))
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(LillistCore.Predicate.self, from: data)
        if case .group(let g) = decoded {
            #expect(g.predicates.count == 2)
            if case .group(let inner) = g.predicates[1] {
                #expect(inner.combinator == .any)
                #expect(inner.predicates.count == 2)
            } else {
                Issue.record("expected inner group")
            }
        } else {
            Issue.record("expected outer group")
        }
    }

    @Test("Predicate JSON uses 'type' discriminator")
    func discriminator() throws {
        let p: LillistCore.Predicate = .leaf(.init(field: .title, op: .contains, value: .string("x")))
        let data = try JSONEncoder().encode(p)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"type\""))
        #expect(json.contains("\"leaf\""))
    }

    @Test("Unknown Predicate type throws on decode")
    func unknownType() {
        let bogus = #"{"type":"sandwich","payload":{}}"#.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(LillistCore.Predicate.self, from: bogus)
        }
    }
}
