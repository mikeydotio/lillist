import Foundation
import LillistCore

/// Turns a positional task token into the list of tokens a batch command
/// should act on, centralizing the previously-duplicated
/// `if StdinReader.isStdinSentinel(...)` block. When the token is the stdin
/// sentinel (`-`), lines are read from `stdin`; otherwise the literal token is
/// returned as a single-element list.
///
/// Destructive verbs (delete, purge, move, status→closed) pass
/// `.requireUUIDs`, which rejects non-UUID stdin lines unless `allowFuzzy`
/// (the `--allow-fuzzy-from-stdin` flag) is set. Read-only callers pass
/// `.none`.
public enum BatchTokens {
    /// Whether stdin lines must be UUIDs for a destructive verb.
    public enum DestructiveGate {
        case none
        case requireUUIDs
    }

    /// Resolves the input token(s) for a batch command.
    ///
    /// - Parameters:
    ///   - token: The positional argument (`-` means "read stdin").
    ///   - stdin: Reader closure returning trimmed, non-empty stdin lines.
    ///     Injectable so tests don't touch the process's standard input.
    ///   - destructiveGate: UUID requirement for stdin lines.
    ///   - allowFuzzy: Bypasses `.requireUUIDs` when true.
    public static func resolveInput(
        token: String,
        stdin: () -> [String] = StdinReader.readAllLines,
        destructiveGate: DestructiveGate,
        allowFuzzy: Bool
    ) throws -> [String] {
        guard StdinReader.isStdinSentinel(token) else {
            return [token]
        }
        let raw = stdin()
        switch destructiveGate {
        case .none:
            return raw
        case .requireUUIDs:
            return allowFuzzy ? raw : (try StdinReader.validateAllUUIDs(raw))
        }
    }
}
