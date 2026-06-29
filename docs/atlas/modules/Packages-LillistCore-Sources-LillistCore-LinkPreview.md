---
module: Packages/LillistCore/Sources/LillistCore/LinkPreview
summary: "SSRF-guarded URL unfurl pipeline: policy check → capped HTML fetch → OG/Twitter parse → attachment store write."
read_when: "Touching link preview or URL unfurling"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewFetching.swift
    blob: f520a770d2d7e21d3450199c06dd1c912c9dbf25
  - path: Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewMetadata.swift
    blob: 083976837615055d4a04b2123ab1b8e4a4007626
  - path: Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewUnfurler.swift
    blob: d292e0ea74212553d800ff98fc7ea5c4d4e24ad7
  - path: Packages/LillistCore/Sources/LillistCore/LinkPreview/OpenGraphParser.swift
    blob: ad3ca6edceb8c1b9e40cecb09f1a52cd4beec693
  - path: Packages/LillistCore/Sources/LillistCore/LinkPreview/URLPreviewPolicy.swift
    blob: 6fdaac257e7c6e4a0fa0fc7bc010ec3326b09de7
  - path: Packages/LillistCore/Sources/LillistCore/LinkPreview/URLSessionLinkPreviewFetcher.swift
    blob: a0806e059cf1ad66ed6e81ff912f662b77096e13
references_modules: [Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistUI-Sources-LillistUI-Accessibility, Packages-LillistUI-Sources-LillistUI-Recurrence]
generator: cartographer/4
baseline: 99321d774840d17affd02fe2ac63b01b3d8cbec3
---

# Module: Packages/LillistCore/Sources/LillistCore/LinkPreview

## Purpose

This module is the link-preview (URL unfurling) subsystem of LillistCore: it fetches a URL's HTML body, extracts Open Graph / Twitter Card / title metadata from the raw bytes without executing JavaScript, and writes the result back to an attachment row via AttachmentStore. The module is organized as a strict pipeline — URLPreviewPolicy gates every URL (including each redirect hop) for SSRF safety before any byte crosses the wire, URLSessionLinkPreviewFetcher performs a capped byte-stream fetch, OpenGraphParser extracts metadata using only NSRegularExpression, and LinkPreviewUnfurler sequences all three steps. If this module vanished, task attachments that hold pasted links would never display rich preview cards; tasks would show only bare URLs with no title, description, image, or site-name fields.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `FailureReason` | enum | `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewUnfurler.swift:16` | Exhaustive six-case enum callers switch on to decide retry affordance: notFound, timeout, oversize, unsupportedContentType, parseError, storeError. |
| `IPv4Address` | struct | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLPreviewPolicy.swift:58` | Failable init parses strict dotted-quad decimal only (no hex, no leading zeros); returns nil for non-IPv4 strings so callers fall through to IPv6 handling. |
| `IPv6Octets` | struct | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLPreviewPolicy.swift:91` | Failable init returns nil for strings without a colon or with non-IPv6 characters; performs high-order-bit range classification only, not a full RFC-compliant IPv6 parser. |
| `LinkPreviewFetching` | protocol | `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewFetching.swift:6` | Callers may inject any Sendable conformer; fetchHTML returns nil on non-2xx, non-HTML, oversize, or policy-blocked responses; fetchImage returns nil on any failure. |
| `LinkPreviewLimits` | enum | `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewFetching.swift:17` | Shared constants namespace: timeout=10s, bodyCapBytes=5MB, redirectHopLimit=5; all fetcher implementations must honor these limits. |
| `LinkPreviewMetadata` | struct | `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewMetadata.swift:6` | Pure Sendable Equatable value type; all fields optional; callers outside the module may construct instances via the explicit public init; `.empty` is a pre-built zero-value sentinel. |
| `LinkPreviewUnfurler` | actor | `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewUnfurler.swift:15` | Serial public actor; callers await unfurl(_:url:) and receive an Outcome — errors never throw; attachments and fetcher are injected at init for testability. |
| `OpenGraphParser` | enum | `Packages/LillistCore/Sources/LillistCore/LinkPreview/OpenGraphParser.swift:7` | Caseless namespace; parse(html:) always returns a non-nil LinkPreviewMetadata; no network I/O; no JS execution; fields are nil when the corresponding tags are absent. |
| `Outcome` | enum | `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewUnfurler.swift:25` | Two-case result: `.success` or `.failure(FailureReason)`; Sendable and Equatable; callers need not catch exceptions from unfurl. |
| `URLPreviewPolicy` | enum | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLPreviewPolicy.swift:20` | Stateless SSRF guard; pure value math, no I/O; callers invoke isAllowed(_:) on every URL including redirect targets; scheme allow-list is http/https only. |
| `URLSessionLinkPreviewFetcher` | class | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLSessionLinkPreviewFetcher.swift:14` | Production LinkPreviewFetching implementation; URLSession is injected at init for testing; makeDefaultSession returns an ephemeral, no-cache session with all policy limits pre-configured. |
| `decodingHTMLEntities` | func | `Packages/LillistCore/Sources/LillistCore/LinkPreview/OpenGraphParser.swift:79` | File-private String helper; decodes six common HTML entities (&amp; &lt; &gt; &quot; &#39; &apos;) and returns a new String; does not mutate the receiver. |
| `fetchHTML` | func | `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewFetching.swift:10` | Non-nil return is HTML body bytes ready for OpenGraphParser; nil means non-2xx status, non-HTML MIME type, oversize body, or policy-blocked URL. |
| `fetchHTML` | func | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLSessionLinkPreviewFetcher.swift:30` | Returns nil when URLPreviewPolicy blocks the URL, response is non-2xx, or Content-Type is not HTML/XHTML; body is stream-read and aborted on exceeding 5 MB. |
| `fetchImage` | func | `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewFetching.swift:14` | Returns nil when url is nil, fails the policy check, response is non-2xx, or Content-Type is not image/*; non-nil is raw image bytes within the 5 MB cap. |
| `fetchImage` | func | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLSessionLinkPreviewFetcher.swift:44` | Returns nil when url is nil, policy blocks it, status is non-2xx, or Content-Type is not image/*; stream-aborted at 5 MB cap. |
| `isAllowed` | func | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLPreviewPolicy.swift:25` | Returns false for non-http/https schemes, empty/missing hosts, and any host isBlockedHost returns true for; safe to call from any concurrency context. |
| `isBlockedHost` | func | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLPreviewPolicy.swift:37` | Returns true for localhost, *.local mDNS names, and IPv4/IPv6 private/loopback/link-local literals; returns false for public DNS hostnames and unrecognized address forms. |
| `makeDefaultSession` | func | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLSessionLinkPreviewFetcher.swift:21` | Returns an ephemeral URLSession with 10s request+resource timeout, no local cache, max 2 connections per host; callers may override by injecting a custom session at init. |
| `parse` | func | `Packages/LillistCore/Sources/LillistCore/LinkPreview/OpenGraphParser.swift:8` | Always returns a non-nil LinkPreviewMetadata from raw HTML; fields are nil when tags are absent; OG tags take precedence over Twitter fallbacks, which take precedence over the <title> element. |
| `unfurl` | func | `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewUnfurler.swift:41` | Callers pass an existing attachment UUID and URL; on .success the attachment row has been updated via AttachmentStore; the attachment must already exist before calling (typically created by LinkHandler.run). |
| `urlSession` | func | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLSessionLinkPreviewFetcher.swift:92` | URLSessionTaskDelegate redirect hook: returns nil (abort redirect) when hop limit exceeded or redirect target fails URLPreviewPolicy; returns the request unmodified otherwise. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `firstMatch` | func | `Packages/LillistCore/Sources/LillistCore/LinkPreview/OpenGraphParser.swift:64` | Single NSRegularExpression bottleneck for all tag extraction in OpenGraphParser; ogTag, twitterTag, and titleElement all funnel through it (OpenGraphParser.swift:35, 50, 59). Centralizes .caseInsensitive + .dotMatchesLineSeparators options and NSRange↔String.Index conversion — removing it would require duplicating regex setup in each matcher. |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-LinkPreview.IPv6Octets -> Packages-LillistUI-Sources-LillistUI-Recurrence.index (calls)`
- `Packages-LillistCore-Sources-LillistCore-LinkPreview.capRead -> Packages-LillistUI-Sources-LillistUI-Accessibility.value (calls)`
- `Packages-LillistCore-Sources-LillistCore-LinkPreview.fetchHTML -> Packages-LillistUI-Sources-LillistUI-Accessibility.value (calls)`
- `Packages-LillistCore-Sources-LillistCore-LinkPreview.fetchImage -> Packages-LillistUI-Sources-LillistUI-Accessibility.value (calls)`
- `Packages-LillistCore-Sources-LillistCore-LinkPreview.unfurl -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.updateLinkPreview (writes)`

## Type notes

`LinkPreviewUnfurler` is a `public actor` (LinkPreviewUnfurler.swift:15), providing serial access to its `attachments: AttachmentStore` and `fetcher: LinkPreviewFetching` dependencies; callers await results and never catch — all failure paths fold into `Outcome.failure(reason:)`. `URLSessionLinkPreviewFetcher` is a `public final class` whose `URLSession` is injected at init (URLSessionLinkPreviewFetcher.swift:17) so tests supply a `StubURLProtocol`-backed session without subclassing. `RedirectGuard` is attached per-task via `bytes(for:delegate:)` (URLSessionLinkPreviewFetcher.swift:61), never as a session-level delegate, avoiding a retain cycle; its `@unchecked Sendable` annotation at line 89 is valid because `hopCount` is mutated only from URLSession's serial delegate queue. `URLPreviewPolicy`, `OpenGraphParser`, `IPv4Address`, and `IPv6Octets` are all stateless caseless-enum or value-type structs — no retained state, callable from any isolation domain. `LinkPreviewMetadata` is a `Sendable, Equatable` value struct with an explicit public init (LinkPreviewMetadata.swift:12) so callers outside the module can construct test fixtures.

## External deps

- Foundation — imported

## Gotchas

DNS rebinding is explicitly out of scope: URLPreviewPolicy.swift:11-18 documents that a public name resolving to a private IP at connect time is only partially mitigated by redirect re-validation. `RedirectGuard` uses `@unchecked Sendable` (URLSessionLinkPreviewFetcher.swift:89) because `hopCount` is mutated by URLSession's delegate queue, not Swift structured concurrency — serial mutation is guaranteed by URLSession, not the type system. `URL.host(percentEncoded: false)` already strips brackets from IPv6 literals (URLPreviewPolicy.swift:44), but `isBlockedHost` has a defensive re-strip path to remain correct if the caller passes a bracketed string directly.
