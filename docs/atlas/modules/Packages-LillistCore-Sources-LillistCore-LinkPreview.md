---
module: Packages/LillistCore/Sources/LillistCore/LinkPreview
summary: "URL unfurl pipeline — SSRF-gated fetch, OpenGraph parsing, and metadata persistence via AttachmentStore"
read_when: "Touching link preview, URL unfurling, OpenGraph metadata, or SSRF policy"
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
baseline: 34dfea7772679dbabc08fabd6fbba53f6ad5856b
---

# Module: Packages/LillistCore/Sources/LillistCore/LinkPreview

## Purpose

Turns a pasted or shared URL into preview metadata (title, description, image, site name) for an `AttachmentStore` row. The pipeline has three replaceable pieces: a `LinkPreviewFetching` network seam, a pure `OpenGraphParser`, and a `URLPreviewPolicy` SSRF guard applied at every ingest and redirect boundary. The guard is the load-bearing design idea — it is pure value math with no I/O, so callers can reject hostile URLs before any actor or network hop occurs.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `LinkPreviewFetching` | protocol | `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewFetching.swift:6` | Sendable network seam; `fetchHTML`/`fetchImage` return nil on any failure |
| `LinkPreviewLimits` | enum | `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewFetching.swift:17` | Shared constants: 10 s timeout, 5 MB body cap, 5-hop redirect limit |
| `LinkPreviewMetadata` | struct | `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewMetadata.swift:6` | Value-type unfurl result; `Sendable`, `Equatable`; `.empty` is the zero-value sentinel |
| `LinkPreviewUnfurler` | actor | `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewUnfurler.swift:15` | Orchestrates fetch→parse→persist; folds all errors into `Outcome` |
| `LinkPreviewUnfurler.FailureReason` | enum | `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewUnfurler.swift:16` | Categorized failure: `notFound`, `timeout`, `oversize`, `unsupportedContentType`, `parseError`, `storeError` |
| `LinkPreviewUnfurler.Outcome` | enum | `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewUnfurler.swift:25` | `success` or `failure(FailureReason)`; `Sendable`, `Equatable` |
| `LinkPreviewUnfurler.unfurl(attachmentID:url:)` | func | `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewUnfurler.swift:41` | Unfurls `url` and writes back to an existing attachment row |
| `OpenGraphParser` | enum | `Packages/LillistCore/Sources/LillistCore/LinkPreview/OpenGraphParser.swift:7` | Stateless HTML→metadata parser; no JS execution |
| `OpenGraphParser.parse(html:)` | func | `Packages/LillistCore/Sources/LillistCore/LinkPreview/OpenGraphParser.swift:8` | Regex-extracts `og:*` / `twitter:*` / `<title>` tags; returns `LinkPreviewMetadata` |
| `URLPreviewPolicy` | enum | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLPreviewPolicy.swift:20` | Stateless SSRF guard; scheme allow-list + private-IP/host block-list |
| `URLPreviewPolicy.allowedSchemes` | static let | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLPreviewPolicy.swift:22` | `["http", "https"]` — only permitted schemes |
| `URLPreviewPolicy.isAllowed(_:)` | func | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLPreviewPolicy.swift:25` | Returns `true` when a URL may be fetched under the policy |
| `URLSessionLinkPreviewFetcher` | class | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLSessionLinkPreviewFetcher.swift:14` | Production `LinkPreviewFetching`; SSRF-gated, redirect-capped, streamed |
| `URLSessionLinkPreviewFetcher.makeDefaultSession()` | func | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLSessionLinkPreviewFetcher.swift:21` | Ephemeral `URLSession` preconfigured with `LinkPreviewLimits` values |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `URLPreviewPolicy.isBlockedHost(_:)` | func | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLPreviewPolicy.swift:37` | Core block-list logic: localhost, `.local` mDNS, and IP-literal dispatch |
| `IPv4Address` | struct | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLPreviewPolicy.swift:58` | Dotted-quad parser + loopback/link-local/RFC1918 range-check |
| `IPv6Octets` | struct | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLPreviewPolicy.swift:91` | IPv6 classifier for `::1`/`::`, `fc00::/7`, `fe80::/10`, and IPv4-mapped tails |
| `RedirectGuard` | class | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLSessionLinkPreviewFetcher.swift:89` | Per-task delegate that re-applies `URLPreviewPolicy` and enforces `redirectHopLimit` on each redirect |
| `URLSessionLinkPreviewFetcher.capRead(_:)` | func | `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLSessionLinkPreviewFetcher.swift:58` | Streams body via `bytes(for:delegate:)` with `RedirectGuard`; aborts mid-stream past the 5 MB cap |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-LinkPreview.LinkPreviewUnfurler -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.AttachmentStore (calls)` — `unfurl` calls `attachments.updateLinkPreview` at `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewUnfurler.swift:52`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.LinkHandler -> Packages-LillistCore-Sources-LillistCore-LinkPreview.URLPreviewPolicy (calls)` — SSRF check before unfurl at `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/LinkHandler.swift:18`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.LinkHandler -> Packages-LillistCore-Sources-LillistCore-LinkPreview.LinkPreviewUnfurler (calls)` — constructs unfurler and calls `unfurl` at `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/LinkHandler.swift:41`
- `Extensions-ShareExtension-iOS.ShareRootView -> Packages-LillistCore-Sources-LillistCore-LinkPreview.URLPreviewPolicy (calls)` — ingest-boundary SSRF check at `Extensions/ShareExtension-iOS/ShareRootView.swift:105`

## Type notes

`LinkPreviewUnfurler` is a Swift `actor`; its `attachments` and `fetcher` dependencies are injected at construction by `LinkHandler.run` and remain isolated state. `URLPreviewPolicy`, `OpenGraphParser`, `IPv4Address`, and `IPv6Octets` are pure and stateless — no I/O, safe to call from any isolation context.

`RedirectGuard` is `@unchecked Sendable` at `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLSessionLinkPreviewFetcher.swift:89`; its `hopCount` is only touched serially from `URLSession`'s delegate queue. It is attached per-task via `bytes(for:delegate:)` to avoid a session-wide retain cycle.

`fetchHTML` accepts an empty `Content-Type` as valid HTML (`Packages/LillistCore/Sources/LillistCore/LinkPreview/URLSessionLinkPreviewFetcher.swift:38`) — intentional for servers that omit the header.

## External deps

- Foundation — `URL`, `URLSession`, `URLRequest`, `URLSessionTaskDelegate`, `NSRegularExpression`, `Data`

## Gotchas

- DNS rebinding is explicitly out of scope — only literal-IP and well-known-name vectors are blocked; the comment at `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLPreviewPolicy.swift:15` documents this and the partial mitigation (re-checking literal hosts on every redirect hop).
- Oversize body is aborted mid-stream: `capRead` does a `Content-Length` pre-check, then breaks the byte loop once running total exceeds `bodyCapBytes` (`Packages/LillistCore/Sources/LillistCore/LinkPreview/URLSessionLinkPreviewFetcher.swift:73`). Do not switch to `data(for:)` — that buffers the full response.
- `OpenGraphParser` matches both attribute orderings for every `<meta>` tag (property/content and content/property) via the two-pattern arrays at `Packages/LillistCore/Sources/LillistCore/LinkPreview/OpenGraphParser.swift:30`; removing either pattern breaks real-world pages that emit the alternative order.
