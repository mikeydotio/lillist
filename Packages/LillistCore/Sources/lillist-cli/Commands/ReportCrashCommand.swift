import ArgumentParser
import Foundation

public struct ReportCrashCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "report-crash",
        abstract: "Submit a crash report from the canary protocol (Plan 9)."
    )

    public init() {}

    public func run() throws {
        FileHandle.standardError.write(Data("Plan 9 (canary-based crash reporting) is not yet implemented. This verb is a placeholder.\n".utf8))
        // Exit 0 — design says "the user sends the email themselves." Until
        // Plan 9 lands, there's no payload to compose.
    }
}
