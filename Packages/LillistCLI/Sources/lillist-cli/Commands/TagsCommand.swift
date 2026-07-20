import ArgumentParser
import Foundation
import LillistCore

public struct TagsCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "tags",
        abstract: "Manage tags.",
        subcommands: [Ls.self, Add.self, Rename.self, Move.self, Delete.self, Tint.self],
        defaultSubcommand: Ls.self
    )

    public init() {}

    public struct Ls: AsyncParsableCommand {
        public static let configuration = CommandConfiguration(commandName: "ls", abstract: "List all tags.")
        @OptionGroup public var globals: GlobalOptions
        public init() {}
        public func run() async throws {
            let p = try await CLIBridge.StoreLocator.openAppGroup()
            let tags = try await CLIBridge.TagsHandler.list(persistence: p)
            switch globals.resolveOutputFormat(default: .pretty) {
            case .json:
                let data = try CLIBridge.TagRenderer.json(tags)
                print(String(data: data, encoding: .utf8) ?? "")
            case .ndjson:
                print(try CLIBridge.TagRenderer.ndjson(tags), terminator: "")
            case .tsv:
                print(CLIBridge.TagRenderer.tsv(tags), terminator: "")
            case .pretty:
                print(CLIBridge.TagRenderer.prettyTree(tags, color: globals.resolveColor()), terminator: "")
            }
        }
    }

    public struct Add: AsyncParsableCommand {
        public static let configuration = CommandConfiguration(commandName: "add", abstract: "Create a tag.")
        @Argument(help: "Tag name.") public var name: String
        @Option(name: .long, help: "Tint color as #RRGGBB.") public var tint: String?
        @Option(name: .long, help: "Parent tag name.") public var parent: String?
        public init() {}
        public func run() async throws {
            let p = try await CLIBridge.StoreLocator.openAppGroup()
            let id = try await CLIBridge.TagsHandler.add(name: name, tint: tint, parent: parent, persistence: p)
            print(id.uuidString)
        }
    }

    public struct Rename: AsyncParsableCommand {
        public static let configuration = CommandConfiguration(commandName: "rename", abstract: "Rename a tag.")
        @Argument public var name: String
        @Argument public var newName: String
        public init() {}
        public func run() async throws {
            let p = try await CLIBridge.StoreLocator.openAppGroup()
            try await CLIBridge.TagsHandler.rename(name: name, to: newName, persistence: p)
        }
    }

    public struct Move: AsyncParsableCommand {
        public static let configuration = CommandConfiguration(commandName: "move", abstract: "Reparent a tag.")
        @Argument public var name: String
        @Argument public var newParent: String?
        @Flag(name: .long) public var root: Bool = false
        public init() {}
        public func run() async throws {
            let p = try await CLIBridge.StoreLocator.openAppGroup()
            try await CLIBridge.TagsHandler.move(name: name, newParent: root ? nil : newParent, persistence: p)
        }
    }

    public struct Delete: AsyncParsableCommand {
        public static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a tag (cascades to descendants).")
        @Argument public var name: String
        public init() {}
        public func run() async throws {
            let p = try await CLIBridge.StoreLocator.openAppGroup()
            try await CLIBridge.TagsHandler.delete(name: name, persistence: p)
        }
    }

    public struct Tint: AsyncParsableCommand {
        public static let configuration = CommandConfiguration(commandName: "tint", abstract: "Set a tag's tint color.")
        @Argument public var name: String
        @Argument(help: "Hex color, e.g. #FF0000.") public var hex: String
        public init() {}
        public func run() async throws {
            let p = try await CLIBridge.StoreLocator.openAppGroup()
            try await CLIBridge.TagsHandler.tint(name: name, hex: hex, persistence: p)
        }
    }
}
