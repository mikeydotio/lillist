import Testing
@testable import lillist_cli

@Suite("CLI argument parsing")
struct ArgumentParsingTests {
    @Test("`add` parses required title and optional flags")
    func addParses() throws {
        let cmd = try AddCommand.parse(["Buy milk", "--start", "tomorrow", "--tag", "Home", "--deadline", "+7d"])
        #expect(cmd.title == "Buy milk")
        #expect(cmd.start == "tomorrow")
        #expect(cmd.deadline == "+7d")
        #expect(cmd.tags == ["Home"])
    }

    @Test("`add` accepts multiple --tag occurrences")
    func addMultiTag() throws {
        let cmd = try AddCommand.parse(["X", "--tag", "A", "--tag", "B"])
        #expect(cmd.tags == ["A", "B"])
    }

    @Test("`add` without title is a usage error")
    func addMissingTitle() {
        #expect(throws: (any Error).self) {
            _ = try AddCommand.parse([])
        }
    }
}
