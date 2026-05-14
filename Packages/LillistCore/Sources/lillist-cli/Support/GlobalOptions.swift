import ArgumentParser
import Foundation
import LillistCore

/// Shared output-and-color flags, embedded with `@OptionGroup` in every subcommand
/// that produces data on stdout.
public struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Emit a single JSON document on stdout.")
    public var json: Bool = false

    @Flag(name: .long, help: "Emit newline-delimited JSON (one object per line).")
    public var ndjson: Bool = false

    @Flag(name: .long, help: "Emit tab-separated values with a header row.")
    public var tsv: Bool = false

    @Flag(name: .long, help: "Suppress informational diagnostic output.")
    public var quiet: Bool = false

    @Flag(name: .long, help: "Disable ANSI color even on a TTY.")
    public var noColor: Bool = false

    public init() {}

    /// Resolves the active output format from the flags + config defaults.
    /// CLI flags win; otherwise config; otherwise `pretty`.
    public func resolveOutputFormat(default fallback: CLIBridge.OutputFormat) -> CLIBridge.OutputFormat {
        if json { return .json }
        if ndjson { return .ndjson }
        if tsv { return .tsv }
        return fallback
    }

    public func resolveColor() -> Bool {
        if noColor { return false }
        return TTY.shouldUseColor
    }
}
