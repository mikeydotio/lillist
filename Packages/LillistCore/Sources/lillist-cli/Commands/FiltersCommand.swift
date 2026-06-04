import ArgumentParser
import Foundation
import LillistCore

public struct FiltersCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "filters",
        abstract: "Manage saved smart filters.",
        subcommands: [Ls.self, Show.self, Run.self, Save.self, Delete.self],
        defaultSubcommand: Ls.self
    )

    public init() {}

    public struct Ls: AsyncParsableCommand {
        public static let configuration = CommandConfiguration(commandName: "ls", abstract: "List all saved filters.")
        @OptionGroup public var globals: GlobalOptions
        public init() {}
        public func run() async throws {
            let p = try await CLIBridge.StoreLocator.openAppGroup()
            let filters = try await CLIBridge.FiltersHandler.list(persistence: p)
            let summaries = filters.map { f in
                CLIBridge.FilterRenderer.PrettyFilterSummary(
                    id: f.id, name: f.name, isPinned: f.isPinned,
                    tintColor: f.tintColor, sortField: f.sortField, sortAscending: f.sortAscending
                )
            }
            print(CLIBridge.FilterRenderer.prettyList(summaries, color: globals.resolveColor()), terminator: "")
        }
    }

    public struct Show: AsyncParsableCommand {
        public static let configuration = CommandConfiguration(commandName: "show", abstract: "Show a saved filter's predicate group.")
        @Argument public var name: String
        public init() {}
        public func run() async throws {
            let p = try await CLIBridge.StoreLocator.openAppGroup()
            let f = try await CLIBridge.FiltersHandler.show(name: name, persistence: p)
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys, .prettyPrinted]
            let data = try enc.encode(f.group)
            print(String(data: data, encoding: .utf8) ?? "")
        }
    }

    public struct Run: AsyncParsableCommand {
        public static let configuration = CommandConfiguration(commandName: "run", abstract: "Run a saved filter and print results.")
        @Argument public var name: String
        @Option(name: .long) public var sort: String?
        @OptionGroup public var globals: GlobalOptions
        public init() {}
        public func run() async throws {
            let p = try await CLIBridge.StoreLocator.openAppGroup()
            let cfg = try CLIBridge.Config.read(from: CLIBridge.Config.defaultLocation())
            let sortField: SortField
            if let token = sort {
                guard let v = SortField(rawValue: token) else {
                    throw LillistError.validationFailed([.init(field: "sort", message: "unknown '\(token)'")])
                }
                sortField = v
            } else {
                sortField = cfg.sort
            }
            let records = try await CLIBridge.FiltersHandler.run(
                name: name, sort: sortField, persistence: p, now: Date(), calendar: cfg.resolvedCalendar()
            )
            switch globals.resolveOutputFormat(default: cfg.outputFormat) {
            case .json: print(try CLIBridge.TaskRenderer.jsonString(records))
            case .ndjson: print(try CLIBridge.TaskRenderer.ndjson(records), terminator: "")
            case .tsv: print(try CLIBridge.TaskRenderer.tsv(records), terminator: "")
            case .pretty: print(CLIBridge.TaskRenderer.prettyTree(records, color: globals.resolveColor()), terminator: "")
            }
        }
    }

    public struct Save: AsyncParsableCommand {
        public static let configuration = CommandConfiguration(commandName: "save", abstract: "Save the current filter flags as a named smart filter.")
        @Argument public var name: String
        @Option(name: .customLong("tag")) public var tag: [String] = []
        @Option(name: .long) public var status: [String] = []
        @Option(name: .long) public var sort: String?
        public init() {}
        public func run() async throws {
            let p = try await CLIBridge.StoreLocator.openAppGroup()
            let cfg = try CLIBridge.Config.read(from: CLIBridge.Config.defaultLocation())
            var flags = CLIBridge.FilterFlags()
            flags.tags = tag
            flags.statuses = try status.map {
                guard let s = CLIBridge.AddHandler.status(from: $0) else {
                    throw LillistError.validationFailed([.init(field: "status", message: "unknown '\($0)'")])
                }
                return s
            }
            let group = try await flags.toPredicateGroup(persistence: p, now: Date(), calendar: cfg.resolvedCalendar())
            let sortField: SortField
            if let s = sort {
                guard let v = SortField(rawValue: s) else {
                    throw LillistError.validationFailed([.init(field: "sort", message: "unknown '\(s)'")])
                }
                sortField = v
            } else {
                sortField = .deadline
            }
            let id = try await CLIBridge.FiltersHandler.save(name: name, group: group, sortField: sortField, persistence: p)
            print(id.uuidString)
        }
    }

    public struct Delete: AsyncParsableCommand {
        public static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a saved filter.")
        @Argument public var name: String
        public init() {}
        public func run() async throws {
            let p = try await CLIBridge.StoreLocator.openAppGroup()
            try await CLIBridge.FiltersHandler.delete(name: name, persistence: p)
        }
    }
}
