import Foundation

/// Stateless SSRF guard for the link-preview pipeline. Decides whether a
/// single `URL` is safe to fetch. Pure value math — no I/O — so it can be
/// applied at the ingest boundary (`CLIBridge.LinkHandler`, the iOS Share
/// Extension), on the initial request, and re-applied on every redirect
/// hop without crossing any actor or network boundary.
///
/// Policy (design Section 3, security hardening — linkpreview-1/3):
///   * Scheme allow-list: `http` and `https` only.
///   * Host block-list: literal `localhost`, any `*.local` mDNS name, and
///     numeric IP literals in loopback / link-local / RFC1918 / IPv6
///     loopback / IPv6 unique-local / IPv6 link-local ranges.
///
/// DNS rebinding (a public name resolving to a private address at connect
/// time) is out of scope here; it is partially mitigated by re-validating
/// the literal host on every redirect, and fully addressing it would
/// require a custom resolver. We block the literal-IP and well-known-name
/// vectors, which are the ones reachable from pasted/shared URLs.
public enum URLPreviewPolicy {
    /// Allowed URL schemes (lowercased).
    public static let allowedSchemes: Set<String> = ["http", "https"]

    /// Returns `true` when `url` may be fetched under the policy.
    public static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), allowedSchemes.contains(scheme) else {
            return false
        }
        guard let host = url.host(percentEncoded: false), !host.isEmpty else {
            return false
        }
        return !isBlockedHost(host)
    }

    /// Returns `true` when `host` (a hostname or bracket-stripped IP
    /// literal) is on the block-list.
    static func isBlockedHost(_ host: String) -> Bool {
        let normalized = host.lowercased()

        if normalized == "localhost" { return true }
        if normalized.hasSuffix(".local") || normalized == "local" { return true }

        // `URL.host(percentEncoded:)` already strips the surrounding
        // brackets from an IPv6 literal, but be defensive.
        let bare = normalized.hasPrefix("[") && normalized.hasSuffix("]")
            ? String(normalized.dropFirst().dropLast())
            : normalized

        if let v4 = IPv4Address(bare) { return v4.isPrivateOrLoopbackOrLinkLocal }
        if let v6 = IPv6Octets(bare) { return v6.isPrivateOrLoopbackOrLinkLocal }

        return false
    }
}

/// Minimal dotted-quad IPv4 parser. Foundation has no public host-literal
/// classifier, so we parse the four octets ourselves and range-check.
struct IPv4Address {
    let octets: (UInt8, UInt8, UInt8, UInt8)

    init?(_ string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var values: [UInt8] = []
        for part in parts {
            // Reject leading/trailing junk and non-decimal forms so we
            // don't misclassify hostnames that merely contain digits.
            guard !part.isEmpty, part.allSatisfy({ $0.isNumber }),
                  let n = UInt16(part), n <= 255 else { return nil }
            values.append(UInt8(n))
        }
        octets = (values[0], values[1], values[2], values[3])
    }

    /// Loopback `127/8` + `0.0.0.0` + link-local `169.254/16`
    /// + RFC1918 `10/8`, `172.16/12`, `192.168/16`.
    var isPrivateOrLoopbackOrLinkLocal: Bool {
        let (a, b, _, _) = octets
        if a == 127 { return true }                          // loopback
        if a == 0 { return true }                            // 0.0.0.0/8 "this host"
        if a == 169 && b == 254 { return true }              // link-local
        if a == 10 { return true }                           // RFC1918 /8
        if a == 172 && (16...31).contains(b) { return true } // RFC1918 /12
        if a == 192 && b == 168 { return true }              // RFC1918 /16
        return false
    }
}

/// Minimal IPv6 literal classifier. We only need to recognize the blocked
/// ranges by their high-order bits, so we parse the first hextet group.
struct IPv6Octets {
    /// Lowercased, bracket-free IPv6 text retained for prefix checks.
    let text: String

    init?(_ string: String) {
        // Must contain a colon and only valid IPv6 characters to qualify.
        guard string.contains(":") else { return nil }
        let allowed = CharacterSet(charactersIn: "0123456789abcdef:.")
        guard string.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        text = string
    }

    /// `::1` loopback, `::` unspecified, `fc00::/7` unique-local,
    /// `fe80::/10` link-local. IPv4-mapped/embedded forms (e.g.
    /// `::ffff:127.0.0.1`) are handled by extracting the trailing IPv4.
    var isPrivateOrLoopbackOrLinkLocal: Bool {
        if text == "::1" || text == "::" { return true }

        // IPv4-mapped / IPv4-compatible: classify the embedded IPv4.
        if let lastColon = text.lastIndex(of: ":") {
            let tail = String(text[text.index(after: lastColon)...])
            if tail.contains("."), let v4 = IPv4Address(tail), v4.isPrivateOrLoopbackOrLinkLocal {
                return true
            }
        }

        // First hextet group determines unique-local / link-local.
        let firstGroup = text.split(separator: ":", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        guard let value = UInt16(firstGroup, radix: 16) else { return false }
        if (value & 0xFE00) == 0xFC00 { return true } // fc00::/7 unique-local
        if (value & 0xFFC0) == 0xFE80 { return true } // fe80::/10 link-local
        return false
    }
}
