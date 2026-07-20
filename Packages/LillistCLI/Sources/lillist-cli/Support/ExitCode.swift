import Foundation
import LillistCore

/// Maps `LillistError` to the exit codes specified in design Section 6.
public enum ExitCode {
    public static let success: Int32 = 0
    public static let generic: Int32 = 1
    public static let usage: Int32 = 2
    public static let notFound: Int32 = 3
    public static let ambiguous: Int32 = 4
    public static let storeUnavailable: Int32 = 5

    public static func fromLillistError(_ error: LillistError) -> Int32 {
        switch error {
        case .notFound: return notFound
        case .ambiguous: return ambiguous
        case .storeUnavailable: return storeUnavailable
        case .validationFailed: return usage
        default: return generic
        }
    }

    /// Maps any thrown error: `LillistError` → above table; other → generic.
    /// Argument-parser surfaces its own `ExitCode` via thrown `CleanExit` /
    /// `ExitCode` types — those are routed through `Lillist.exit(withError:)`
    /// at the dispatcher level, not here.
    public static func fromAny(_ error: Error) -> Int32 {
        if let l = error as? LillistError { return fromLillistError(l) }
        return generic
    }
}
