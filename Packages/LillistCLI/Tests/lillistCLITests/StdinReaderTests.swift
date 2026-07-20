import Testing
import Foundation
import LillistCore
@testable import lillist_cli

@Suite("CLI StdinReader")
struct StdinReaderTests {
    @Test("Reads lines from a data blob")
    func basic() {
        let data = "a\nb\nc\n".data(using: .utf8)!
        let lines = StdinReader.linesFromData(data)
        #expect(lines == ["a", "b", "c"])
    }

    @Test("Strips empty trailing line and surrounding whitespace")
    func trimming() {
        let data = "  alpha  \n\nbeta\n".data(using: .utf8)!
        let lines = StdinReader.linesFromData(data)
        #expect(lines == ["alpha", "beta"])
    }

    @Test("Token '-' indicates stdin")
    func isStdinSentinel() {
        #expect(StdinReader.isStdinSentinel("-") == true)
        #expect(StdinReader.isStdinSentinel("anything else") == false)
    }

    @Test("validateAllUUIDs accepts UUIDs and rejects non-UUIDs")
    func validateUUIDs() throws {
        let good = try StdinReader.validateAllUUIDs([UUID().uuidString, UUID().uuidString])
        #expect(good.count == 2)
        #expect(throws: LillistError.self) {
            _ = try StdinReader.validateAllUUIDs(["not-a-uuid"])
        }
    }
}
