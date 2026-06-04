import ArgumentParser
import Foundation
import LillistCore

public struct LsCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "ls",
        abstract: "List tasks matching the given filters."
    )

    @Option(name: .long, help: "Run the named saved smart filter.")
    public var saved: String?

    @Flag(name: .long, help: "Combinator: ANY of the predicates must match.")
    public var any: Bool = false

    @Flag(name: .long, help: "Combinator: ALL predicates must match (default).")
    public var all: Bool = false

    @Option(name: .customLong("tag"), help: "Include only tasks tagged with this name. Repeat for multiple.")
    public var tag: [String] = []

    @Option(name: .customLong("exclude-tag"), help: "Exclude tasks tagged with this name.")
    public var excludeTag: [String] = []

    @Option(name: .long, help: "Filter by status. Repeat for multiple.")
    public var status: [String] = []

    @Option(name: .customLong("deadline-before"), help: "Deadline strictly before this date.")
    public var deadlineBefore: String?

    @Option(name: .customLong("deadline-after"), help: "Deadline strictly after this date.")
    public var deadlineAfter: String?

    @Option(name: .customLong("start-before"), help: "Start strictly before this date.")
    public var startBefore: String?

    @Option(name: .customLong("start-after"), help: "Start strictly after this date.")
    public var startAfter: String?

    @Flag(name: .customLong("has-attachments"), help: "Only tasks with attachments.")
    public var hasAttachments: Bool = false

    @Flag(name: .long, help: "Only pinned tasks.")
    public var pinned: Bool = false

    @Flag(name: .customLong("include-trash"), help: "Include trashed tasks.")
    public var includeTrash: Bool = false

    @Option(name: .long, help: "Sort field (deadline, start, title, createdAt, modifiedAt, closedAt, status, manualPosition).")
    public var sort: String?

    @OptionGroup public var globals: GlobalOptions

    public init() {}

    public func run() async throws {
        let p = try await CLIBridge.StoreLocator.openAppGroup()
        let cfg = try CLIBridge.Config.read(from: CLIBridge.Config.defaultLocation())

        var flags = CLIBridge.FilterFlags()
        flags.combinator = any ? .any : .all
        flags.tags = tag
        flags.excludeTags = excludeTag
        flags.statuses = try status.map { token in
            guard let s = CLIBridge.AddHandler.status(from: token) else {
                throw LillistError.validationFailed([.init(field: "status", message: "unknown '\(token)'")])
            }
            return s
        }
        flags.deadlineBefore = deadlineBefore
        flags.deadlineAfter = deadlineAfter
        flags.startBefore = startBefore
        flags.startAfter = startAfter
        flags.hasAttachments = hasAttachments
        flags.pinned = pinned
        flags.includeTrash = includeTrash

        let sortField: SortField
        if let s = sort {
            guard let v = SortField(rawValue: s) else {
                throw LillistError.validationFailed([.init(field: "sort", message: "unknown sort '\(s)'")])
            }
            sortField = v
        } else {
            sortField = cfg.sort
        }

        let records = try await CLIBridge.LsHandler.run(
            flags: flags, savedFilterName: saved, sort: sortField,
            persistence: p, now: Date(), calendar: cfg.resolvedCalendar()
        )

        let format = globals.resolveOutputFormat(default: cfg.outputFormat)
        switch format {
        case .json:
            print(try CLIBridge.TaskRenderer.jsonString(records))
        case .ndjson:
            print(try CLIBridge.TaskRenderer.ndjson(records), terminator: "")
        case .tsv:
            print(try CLIBridge.TaskRenderer.tsv(records), terminator: "")
        case .pretty:
            print(CLIBridge.TaskRenderer.prettyTree(records, color: globals.resolveColor()), terminator: "")
        }
    }
}
