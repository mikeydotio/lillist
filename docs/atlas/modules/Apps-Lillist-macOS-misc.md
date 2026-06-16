---
module: "Apps/Lillist-macOS (misc)"
summary: "macOS app bundle config — Info.plist, sandbox/iCloud entitlements, privacy manifest, app-only strings"
read_when: "macOS bundle entitlements"
sources:
  - path: Apps/Lillist-macOS/Info.plist
    blob: 77bee3c5e56ace15bb627ba59aa18edf5f4544b3
  - path: Apps/Lillist-macOS/Lillist.entitlements
    blob: bbcb3bfbc5f58c2efb616805c4867d1b24a7d644
  - path: Apps/Lillist-macOS/Resources/Localizable.xcstrings
    blob: 7487e9c9eb037dcf3d359808de8a5b58e1b4c96d
  - path: Apps/Lillist-macOS/Resources/PrivacyInfo.xcprivacy
    blob: 4e7e051bbe5e2753a0a80b85ae78289d250bdce7
references_modules: [Apps-Lillist-macOS-Sources-misc, Apps-Lillist-macOS-Sources-Preferences]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: Apps/Lillist-macOS (misc)

## Purpose

Bundle-level configuration for the macOS app target — not Swift code. These
property lists declare the app's identity, capability grants, App Store privacy
manifest, and the small set of user-visible strings that exist only on macOS.
Most build-time values are xcodegen placeholders (`$(…)`); the hand-set entries
here are the load-bearing ones: the Services menu hook, the sandbox/iCloud/App
Group grants, and the Sparkle auto-update feed. Misconfigure any and the app
either fails to launch, loses CloudKit sync, or breaks OTA updates.

## Public API

(none — configuration files expose no callable symbols)

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `NSServices` | plist key | `Apps/Lillist-macOS/Info.plist:29` | Registers a system Services menu item routed to the `addToLillistAsTask` message |
| `SUFeedURL` | plist key | `Apps/Lillist-macOS/Info.plist:52` | Sparkle appcast URL served over Tailscale for OTA macOS updates |
| `SUPublicEDKey` | plist key | `Apps/Lillist-macOS/Info.plist:54` | EdDSA public key Sparkle verifies update signatures against |
| `com.apple.security.application-groups` | entitlement | `Apps/Lillist-macOS/Lillist.entitlements:11` | App Group `group.io.mikeydotio.Lillist` shared with iOS app and extensions |
| `com.apple.developer.icloud-container-identifiers` | entitlement | `Apps/Lillist-macOS/Lillist.entitlements:15` | CloudKit container `iCloud.com.mikeydotio.lillist` backing sync |
| `com.apple.security.app-sandbox` | entitlement | `Apps/Lillist-macOS/Lillist.entitlements:5` | App Sandbox enabled; pairs with user-selected file and network-client grants |

## Relationships

- `Apps-Lillist-macOS-misc.NSServices -> Apps-Lillist-macOS-Sources-misc.addToLillistAsTask (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.DiagnosticsPane -> Apps-Lillist-macOS-misc.Localizable.xcstrings (reads)`

## Type notes

`Info.plist`'s `NSMessage` value (`addToLillistAsTask`, `Apps/Lillist-macOS/Info.plist:38`)
is the Objective-C selector AppKit invokes when the Services menu item fires;
it must match the `@objc func` of the same name verbatim or the menu item
silently no-ops. `CFBundleShortVersionString` is hand-pinned to `1.0.0`
(`Apps/Lillist-macOS/Info.plist:20`); `CFBundleVersion` here is a static value
(`Apps/Lillist-macOS/Info.plist:22`) — the deploy-time build-number bump
targets the iOS target's xcconfig, not this plist.

The entitlements form one capability set: sandbox on, user-selected files
read-write, network client (for Sparkle + CloudKit), the shared App Group, and
the CloudKit container with the `CloudKit` service. The App Group string must
stay identical across all targets that share it.

## External deps

- Sparkle — `SUFeedURL`/`SUPublicEDKey`/`SUEnableAutomaticChecks` drive its auto-update flow
- CloudKit — `com.apple.developer.icloud-services` grants the sync backend
- App Sandbox — entitlements gate filesystem and network access at runtime

## Gotchas

- `ITSAppUsesNonExemptEncryption` is `false` (`Apps/Lillist-macOS/Info.plist:50`) — export-compliance declaration; flipping it triggers App Store encryption review.
- `PrivacyInfo.xcprivacy` declares UserDefaults/FileTimestamp/DiskSpace API reasons (`Apps/Lillist-macOS/Resources/PrivacyInfo.xcprivacy:24`); adding such an API without a matching reason fails App Store submission.
