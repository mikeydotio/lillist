import ArgumentParser
import Foundation
import LillistCore

public struct NudgeCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "nudge", abstract: "Schedule a nudge for a task.")
    @Argument(help: "Task token.") public var token: String
    @Option(name: .long, help: "When to nudge (ISO-8601, relative DSL, or natural-language phrase).") public var at: String
    public init() {}
    public func run() async throws {
        let p = try await CLIBridge.StoreLocator.openAppGroup()
        let id = try await CLIBridge.NudgeHandler.run(token: token, atToken: at, persistence: p, now: Date(), calendar: Calendar.current)
        print(id.uuidString)
    }
}
