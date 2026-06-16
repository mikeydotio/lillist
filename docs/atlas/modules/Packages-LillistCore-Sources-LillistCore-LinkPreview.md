---
module: Packages/LillistCore/Sources/LillistCore/LinkPreview
summary: "SSRF-guarded URL unfurl pipeline — fetch HTML, parse OpenGraph metadata, persist to attachment"
read_when: link preview / URL unfurl
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
references_modules: [Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1, Extensions-ShareExtension-iOS]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: Packages/LillistCore/Sources/LillistCore/LinkPreview

## Purpose

Turns a pasted/shared URL into preview metadata (title, description, image, site
name) for an attachment row. The pipeline splits into three replaceable pieces:
a `LinkPreviewFetching` network side, a pure `OpenGraphParser`, and a
`URLPreviewPolicy` SSRF guard applied at every ingest and redirect boundary. The
guard is the load-bearing idea — it is pure value math with no I/O, so callers
can reject hostile URLs before any actor or network hop.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `LinkPreviewFetching` | protocol | `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewFetching.swift:6` | Sendable network seam; `fetchHTML`/`fetchImage` return nil on any failure |
| `LinkPreviewLimits` | enum | `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewFetching.swift:17` | Shared constants: 10s timeout, 5 MB body cap, 5-hop redirect limit |
| `LinkPreviewMetadata` | struct | `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewMetadata.swift:6` | Value-type unfurl result; `.empty` updates thumbnail only |
| `LinkPreviewUnfurler` | actor | `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewUnfurler.swift:15` | Orchestrates fetch→parse→persist; folds all errors into `Outcome` |
| `LinkPreviewUnfurler.FailureReason` | enum | `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewUnfurler.swift:16` | Categorized failure: notFound/timeout/oversize/unsupported/parse/store |
| `LinkPreviewUnfurler.Outcome` | enum | `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewUnfurler.swift:25` | `success` or `failure(FailureReason)` returned by `unfurl` |
| `LinkPreviewUnfurler.unfurl(attachmentID:url:)` | func | `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewUnfurler.swift:41` | Unfurls and writes back to an existing attachment row |
| `OpenGraphParser` | enum | `Packages/LillistCore/Sources/LillistCore/LinkPreview/OpenGraphParser.swift:7` | Stateless HTML→metadata parser; no JS execution |
| `OpenGraphParser.parse(html:)` | func | `Packages/LillistCore/Sources/LillistCore/LinkPreview/OpenGraphParser.swift:8` | Regex-extracts og:* / twitter:* / `<title>` tags |
| `URLPreviewPolicy` | enum | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLPreviewPolicy.swift:20` | Stateless SSRF guard; scheme allow-list + private-IP/host block-list |
| `URLPreviewPolicy.allowedSchemes` | static let | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLPreviewPolicy.swift:22` | `["http", "https"]` only |
| `URLPreviewPolicy.isAllowed(_:)` | func | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLPreviewPolicy.swift:25` | True when a URL may be fetched under the policy |
| `URLSessionLinkPreviewFetcher` | class | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLSessionLinkPreviewFetcher.swift:14` | Production `LinkPreviewFetching`; gated, redirect-capped, streamed |
| `URLSessionLinkPreviewFetcher.makeDefaultSession()` | func | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLSessionLinkPreviewFetcher.swift:21` | Ephemeral session preconfigured with `LinkPreviewLimits` |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `URLPreviewPolicy.isBlockedHost(_:)` | func | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLPreviewPolicy.swift:37` | Core block-list logic: localhost, `.local`, and IP-literal dispatch |
| `IPv4Address` | struct | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLPreviewPolicy.swift:58` | Dotted-quad parser + loopback/link-local/RFC1918 range-check |
| `IPv6Octets` | struct | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLPreviewPolicy.swift:91` | IPv6 classifier for ::1/::, fc00::/7, fe80::/10, IPv4-mapped tails |
| `RedirectGuard` | class | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLSessionLinkPreviewFetcher.swift:89` | Per-task delegate re-applying policy + hop cap on each redirect |
| `URLSessionLinkPreviewFetcher.capRead(_:)` | func | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLSessionLinkPreviewFetcher.swift:58` | Streams body via `bytes(for:delegate:)`, aborts past the 5 MB cap |
| `OpenGraphParser.firstMatch(in:pattern:group:)` | func | `Packages/LillistCore/Sources/LillistCore/LinkPreview/OpenGraphParser.swift:64` | Shared regex runner behind every og/twitter/title matcher |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-LinkPreview.LinkPreviewUnfurler -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.AttachmentStore (calls)`
- `Packages-LillistCore-Sources-LillistCore-LinkPreview.LinkPreviewUnfurler -> Packages-LillistCore-Sources-LillistCore-LinkPreview.OpenGraphParser (calls)`
- `Packages-LillistCore-Sources-LillistCore-LinkPreview.LinkPreviewUnfurler -> Packages-LillistCore-Sources-LillistCore-LinkPreview.LinkPreviewFetching (calls)`
- `Packages-LillistCore-Sources-LillistCore-LinkPreview.URLSessionLinkPreviewFetcher -> Packages-LillistCore-Sources-LillistCore-LinkPreview.LinkPreviewFetching (conforms-to)`
- `Packages-LillistCore-Sources-LillistCore-LinkPreview.URLSessionLinkPreviewFetcher -> Packages-LillistCore-Sources-LillistCore-LinkPreview.URLPreviewPolicy (calls)`
- `Packages-LillistCore-Sources-LillistCore-LinkPreview.RedirectGuard -> Packages-LillistCore-Sources-LillistCore-LinkPreview.URLPreviewPolicy (calls)`
- `Packages-LillistCore-Sources-LillistCore-LinkPreview.OpenGraphParser -> Packages-LillistCore-Sources-LillistCore-LinkPreview.LinkPreviewMetadata (owns)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.LinkHandler -> Packages-LillistCore-Sources-LillistCore-LinkPreview.URLPreviewPolicy (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.LinkHandler -> Packages-LillistCore-Sources-LillistCore-LinkPreview.LinkPreviewUnfurler (calls)`
- `Extensions-ShareExtension-iOS.ShareRootView -> Packages-LillistCore-Sources-LillistCore-LinkPreview.URLPreviewPolicy (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.AttachmentStore -> Packages-LillistCore-Sources-LillistCore-LinkPreview.LinkPreviewMetadata (reads)`

## Type notes

`LinkPreviewUnfurler` is an `actor`; `AttachmentStore` and the injected
`LinkPreviewFetching` are stored as its isolated state and constructed by the
caller (`LinkHandler.run`), which also creates the attachment row before
`unfurl` runs (`Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewUnfurler.swift:38`).
`URLPreviewPolicy`, `OpenGraphParser`, `IPv4Address`, and `IPv6Octets` are pure
and stateless — no I/O, safe to call from any isolation. `RedirectGuard` is a
per-task delegate (`@unchecked Sendable`) attached via `bytes(for:delegate:)` so
it never becomes a retained session-wide delegate; its lone mutable `hopCount` is
only touched serially from `URLSession`'s delegate queue
(`Packages/LillistCore/Sources/LillistCore/LinkPreview/URLSessionLinkPreviewFetcher.swift:88`).
`LinkPreviewMetadata.empty` is the sentinel for thumbnail-only updates
(`Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewMetadata.swift:24`).

## External deps

- Foundation — `URL`, `URLSession`, `URLRequest`, `NSRegularExpression`, `Data`

## Gotchas

- Oversize body is aborted mid-stream, not buffered: `capRead` rejects on a
  `Content-Length` pre-check then breaks once running bytes exceed the cap
  (`Packages/LillistCore/Sources/LillistCore/LinkPreview/URLSessionLinkPreviewFetcher.swift:73`).
- DNS rebinding is out of scope — only literal-IP/well-known-name vectors are
  blocked; redirect re-validation is the partial mitigation
  (`Packages/LillistCore/Sources/LillistCore/LinkPreview/URLPreviewPolicy.swift:15`).
- `fetchHTML` accepts an empty `Content-Type` as HTML, not just `text/html`
  (`Packages/LillistCore/Sources/LillistCore/LinkPreview/URLSessionLinkPreviewFetcher.swift:38`).
