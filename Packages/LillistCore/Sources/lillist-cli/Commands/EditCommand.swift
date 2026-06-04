import ArgumentParser
import Foundation
import LillistCore

public struct EditCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "edit",
        abstract: "Modify fields of an existing task."
    )

    @Argument(help: "Task UUID, UUID prefix, or fuzzy title token.")
    public var token: String

    @Option(name: .long, help: "New title.")
    public var title: String?

    @Option(name: .long, help: "New notes (Markdown).")
    public var notes: String?

    @Option(name: .long, help: "New start date/time.")
    public var start: String?

    @Option(name: .long, help: "New deadline date/time.")
    public var deadline: String?

    @OptionGroup public var globals: GlobalOptions

    public init() {}

    public func run() async throws {
        let p = try await CLIBridge.StoreLocator.openAppGroup()
        let cfg = try CLIBridge.Config.read(from: CLIBridge.Config.defaultLocation())
        try await CLIBridge.EditHandler.run(
            token: token,
            newTitle: title, newNotes: notes,
            startToken: start, deadlineToken: deadline,
            persistence: p, now: Date(), calendar: cfg.resolvedCalendar()
        )
    }
}
