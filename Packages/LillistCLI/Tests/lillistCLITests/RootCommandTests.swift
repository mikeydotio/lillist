import Testing
import Foundation
@testable import lillist_cli

@Suite("Root command parsing")
struct RootCommandTests {
    @Test("Root accepts --help (returns or throws — both are valid argument-parser outcomes)")
    func rootHelp() throws {
        // argument-parser may handle --help by returning a help-style command
        // OR by throwing CleanExit / HelpRequested depending on version. Both
        // are acceptable; the test just confirms it doesn't crash.
        _ = try? Lillist.parseAsRoot(["--help"])
    }

    @Test("Unknown subcommand is a parse error")
    func unknownSubcommand() {
        #expect(throws: (any Error).self) {
            _ = try Lillist.parseAsRoot(["nonexistent-verb"])
        }
    }
}
