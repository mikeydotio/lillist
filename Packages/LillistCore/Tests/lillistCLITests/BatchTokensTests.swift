import Testing
import Foundation
import LillistCore
@testable import lillist_cli

@Suite("CLI BatchTokens")
struct BatchTokensTests {
    @Test("Non-sentinel token returns a single-element list verbatim")
    func singleToken() throws {
        let tokens = try BatchTokens.resolveInput(
            token: "Buy milk",
            stdin: { [] },
            destructiveGate: .requireUUIDs,
            allowFuzzy: false
        )
        #expect(tokens == ["Buy milk"])
    }

    @Test("Sentinel reads from stdin when the read-only gate is in effect")
    func stdinReadOnly() throws {
        let tokens = try BatchTokens.resolveInput(
            token: "-",
            stdin: { ["alpha", "beta"] },
            destructiveGate: .none,
            allowFuzzy: false
        )
        #expect(tokens == ["alpha", "beta"])
    }

    @Test("Destructive gate rejects non-UUID stdin lines unless allowed")
    func destructiveRejectsNonUUID() throws {
        #expect(throws: LillistError.self) {
            _ = try BatchTokens.resolveInput(
                token: "-",
                stdin: { ["not-a-uuid"] },
                destructiveGate: .requireUUIDs,
                allowFuzzy: false
            )
        }
    }

    @Test("Destructive gate is bypassed by allowFuzzy")
    func destructiveAllowFuzzy() throws {
        let tokens = try BatchTokens.resolveInput(
            token: "-",
            stdin: { ["not-a-uuid"] },
            destructiveGate: .requireUUIDs,
            allowFuzzy: true
        )
        #expect(tokens == ["not-a-uuid"])
    }

    @Test("Destructive gate accepts all-UUID stdin")
    func destructiveAcceptsUUIDs() throws {
        let u = UUID().uuidString
        let tokens = try BatchTokens.resolveInput(
            token: "-",
            stdin: { [u] },
            destructiveGate: .requireUUIDs,
            allowFuzzy: false
        )
        #expect(tokens == [u])
    }
}
