import ArgumentParser
import Foundation
import LillistCore

public struct NoteCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "note",
        abstract: "Append a Markdown note to a task's journal."
    )

    @Argument(help: "Task token.")
    public var token: String

    @Argument(help: "Note body (Markdown).")
    public var body: String

    @OptionGroup public var globals: GlobalOptions

    public init() {}

    public func run() async throws {
        let p = try await CLIBridge.StoreLocator.openAppGroup()
        let id = try await CLIBridge.NoteHandler.run(token: token, body: body, persistence: p)
        if globals.quiet == false { print(id.uuidString) }
    }
}
