import Testing
@testable import LillistCore

@Suite("CLIBridge.OutputFormat")
struct OutputFormatTests {
    @Test("Raw values are stable")
    func rawValues() {
        #expect(CLIBridge.OutputFormat.pretty.rawValue == "pretty")
        #expect(CLIBridge.OutputFormat.json.rawValue == "json")
        #expect(CLIBridge.OutputFormat.ndjson.rawValue == "ndjson")
        #expect(CLIBridge.OutputFormat.tsv.rawValue == "tsv")
    }
}
