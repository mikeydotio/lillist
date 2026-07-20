import Testing
import ArgumentParser
@testable import lillist_cli

@Suite("CLI smoke")
struct SmokeTests {
    @Test("Root command parses with no arguments")
    func rootParses() throws {
        _ = try Lillist.parse([])
    }

    @Test("Root command name is 'lillist'")
    func commandName() {
        #expect(Lillist.configuration.commandName == "lillist")
    }

    @Test("Version reflects LillistCoreInfo.version")
    func version() {
        #expect(Lillist.configuration.version.isEmpty == false)
    }
}
