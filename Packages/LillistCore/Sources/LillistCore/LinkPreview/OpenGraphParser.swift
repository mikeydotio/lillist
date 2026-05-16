import Foundation

/// Extracts `LinkPreviewMetadata` from raw HTML using a small set of
/// regexes that match the four `<meta property="og:*">` tags and the
/// `<title>` element, plus a Twitter-card fallback. Design Section 3:
/// "HTML-only parsing (no JS execution)."
public enum OpenGraphParser {
    public static func parse(html: String) -> LinkPreviewMetadata {
        var m = LinkPreviewMetadata()
        m.title = ogTag(in: html, property: "og:title")
            ?? twitterTag(in: html, name: "twitter:title")
            ?? titleElement(in: html)
        m.description = ogTag(in: html, property: "og:description")
            ?? twitterTag(in: html, name: "twitter:description")
        if let imageString = ogTag(in: html, property: "og:image")
            ?? twitterTag(in: html, name: "twitter:image"),
           let url = URL(string: imageString),
           url.scheme == "http" || url.scheme == "https" {
            m.imageURL = url
        }
        m.siteName = ogTag(in: html, property: "og:site_name")
        return m
    }

    // MARK: - Tag matchers

    /// `<meta property="og:KEY" content="VALUE">`, both attribute orders.
    private static func ogTag(in html: String, property: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: property)
        let patterns = [
            #"<meta[^>]+property\s*=\s*["']\#(escaped)["'][^>]+content\s*=\s*["']([^"']+)["']"#,
            #"<meta[^>]+content\s*=\s*["']([^"']+)["'][^>]+property\s*=\s*["']\#(escaped)["']"#
        ]
        for p in patterns {
            if let m = firstMatch(in: html, pattern: p, group: 1) {
                return m.decodingHTMLEntities()
            }
        }
        return nil
    }

    /// `<meta name="twitter:KEY" content="VALUE">`, both attribute orders.
    private static func twitterTag(in html: String, name: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let patterns = [
            #"<meta[^>]+name\s*=\s*["']\#(escaped)["'][^>]+content\s*=\s*["']([^"']+)["']"#,
            #"<meta[^>]+content\s*=\s*["']([^"']+)["'][^>]+name\s*=\s*["']\#(escaped)["']"#
        ]
        for p in patterns {
            if let m = firstMatch(in: html, pattern: p, group: 1) {
                return m.decodingHTMLEntities()
            }
        }
        return nil
    }

    /// `<title>VALUE</title>` — newline-permissive.
    private static func titleElement(in html: String) -> String? {
        firstMatch(in: html, pattern: #"<title[^>]*>([^<]+)</title>"#, group: 1)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .decodingHTMLEntities()
    }

    private static func firstMatch(in s: String, pattern: String, group: Int) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let nsRange = NSRange(s.startIndex..<s.endIndex, in: s)
        guard let match = re.firstMatch(in: s, range: nsRange),
              let range = Range(match.range(at: group), in: s) else {
            return nil
        }
        return String(s[range])
    }
}

private extension String {
    /// Decodes the handful of HTML entities OG values commonly contain.
    func decodingHTMLEntities() -> String {
        var s = self
        let map: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'")
        ]
        for (k, v) in map { s = s.replacingOccurrences(of: k, with: v) }
        return s
    }
}
