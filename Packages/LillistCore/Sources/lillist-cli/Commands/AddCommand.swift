import ArgumentParser
import Foundation
import LillistCore

public struct AddCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Create a new task."
    )

    @Argument(help: "Title of the task.")
    public var title: String

    @Option(name: .long, help: "Start date/time (ISO-8601, relative DSL, or natural-language phrase).")
    public var start: String?

    @Option(name: .long, help: "Deadline date/time.")
    public var deadline: String?

    @Option(name: [.customLong("tag")], help: "Tag name. Repeat flag for multiple.")
    public var tags: [String] = []

    @Option(name: .long, help: "Initial notes (Markdown).")
    public var notes: String = ""

    @Option(name: .long, help: "Parent task ID or fuzzy title.")
    public var parent: String?

    @Option(name: .long, help: "Initial status: todo|started|blocked|closed.")
    public var status: String?

    @OptionGroup public var globals: GlobalOptions

    public init() {}

    public func run() async throws {
        let p = try await CLIBridge.StoreLocator.openAppGroup()
        let id = try await CLIBridge.AddHandler.run(
            title: title,
            notes: notes,
            startToken: start,
            deadlineToken: deadline,
            tagNames: tags,
            parentToken: parent,
            statusToken: status,
            persistence: p,
            now: Date(),
            calendar: Calendar.current
        )
        if globals.quiet == false {
            print(id.uuidString)
        }
    }
}
