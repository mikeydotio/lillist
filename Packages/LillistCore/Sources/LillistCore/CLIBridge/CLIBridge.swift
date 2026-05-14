import Foundation

/// Top-level namespace for command-line and App-Intents-shared handlers.
///
/// Per design Section 6 ("App Intents alignment"): the CLI and the Shortcuts
/// actions share their implementation through `CLIBridge`. Anything user-facing
/// (verb parsing, output formatting) belongs to the caller; anything load-bearing
/// (resolution, validation, I/O) lives here.
public enum CLIBridge {}
