import Foundation

/// Pure-function redaction over raw log text.
///
/// Applies the redaction passes enumerated in the Plan 9 design,
/// in fixed order. Each pass is idempotent. Design Section 8
/// requires that task titles, notes, journal bodies, tag names,
/// file paths under user dirs, email addresses, and UUIDs are all
/// stripped before any log text leaves the device.
public enum LogRedactor {

    public static func redact(_ raw: String) -> String {
        var s = raw

        for pass in passes {
            s = pass.regex.stringByReplacingMatches(
                in: s,
                range: NSRange(s.startIndex..., in: s),
                withTemplate: pass.replacement
            )
        }
        return s
    }

    private struct Pass {
        let regex: NSRegularExpression
        let replacement: String
    }

    /// Order matters: wrapped-marker passes go before defense-in-depth
    /// passes so we don't double-stamp content; UUIDs go before paths
    /// because some iOS container paths contain UUIDs we'd rather
    /// pretend are just paths.
    private static let passes: [Pass] = {
        func make(_ pattern: String, _ replacement: String, options: NSRegularExpression.Options = []) -> Pass {
            // swiftlint:disable:next force_try
            let r = try! NSRegularExpression(pattern: pattern, options: options)
            return Pass(regex: r, replacement: replacement)
        }
        return [
            // Wrapped markers first — preserves the marker for clarity.
            make(#"<title>[\s\S]*?</title>"#, "<title><redacted></title>"),
            make(#"<notes>[\s\S]*?</notes>"#, "<notes><redacted></notes>"),
            make(#"<journal>[\s\S]*?</journal>"#, "<journal><redacted></journal>"),
            make(#"<tag>[\s\S]*?</tag>"#, "<tag><redacted></tag>"),
            // Defense-in-depth key=value forms (whitespace-delimited).
            // Case-insensitive on the key: framework/third-party log lines
            // capitalize keys inconsistently (`Title=`, `NOTES=`). The key
            // is captured ($1) and re-emitted verbatim so the *original*
            // casing is preserved while only the value is replaced — a
            // bare literal template would rewrite the whole match and
            // lowercase the key. Single-token only by design: the value
            // class stops at the first whitespace, so multi-word/unwrapped
            // PII is the job of the wrapped-marker passes above; see the
            // type comment.
            make(#"(title=)[^\s\n]*"#, "$1<redacted>", options: .caseInsensitive),
            make(#"(notes=)[^\s\n]*"#, "$1<redacted>", options: .caseInsensitive),
            make(#"(tag=)[^\s\n]*"#, "$1<redacted>", options: .caseInsensitive),
            // Paths. The `\s(?=[A-Z][a-z])` lookahead lets a path
            // greedily consume a literal-space-separated component when
            // the next component begins with a capitalized word — the
            // macOS convention (e.g. `~/Library/Application Support`).
            // This preserves over-redaction at the cost of occasionally
            // eating a capitalized word that follows a real path; the
            // crash-reporter philosophy explicitly favors this trade.
            make(#"/Users/[^/\s]+(?:/(?:[^\s]|\s(?=[A-Z][a-z]))*)?"#, "<path>"),
            // iOS sandbox + App-Group containers. The UUID segment is
            // hex-with-dashes in *either* case (real container names are
            // uppercase, but synced/imported/third-party log text is not
            // guaranteed to be), so the class is [0-9A-Fa-f-], not the
            // uppercase-only form. Both the per-app `Data/Application`
            // subtree and the shared `Shared/AppGroup` subtree (where the
            // shared store and canary live) are covered.
            make(#"/var/mobile/Containers/(?:Data/Application|Shared/AppGroup)/[0-9A-Fa-f-]+(?:/(?:[^\s]|\s(?=[A-Z][a-z]))*)?"#, "<path>"),
            make(#"~/(?:[^\s]|\s(?=[A-Z][a-z]))*"#, "<path>"),
            // Emails.
            make(#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, "<email>"),
            // UUIDs last — by this point paths and emails are gone.
            make(#"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b"#, "<uuid>")
        ]
    }()
}
