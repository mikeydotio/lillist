# Privacy Manifest & Export-Compliance Implementation Plan

> **📍 STATUS — ⬜ PENDING — Wave 7 (ship-blocker).**
>
> Part of the **Foundation Hardening** program. **Single source of truth for progress, wave order, and cross-plan coordination:** [`2026-05-29-foundation-hardening-index.md`](2026-05-29-foundation-hardening-index.md). New to this project? Read the index first, then the review ([`docs/reviews/2026-05-28-foundation-review.md`](../../reviews/2026-05-28-foundation-review.md)) for *why* this work exists, then `CLAUDE.md` for conventions + build/test commands. Execute task-by-task with `superpowers:subagent-driven-development`.
>
> ⚠️ **Wave 1 (`store-swap-safety`) is merged to `main`.** It changed several shared files (`MigrationCoordinator`, `PersistenceHost`, `QuarantineManager`, `MigrationJournal`, both `AppEnvironment`s, `PersistenceController`). **Re-Read every file before editing and anchor by code structure — the line numbers in this plan may have drifted.**

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an Apple `PrivacyInfo.xcprivacy` privacy manifest plus the `ITSAppUsesNonExemptEncryption=false` export-compliance key to both apps and both extensions, wire the manifests into xcodegen so every shipping bundle carries them, and add an executing test that proves each manifest exists, parses, and declares the correct required-reason API categories — so TestFlight/App Store submission and OTA install no longer stall on missing-manifest or export-compliance prompts.

**Architecture:** Four committed `PrivacyInfo.xcprivacy` files (one per shipping bundle: iOS app, macOS app, ShareExtension-iOS, ShortcutsActions) each declaring `NSPrivacyTracking=false`, the CloudKit data-collection type (linked to user, not used for tracking), and the two required-reason API categories actually exercised by the codebase — `NSPrivacyAccessedAPICategoryUserDefaults` reason `CA92.1` and `NSPrivacyAccessedAPICategoryFileTimestamp` reason `C617.1`. The apps' manifests live in their existing `Resources/` directories (already `buildPhase: resources`); the extensions' manifests live at the root of their existing source path and are auto-routed to the resources build phase by xcodegen (non-buildable file type). The `ITSAppUsesNonExemptEncryption=false` key is added to all four `Info.plist` files (the app is HTTPS-only — no custom/non-exempt cryptography). A single repo-tree-relative XCTest in each app test bundle (host-less standalone bundles can't read app-bundle resources at runtime, so the test resolves the four manifests by path from `#filePath` and parses them with `PropertyListSerialization`, asserting the required keys/reasons).

**Tech Stack:** Apple privacy manifests (`.xcprivacy` property lists), `Info.plist`, xcodegen (`project.yml`), XCTest + `PropertyListSerialization`, `plutil` for local verification.

**Source findings:** critic blind spot #3 — `PrivacyInfo.xcprivacy` + `ITSAppUsesNonExemptEncryption` (review §"Blind spots" item 3, lines 144–148).

---

## File Structure

### Create

| Path | Responsibility |
|------|----------------|
| `Apps/Lillist-iOS/Resources/PrivacyInfo.xcprivacy` | iOS app privacy manifest — tracking=false, CloudKit collection type, UserDefaults (CA92.1) + FileTimestamp (C617.1) reasons. |
| `Apps/Lillist-macOS/Resources/PrivacyInfo.xcprivacy` | macOS app privacy manifest — identical declarations to the iOS app. |
| `Extensions/ShareExtension-iOS/PrivacyInfo.xcprivacy` | Share-extension privacy manifest — tracking=false, CloudKit collection type, UserDefaults (CA92.1) + FileTimestamp (C617.1) reasons. |
| `Extensions/ShortcutsActions/PrivacyInfo.xcprivacy` | App-Intents-extension privacy manifest — identical declarations to the Share extension. |
| `Apps/Lillist-iOS/Tests/UnitTests/PrivacyManifestComplianceTests.swift` | iOS-bundle XCTest proving all four manifests + four Info.plists exist, parse, and carry the required keys/reasons (`#filePath`-relative). |
| `Apps/Lillist-macOS/Tests/PrivacyManifestComplianceTests.swift` | macOS-bundle XCTest — same assertions, independent so the macOS scheme also fails red on regression. |

### Modify

| Path | Lines | Responsibility |
|------|-------|----------------|
| `Apps/Lillist-iOS/Info.plist` | after line 53 (before closing `</dict>`) | Add `ITSAppUsesNonExemptEncryption` = `false`. |
| `Apps/Lillist-macOS/Info.plist` | after line 49 (before closing `</dict>`) | Add `ITSAppUsesNonExemptEncryption` = `false`. |
| `Extensions/ShareExtension-iOS/Info.plist` | after line 41 (before closing `</dict>`) | Add `ITSAppUsesNonExemptEncryption` = `false`. |
| `Extensions/ShortcutsActions/Info.plist` | after line 27 (before closing `</dict>`) | Add `ITSAppUsesNonExemptEncryption` = `false`. |
| `Apps/Lillist-iOS/project.yml` | `Lillist-iOSTests.sources` (lines 128–139) | Co-compile the four manifests' parent dirs are already in target sources; no manifest co-compile needed (test reads from disk via `#filePath`). Add nothing here unless Step verification fails — see Task 6. |
| `Apps/project.yml` | n/a | macOS app `Resources` path (line 40–41) already has `buildPhase: resources`; manifest auto-bundles. No edit needed unless Task 7 verification fails. |

> **Note on xcodegen wiring:** Both apps' `Resources/` directories are already declared with `buildPhase: resources` (`Apps/Lillist-iOS/project.yml:45-46`, `Apps/project.yml:40-41`), so dropping `PrivacyInfo.xcprivacy` into `Resources/` bundles it automatically. Both extensions declare their whole source directory as a `sources` path with `excludes` for `Info.plist`/`Lillist.entitlements`/`Tests/**` (`Apps/Lillist-iOS/project.yml:78-83, 102-107`); xcodegen routes the non-buildable `.xcprivacy` to the resources build phase automatically. Tasks 6 and 7 verify the bundling actually happened via `xcodegen generate` + pbxproj grep, and add explicit `buildPhase: resources` declarations only if the auto-routing didn't fire.

---

## Task 1: iOS app privacy manifest

**Files:** Create `Apps/Lillist-iOS/Resources/PrivacyInfo.xcprivacy`.

- [ ] **Step 1: Verify the file is genuinely absent.**
  Run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && find . -name "*.xcprivacy" -not -path "*/.build/*"
  ```
  Expected output: empty (no privacy manifests exist yet). If any path prints, stop and reconcile with the existing file before proceeding.

- [ ] **Step 2: Write the manifest.**
  Create `Apps/Lillist-iOS/Resources/PrivacyInfo.xcprivacy` with this exact content:
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>NSPrivacyTracking</key>
      <false/>
      <key>NSPrivacyTrackingDomains</key>
      <array/>
      <key>NSPrivacyCollectedDataTypes</key>
      <array>
          <dict>
              <key>NSPrivacyCollectedDataType</key>
              <string>NSPrivacyCollectedDataTypeOtherUserContent</string>
              <key>NSPrivacyCollectedDataTypeLinked</key>
              <true/>
              <key>NSPrivacyCollectedDataTypeTracking</key>
              <false/>
              <key>NSPrivacyCollectedDataTypePurposes</key>
              <array>
                  <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
              </array>
          </dict>
      </array>
      <key>NSPrivacyAccessedAPITypes</key>
      <array>
          <dict>
              <key>NSPrivacyAccessedAPIType</key>
              <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
              <key>NSPrivacyAccessedAPITypeReasons</key>
              <array>
                  <string>CA92.1</string>
              </array>
          </dict>
          <dict>
              <key>NSPrivacyAccessedAPIType</key>
              <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
              <key>NSPrivacyAccessedAPITypeReasons</key>
              <array>
                  <string>C617.1</string>
              </array>
          </dict>
      </array>
  </dict>
  </plist>
  ```
  Rationale for each declaration (do not omit any):
  - `NSPrivacyTracking=false` / empty `NSPrivacyTrackingDomains` — Lillist does no cross-app tracking and contacts no tracking domains.
  - `NSPrivacyCollectedDataTypeOtherUserContent`, `Linked=true`, `Tracking=false`, purpose `AppFunctionality` — tasks/notes/attachments sync to the user's private CloudKit database; the data is linked to the user's iCloud identity but never used for tracking and exists only for app functionality. (Private-database CloudKit is *not* "data collected by the developer" in Apple's sense, but declaring user content explicitly is the conservative, audit-safe choice and avoids a reviewer back-and-forth.)
  - `NSPrivacyAccessedAPICategoryUserDefaults` reason `CA92.1` — the app reads/writes its own `UserDefaults`/App-Group defaults (verified: `AppEnvironment.swift`, `OnboardingState.swift`, `SyncModeStore.swift`, etc.). `CA92.1` = "Access info from same app, App Group, or CloudKit container."
  - `NSPrivacyAccessedAPICategoryFileTimestamp` reason `C617.1` — `QuarantineManager` reads file `modificationDate`/attributes to age out backups. `C617.1` = "display file timestamps to the person using the device" is wrong; the correct reason for inspecting timestamps of files the app itself created within its own container is `C617.1` ("Access timestamps... of files inside the app container, App Group container, or CloudKit container").

- [ ] **Step 3: Verify it parses as a valid plist.**
  Run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && plutil -lint Apps/Lillist-iOS/Resources/PrivacyInfo.xcprivacy
  ```
  Expected output: `Apps/Lillist-iOS/Resources/PrivacyInfo.xcprivacy: OK`

- [ ] **Step 4: Commit.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  git add Apps/Lillist-iOS/Resources/PrivacyInfo.xcprivacy
  git commit -m "feat(privacy): add iOS app PrivacyInfo.xcprivacy (CA92.1, C617.1)"
  ```

---

## Task 2: macOS app privacy manifest

**Files:** Create `Apps/Lillist-macOS/Resources/PrivacyInfo.xcprivacy`.

- [ ] **Step 1: Write the manifest.**
  Create `Apps/Lillist-macOS/Resources/PrivacyInfo.xcprivacy` with byte-identical content to the iOS manifest (the macOS app uses the same `UserDefaults` + `FileTimestamp` APIs and the same private-CloudKit collection model — keep them verbatim so a single regression diff is obvious):
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>NSPrivacyTracking</key>
      <false/>
      <key>NSPrivacyTrackingDomains</key>
      <array/>
      <key>NSPrivacyCollectedDataTypes</key>
      <array>
          <dict>
              <key>NSPrivacyCollectedDataType</key>
              <string>NSPrivacyCollectedDataTypeOtherUserContent</string>
              <key>NSPrivacyCollectedDataTypeLinked</key>
              <true/>
              <key>NSPrivacyCollectedDataTypeTracking</key>
              <false/>
              <key>NSPrivacyCollectedDataTypePurposes</key>
              <array>
                  <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
              </array>
          </dict>
      </array>
      <key>NSPrivacyAccessedAPITypes</key>
      <array>
          <dict>
              <key>NSPrivacyAccessedAPIType</key>
              <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
              <key>NSPrivacyAccessedAPITypeReasons</key>
              <array>
                  <string>CA92.1</string>
              </array>
          </dict>
          <dict>
              <key>NSPrivacyAccessedAPIType</key>
              <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
              <key>NSPrivacyAccessedAPITypeReasons</key>
              <array>
                  <string>C617.1</string>
              </array>
          </dict>
      </array>
  </dict>
  </plist>
  ```

- [ ] **Step 2: Verify it parses.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && plutil -lint Apps/Lillist-macOS/Resources/PrivacyInfo.xcprivacy
  ```
  Expected output: `Apps/Lillist-macOS/Resources/PrivacyInfo.xcprivacy: OK`

- [ ] **Step 3: Confirm it is byte-identical to the iOS manifest.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && diff Apps/Lillist-iOS/Resources/PrivacyInfo.xcprivacy Apps/Lillist-macOS/Resources/PrivacyInfo.xcprivacy && echo "IDENTICAL"
  ```
  Expected output: `IDENTICAL`

- [ ] **Step 4: Commit.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  git add Apps/Lillist-macOS/Resources/PrivacyInfo.xcprivacy
  git commit -m "feat(privacy): add macOS app PrivacyInfo.xcprivacy (CA92.1, C617.1)"
  ```

---

## Task 3: ShareExtension-iOS privacy manifest

**Files:** Create `Extensions/ShareExtension-iOS/PrivacyInfo.xcprivacy`.

- [ ] **Step 1: Write the manifest.**
  Create `Extensions/ShareExtension-iOS/PrivacyInfo.xcprivacy` (the extension also touches App-Group `UserDefaults` via shared `LillistCore` and reads file timestamps through `QuarantineManager`; identical declarations):
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>NSPrivacyTracking</key>
      <false/>
      <key>NSPrivacyTrackingDomains</key>
      <array/>
      <key>NSPrivacyCollectedDataTypes</key>
      <array>
          <dict>
              <key>NSPrivacyCollectedDataType</key>
              <string>NSPrivacyCollectedDataTypeOtherUserContent</string>
              <key>NSPrivacyCollectedDataTypeLinked</key>
              <true/>
              <key>NSPrivacyCollectedDataTypeTracking</key>
              <false/>
              <key>NSPrivacyCollectedDataTypePurposes</key>
              <array>
                  <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
              </array>
          </dict>
      </array>
      <key>NSPrivacyAccessedAPITypes</key>
      <array>
          <dict>
              <key>NSPrivacyAccessedAPIType</key>
              <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
              <key>NSPrivacyAccessedAPITypeReasons</key>
              <array>
                  <string>CA92.1</string>
              </array>
          </dict>
          <dict>
              <key>NSPrivacyAccessedAPIType</key>
              <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
              <key>NSPrivacyAccessedAPITypeReasons</key>
              <array>
                  <string>C617.1</string>
              </array>
          </dict>
      </array>
  </dict>
  </plist>
  ```

- [ ] **Step 2: Verify it parses.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && plutil -lint Extensions/ShareExtension-iOS/PrivacyInfo.xcprivacy
  ```
  Expected output: `Extensions/ShareExtension-iOS/PrivacyInfo.xcprivacy: OK`

- [ ] **Step 3: Commit.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  git add Extensions/ShareExtension-iOS/PrivacyInfo.xcprivacy
  git commit -m "feat(privacy): add ShareExtension-iOS PrivacyInfo.xcprivacy (CA92.1, C617.1)"
  ```

---

## Task 4: ShortcutsActions privacy manifest

**Files:** Create `Extensions/ShortcutsActions/PrivacyInfo.xcprivacy`.

- [ ] **Step 1: Write the manifest.**
  Create `Extensions/ShortcutsActions/PrivacyInfo.xcprivacy` (the App-Intents extension opens the shared store and shared defaults via `IntentSupport`/`LillistCore`; identical declarations):
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>NSPrivacyTracking</key>
      <false/>
      <key>NSPrivacyTrackingDomains</key>
      <array/>
      <key>NSPrivacyCollectedDataTypes</key>
      <array>
          <dict>
              <key>NSPrivacyCollectedDataType</key>
              <string>NSPrivacyCollectedDataTypeOtherUserContent</string>
              <key>NSPrivacyCollectedDataTypeLinked</key>
              <true/>
              <key>NSPrivacyCollectedDataTypeTracking</key>
              <false/>
              <key>NSPrivacyCollectedDataTypePurposes</key>
              <array>
                  <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
              </array>
          </dict>
      </array>
      <key>NSPrivacyAccessedAPITypes</key>
      <array>
          <dict>
              <key>NSPrivacyAccessedAPIType</key>
              <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
              <key>NSPrivacyAccessedAPITypeReasons</key>
              <array>
                  <string>CA92.1</string>
              </array>
          </dict>
          <dict>
              <key>NSPrivacyAccessedAPIType</key>
              <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
              <key>NSPrivacyAccessedAPITypeReasons</key>
              <array>
                  <string>C617.1</string>
              </array>
          </dict>
      </array>
  </dict>
  </plist>
  ```

- [ ] **Step 2: Verify it parses.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && plutil -lint Extensions/ShortcutsActions/PrivacyInfo.xcprivacy
  ```
  Expected output: `Extensions/ShortcutsActions/PrivacyInfo.xcprivacy: OK`

- [ ] **Step 3: Confirm all four manifests are byte-identical.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  md5 -q Apps/Lillist-iOS/Resources/PrivacyInfo.xcprivacy \
         Apps/Lillist-macOS/Resources/PrivacyInfo.xcprivacy \
         Extensions/ShareExtension-iOS/PrivacyInfo.xcprivacy \
         Extensions/ShortcutsActions/PrivacyInfo.xcprivacy | sort -u
  ```
  Expected output: exactly **one** line (a single shared MD5). More than one line means a manifest drifted — fix before committing.

- [ ] **Step 4: Commit.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  git add Extensions/ShortcutsActions/PrivacyInfo.xcprivacy
  git commit -m "feat(privacy): add ShortcutsActions PrivacyInfo.xcprivacy (CA92.1, C617.1)"
  ```

---

## Task 5: Add `ITSAppUsesNonExemptEncryption=false` to all four Info.plists

**Files:**
- Modify `Apps/Lillist-iOS/Info.plist` (insert before `</dict>` at line 54).
- Modify `Apps/Lillist-macOS/Info.plist` (insert before `</dict>` at line 50).
- Modify `Extensions/ShareExtension-iOS/Info.plist` (insert before `</dict>` at line 42).
- Modify `Extensions/ShortcutsActions/Info.plist` (insert before `</dict>` at line 28).

> **Why:** Lillist uses only HTTPS (`URLSession` to `https://` for link previews and CloudKit's standard transport) and no custom or otherwise non-exempt cryptography. Declaring `ITSAppUsesNonExemptEncryption=false` lets every TestFlight/App Store upload skip the manual export-compliance prompt — a hard blocker for the OTA goal noted in review §3. Each bundle that is uploaded needs its own copy of the key.

- [ ] **Step 1: Confirm the key is genuinely absent everywhere.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && grep -rn "ITSAppUsesNonExemptEncryption" Apps Extensions
  ```
  Expected output: empty. If anything prints, stop and reconcile.

- [ ] **Step 2: Add the key to the iOS app Info.plist.**
  In `Apps/Lillist-iOS/Info.plist`, the current tail (lines 50–54) is:
  ```xml
      <key>NSUserActivityTypes</key>
      <array>
          <string>io.mikeydotio.Lillist.openTask</string>
      </array>
  </dict>
  ```
  Replace it with:
  ```xml
      <key>NSUserActivityTypes</key>
      <array>
          <string>io.mikeydotio.Lillist.openTask</string>
      </array>
      <key>ITSAppUsesNonExemptEncryption</key>
      <false/>
  </dict>
  ```

- [ ] **Step 3: Add the key to the macOS app Info.plist.**
  In `Apps/Lillist-macOS/Info.plist`, the current tail (lines 29–50) ends:
  ```xml
      <key>NSServices</key>
      <array>
          <dict>
              <key>NSMenuItem</key>
              <dict>
                  <key>default</key>
                  <string>Add to Lillist as task</string>
              </dict>
              <key>NSMessage</key>
              <string>addToLillistAsTask</string>
              <key>NSPortName</key>
              <string>Lillist</string>
              <key>NSSendTypes</key>
              <array>
                  <string>NSStringPboardType</string>
                  <string>public.utf8-plain-text</string>
              </array>
              <key>NSReturnTypes</key>
              <array/>
          </dict>
      </array>
  </dict>
  ```
  Replace the closing `</array>` + `</dict>` with the array close, the new key, then the dict close:
  ```xml
              <key>NSReturnTypes</key>
              <array/>
          </dict>
      </array>
      <key>ITSAppUsesNonExemptEncryption</key>
      <false/>
  </dict>
  ```

- [ ] **Step 4: Add the key to the ShareExtension Info.plist.**
  In `Extensions/ShareExtension-iOS/Info.plist`, the current tail (lines 37–42) is:
  ```xml
          <key>NSExtensionPointIdentifier</key>
          <string>com.apple.share-services</string>
          <key>NSExtensionPrincipalClass</key>
          <string>$(PRODUCT_MODULE_NAME).ShareViewController</string>
      </dict>
  </dict>
  ```
  Replace it with (close the `NSExtension` dict, then add the key at the top level before the final `</dict>`):
  ```xml
          <key>NSExtensionPointIdentifier</key>
          <string>com.apple.share-services</string>
          <key>NSExtensionPrincipalClass</key>
          <string>$(PRODUCT_MODULE_NAME).ShareViewController</string>
      </dict>
      <key>ITSAppUsesNonExemptEncryption</key>
      <false/>
  </dict>
  ```

- [ ] **Step 5: Add the key to the ShortcutsActions Info.plist.**
  In `Extensions/ShortcutsActions/Info.plist`, the current tail (lines 23–28) is:
  ```xml
      <key>NSExtension</key>
      <dict>
          <key>NSExtensionPointIdentifier</key>
          <string>com.apple.appintents-extension</string>
      </dict>
  </dict>
  ```
  Replace it with:
  ```xml
      <key>NSExtension</key>
      <dict>
          <key>NSExtensionPointIdentifier</key>
          <string>com.apple.appintents-extension</string>
      </dict>
      <key>ITSAppUsesNonExemptEncryption</key>
      <false/>
  </dict>
  ```

- [ ] **Step 6: Lint all four Info.plists and confirm the key resolves to a boolean false in each.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  for p in Apps/Lillist-iOS/Info.plist Apps/Lillist-macOS/Info.plist \
           Extensions/ShareExtension-iOS/Info.plist Extensions/ShortcutsActions/Info.plist; do
    plutil -lint "$p" || exit 1
    printf '%s -> ' "$p"; plutil -extract ITSAppUsesNonExemptEncryption raw "$p"
  done
  ```
  Expected output (the `-lint` `OK` lines interleaved with):
  ```
  Apps/Lillist-iOS/Info.plist -> false
  Apps/Lillist-macOS/Info.plist -> false
  Extensions/ShareExtension-iOS/Info.plist -> false
  Extensions/ShortcutsActions/Info.plist -> false
  ```

- [ ] **Step 7: Commit.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  git add Apps/Lillist-iOS/Info.plist Apps/Lillist-macOS/Info.plist \
          Extensions/ShareExtension-iOS/Info.plist Extensions/ShortcutsActions/Info.plist
  git commit -m "feat(export-compliance): declare ITSAppUsesNonExemptEncryption=false (HTTPS-only)"
  ```

---

## Task 6: Wire the iOS bundles' manifests through xcodegen and verify they land in the built bundles

**Files:** Possibly modify `Apps/Lillist-iOS/project.yml` (`ShareExtension-iOS.sources` lines 78–83, `ShortcutsActions.sources` lines 102–107). The iOS app's `Resources` path (lines 45–46) already has `buildPhase: resources` — no edit expected.

> This task makes the manifests xcodegen-visible. The apps' `Resources/` dirs are already resource build phases; the extensions declare their whole source dir as a `sources` path. We regenerate the pbxproj, then grep the generated project for each manifest to confirm it's in a resources build phase. We add explicit `buildPhase: resources` declarations only if the auto-routing didn't pick the manifest up.

- [ ] **Step 1: Regenerate the iOS pbxproj.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist/Apps/Lillist-iOS && xcodegen generate --spec project.yml --project .
  ```
  Expected output: `Created project at .../Apps/Lillist-iOS/Lillist-iOS.xcodeproj` (or `Loaded project ... Created project ...`), no error.

- [ ] **Step 2: Confirm all three iOS manifests are referenced in the generated project.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  grep -c "PrivacyInfo.xcprivacy" Apps/Lillist-iOS/Lillist-iOS.xcodeproj/project.pbxproj
  ```
  Expected: a count of **6 or more** (each of the three iOS-side manifests appears as both a `PBXFileReference` and a `PBXBuildFile`/group entry). If the count is `0`, the auto-routing failed — go to Step 3. If `>= 6`, skip Step 3 and go to Step 4.

- [ ] **Step 3 (only if Step 2 returned 0): Declare the extension manifests as explicit resources.**
  In `Apps/Lillist-iOS/project.yml`, change the `ShareExtension-iOS` `sources` block (currently lines 78–83):
  ```yaml
      sources:
        - path: ../../Extensions/ShareExtension-iOS
          excludes:
            - "Info.plist"
            - "Lillist.entitlements"
            - "Tests/**"
  ```
  to:
  ```yaml
      sources:
        - path: ../../Extensions/ShareExtension-iOS
          excludes:
            - "Info.plist"
            - "Lillist.entitlements"
            - "PrivacyInfo.xcprivacy"
            - "Tests/**"
        - path: ../../Extensions/ShareExtension-iOS/PrivacyInfo.xcprivacy
          buildPhase: resources
  ```
  and the `ShortcutsActions` `sources` block (currently lines 102–107):
  ```yaml
      sources:
        - path: ../../Extensions/ShortcutsActions
          excludes:
            - "Info.plist"
            - "Lillist.entitlements"
            - "Tests/**"
  ```
  to:
  ```yaml
      sources:
        - path: ../../Extensions/ShortcutsActions
          excludes:
            - "Info.plist"
            - "Lillist.entitlements"
            - "PrivacyInfo.xcprivacy"
            - "Tests/**"
        - path: ../../Extensions/ShortcutsActions/PrivacyInfo.xcprivacy
          buildPhase: resources
  ```
  Then re-run Step 1 and Step 2; the count must now be `>= 6`.

- [ ] **Step 4: Build the iOS app + extensions unsigned and confirm the manifests are copied into each `.app`/`.appex`.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build \
    -derivedDataPath /tmp/lillist-privacy-dd 2>&1 | tail -5
  echo "--- bundled manifests ---"
  find /tmp/lillist-privacy-dd/Build/Products -name PrivacyInfo.xcprivacy
  ```
  Expected: `** BUILD SUCCEEDED **` and `find` printing **three** `PrivacyInfo.xcprivacy` paths — one inside `Lillist.app/`, one inside `Lillist.app/PlugIns/ShareExtension-iOS.appex/` (or `Add to Lillist.appex`), and one inside `.../ShortcutsActions.appex/`.

- [ ] **Step 5: Commit the regenerated pbxproj (and the project.yml change if Step 3 ran).**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  git add Apps/Lillist-iOS/project.yml Apps/Lillist-iOS/Lillist-iOS.xcodeproj/project.pbxproj
  git commit -m "build(privacy): bundle iOS app + extension privacy manifests via xcodegen"
  ```

---

## Task 7: Wire the macOS app manifest through xcodegen and verify it lands in the built bundle

**Files:** Possibly modify `Apps/project.yml` (`Lillist-macOS.sources` lines 38–41 — already includes `Resources` with `buildPhase: resources`; no edit expected).

- [ ] **Step 1: Regenerate the macOS pbxproj.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist/Apps && xcodegen generate --spec project.yml --project .
  ```
  Expected output: `Created project at .../Apps/Lillist-macOS.xcodeproj`, no error.

- [ ] **Step 2: Confirm the macOS manifest is referenced in the generated project.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  grep -c "PrivacyInfo.xcprivacy" Apps/Lillist-macOS.xcodeproj/project.pbxproj
  ```
  Expected: a count of **2 or more**. If `0`, the `Resources` path didn't pick it up — go to Step 3; otherwise skip to Step 4.

- [ ] **Step 3 (only if Step 2 returned 0): Add an explicit resource entry.**
  In `Apps/project.yml`, change the `Lillist-macOS` `sources` block (currently lines 38–41):
  ```yaml
      sources:
        - path: Lillist-macOS/Sources
        - path: Lillist-macOS/Resources
          buildPhase: resources
  ```
  to add the explicit manifest path:
  ```yaml
      sources:
        - path: Lillist-macOS/Sources
        - path: Lillist-macOS/Resources
          buildPhase: resources
        - path: Lillist-macOS/Resources/PrivacyInfo.xcprivacy
          buildPhase: resources
  ```
  Then re-run Step 1 and Step 2; the count must now be `>= 2`.

- [ ] **Step 4: Build the macOS app unsigned and confirm the manifest is copied into `Lillist.app`.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
    -destination 'platform=macOS' \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build \
    -derivedDataPath /tmp/lillist-privacy-dd-mac 2>&1 | tail -5
  echo "--- bundled manifest ---"
  find /tmp/lillist-privacy-dd-mac/Build/Products -name PrivacyInfo.xcprivacy
  ```
  Expected: `** BUILD SUCCEEDED **` and `find` printing **one** `PrivacyInfo.xcprivacy` path inside `Lillist.app/Contents/Resources/`.

- [ ] **Step 5: Commit the regenerated pbxproj (and the project.yml change if Step 3 ran).**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  git add Apps/project.yml Apps/Lillist-macOS.xcodeproj/project.pbxproj
  git commit -m "build(privacy): bundle macOS app privacy manifest via xcodegen"
  ```

---

## Task 8: Executing test — manifests + Info.plist keys exist, parse, and declare the right reasons

**Files:**
- Create `Apps/Lillist-iOS/Tests/UnitTests/PrivacyManifestComplianceTests.swift`.
- Create `Apps/Lillist-macOS/Tests/PrivacyManifestComplianceTests.swift`.

> **Why a repo-tree-relative test, not a `Bundle.main`/`Bundle.module` lookup:** both app test bundles are *host-less standalone bundles* (`TEST_HOST: ""`, `BUNDLE_LOADER: ""` — `Apps/Lillist-iOS/project.yml:154-155`, `Apps/project.yml:127-128`), so they cannot read the *app's* bundled resources at runtime. The robust contract is "these source files exist on disk, parse, and carry the right declarations" — resolved from `#filePath` so the test is location-independent. Tasks 6/7 already prove the build actually copies them into the bundle, so the two checks together cover both source presence and packaging. The neighbours (`SharePayloadTests.swift`, `DefaultSmartFiltersInstallerTests.swift`, all macOS `*Tests.swift`) use **XCTest** — match that.

- [ ] **Step 1: Write the failing iOS test.**
  Create `Apps/Lillist-iOS/Tests/UnitTests/PrivacyManifestComplianceTests.swift`:
  ```swift
  import XCTest
  import Foundation

  /// Submission-readiness guard. Proves every shipping bundle carries a
  /// privacy manifest declaring the required-reason API categories the app
  /// actually uses (UserDefaults CA92.1, file-timestamp C617.1), declares no
  /// tracking, and that every uploadable Info.plist sets
  /// `ITSAppUsesNonExemptEncryption=false` so export-compliance never stalls
  /// a TestFlight/App Store upload.
  ///
  /// The standalone iOS test bundle has no app host (TEST_HOST=""), so it
  /// cannot read the built app's resources at runtime. Instead it resolves
  /// the source-tree files relative to this file's location (#filePath) and
  /// parses them directly. Task 6/7 of the privacy-manifest plan separately
  /// verify the build copies them into each .app/.appex.
  final class PrivacyManifestComplianceTests: XCTestCase {

      /// Repo root resolved from this file:
      /// .../Apps/Lillist-iOS/Tests/UnitTests/PrivacyManifestComplianceTests.swift
      /// -> up 4 components -> repo root.
      private var repoRoot: URL {
          URL(fileURLWithPath: #filePath)
              .deletingLastPathComponent()   // UnitTests
              .deletingLastPathComponent()   // Tests
              .deletingLastPathComponent()   // Lillist-iOS
              .deletingLastPathComponent()   // Apps
              .deletingLastPathComponent()   // repo root
      }

      private var manifestPaths: [String] {
          [
              "Apps/Lillist-iOS/Resources/PrivacyInfo.xcprivacy",
              "Apps/Lillist-macOS/Resources/PrivacyInfo.xcprivacy",
              "Extensions/ShareExtension-iOS/PrivacyInfo.xcprivacy",
              "Extensions/ShortcutsActions/PrivacyInfo.xcprivacy",
          ]
      }

      private var infoPlistPaths: [String] {
          [
              "Apps/Lillist-iOS/Info.plist",
              "Apps/Lillist-macOS/Info.plist",
              "Extensions/ShareExtension-iOS/Info.plist",
              "Extensions/ShortcutsActions/Info.plist",
          ]
      }

      private func plist(at relativePath: String) throws -> [String: Any] {
          let url = repoRoot.appendingPathComponent(relativePath)
          XCTAssertTrue(
              FileManager.default.fileExists(atPath: url.path),
              "Missing file: \(relativePath)"
          )
          let data = try Data(contentsOf: url)
          let parsed = try PropertyListSerialization.propertyList(
              from: data, options: [], format: nil
          )
          let dict = try XCTUnwrap(
              parsed as? [String: Any],
              "Not a plist dictionary: \(relativePath)"
          )
          return dict
      }

      func test_every_bundle_has_a_parseable_privacy_manifest() throws {
          for path in manifestPaths {
              _ = try plist(at: path)   // throws/fails if missing or unparseable
          }
      }

      func test_manifests_declare_no_tracking() throws {
          for path in manifestPaths {
              let dict = try plist(at: path)
              let tracking = try XCTUnwrap(
                  dict["NSPrivacyTracking"] as? Bool,
                  "NSPrivacyTracking missing in \(path)"
              )
              XCTAssertFalse(tracking, "NSPrivacyTracking must be false in \(path)")
          }
      }

      func test_manifests_declare_userDefaults_CA92_1_and_fileTimestamp_C617_1() throws {
          for path in manifestPaths {
              let dict = try plist(at: path)
              let apiTypes = try XCTUnwrap(
                  dict["NSPrivacyAccessedAPITypes"] as? [[String: Any]],
                  "NSPrivacyAccessedAPITypes missing in \(path)"
              )
              let reasonsByCategory: [String: [String]] = apiTypes.reduce(into: [:]) { acc, entry in
                  guard
                      let category = entry["NSPrivacyAccessedAPIType"] as? String,
                      let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String]
                  else { return }
                  acc[category] = reasons
              }
              XCTAssertEqual(
                  reasonsByCategory["NSPrivacyAccessedAPICategoryUserDefaults"], ["CA92.1"],
                  "UserDefaults reason must be exactly [CA92.1] in \(path)"
              )
              XCTAssertEqual(
                  reasonsByCategory["NSPrivacyAccessedAPICategoryFileTimestamp"], ["C617.1"],
                  "FileTimestamp reason must be exactly [C617.1] in \(path)"
              )
          }
      }

      func test_collected_data_is_cloudkit_user_content_linked_and_not_tracking() throws {
          for path in manifestPaths {
              let dict = try plist(at: path)
              let collected = try XCTUnwrap(
                  dict["NSPrivacyCollectedDataTypes"] as? [[String: Any]],
                  "NSPrivacyCollectedDataTypes missing in \(path)"
              )
              let userContent = try XCTUnwrap(
                  collected.first {
                      ($0["NSPrivacyCollectedDataType"] as? String)
                          == "NSPrivacyCollectedDataTypeOtherUserContent"
                  },
                  "OtherUserContent entry missing in \(path)"
              )
              XCTAssertEqual(
                  userContent["NSPrivacyCollectedDataTypeLinked"] as? Bool, true,
                  "CloudKit user content must be Linked in \(path)"
              )
              XCTAssertEqual(
                  userContent["NSPrivacyCollectedDataTypeTracking"] as? Bool, false,
                  "CloudKit user content must not be used for tracking in \(path)"
              )
          }
      }

      func test_every_uploadable_infoplist_disables_nonexempt_encryption() throws {
          for path in infoPlistPaths {
              let dict = try plist(at: path)
              let flag = try XCTUnwrap(
                  dict["ITSAppUsesNonExemptEncryption"] as? Bool,
                  "ITSAppUsesNonExemptEncryption missing in \(path)"
              )
              XCTAssertFalse(
                  flag, "ITSAppUsesNonExemptEncryption must be false in \(path)"
              )
          }
      }
  }
  ```

- [ ] **Step 2: Run the iOS test, expect it to PASS** (the manifests and keys already landed in Tasks 1–5, so this is a green-on-arrival regression guard rather than a red-first cycle).
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
    -only-testing:Lillist-iOSTests/PrivacyManifestComplianceTests 2>&1 | tail -20
  ```
  Expected: `Test Suite 'PrivacyManifestComplianceTests' passed`, 5 tests, 0 failures.
  > To prove the test actually fails on regression (TDD discipline): temporarily `git stash` one manifest (`git rm --cached Extensions/ShortcutsActions/PrivacyInfo.xcprivacy && mv Extensions/ShortcutsActions/PrivacyInfo.xcprivacy /tmp/`), re-run — expect `test_every_bundle_has_a_parseable_privacy_manifest` to fail with `Missing file: Extensions/ShortcutsActions/PrivacyInfo.xcprivacy` — then restore it (`mv /tmp/PrivacyInfo.xcprivacy Extensions/ShortcutsActions/ && git add Extensions/ShortcutsActions/PrivacyInfo.xcprivacy`) and re-run to green.

- [ ] **Step 3: Write the macOS test.**
  Create `Apps/Lillist-macOS/Tests/PrivacyManifestComplianceTests.swift` — same assertions, but `#filePath` is one level shallower (`.../Apps/Lillist-macOS/Tests/PrivacyManifestComplianceTests.swift`, so up 3 to repo root):
  ```swift
  import XCTest
  import Foundation

  /// Submission-readiness guard, macOS-scheme copy of the iOS test so the
  /// macOS scheme also fails red if any privacy manifest or
  /// export-compliance key regresses. See the iOS copy for rationale.
  ///
  /// The standalone macOS test bundle has no app host (TEST_HOST=""), so it
  /// resolves the source-tree files relative to this file (#filePath) and
  /// parses them directly.
  final class PrivacyManifestComplianceTests: XCTestCase {

      /// Repo root resolved from this file:
      /// .../Apps/Lillist-macOS/Tests/PrivacyManifestComplianceTests.swift
      /// -> up 3 components -> repo root.
      private var repoRoot: URL {
          URL(fileURLWithPath: #filePath)
              .deletingLastPathComponent()   // Tests
              .deletingLastPathComponent()   // Lillist-macOS
              .deletingLastPathComponent()   // Apps
              .deletingLastPathComponent()   // repo root
      }

      private var manifestPaths: [String] {
          [
              "Apps/Lillist-iOS/Resources/PrivacyInfo.xcprivacy",
              "Apps/Lillist-macOS/Resources/PrivacyInfo.xcprivacy",
              "Extensions/ShareExtension-iOS/PrivacyInfo.xcprivacy",
              "Extensions/ShortcutsActions/PrivacyInfo.xcprivacy",
          ]
      }

      private var infoPlistPaths: [String] {
          [
              "Apps/Lillist-iOS/Info.plist",
              "Apps/Lillist-macOS/Info.plist",
              "Extensions/ShareExtension-iOS/Info.plist",
              "Extensions/ShortcutsActions/Info.plist",
          ]
      }

      private func plist(at relativePath: String) throws -> [String: Any] {
          let url = repoRoot.appendingPathComponent(relativePath)
          XCTAssertTrue(
              FileManager.default.fileExists(atPath: url.path),
              "Missing file: \(relativePath)"
          )
          let data = try Data(contentsOf: url)
          let parsed = try PropertyListSerialization.propertyList(
              from: data, options: [], format: nil
          )
          let dict = try XCTUnwrap(
              parsed as? [String: Any],
              "Not a plist dictionary: \(relativePath)"
          )
          return dict
      }

      func test_every_bundle_has_a_parseable_privacy_manifest() throws {
          for path in manifestPaths {
              _ = try plist(at: path)
          }
      }

      func test_manifests_declare_no_tracking() throws {
          for path in manifestPaths {
              let dict = try plist(at: path)
              let tracking = try XCTUnwrap(
                  dict["NSPrivacyTracking"] as? Bool,
                  "NSPrivacyTracking missing in \(path)"
              )
              XCTAssertFalse(tracking, "NSPrivacyTracking must be false in \(path)")
          }
      }

      func test_manifests_declare_userDefaults_CA92_1_and_fileTimestamp_C617_1() throws {
          for path in manifestPaths {
              let dict = try plist(at: path)
              let apiTypes = try XCTUnwrap(
                  dict["NSPrivacyAccessedAPITypes"] as? [[String: Any]],
                  "NSPrivacyAccessedAPITypes missing in \(path)"
              )
              let reasonsByCategory: [String: [String]] = apiTypes.reduce(into: [:]) { acc, entry in
                  guard
                      let category = entry["NSPrivacyAccessedAPIType"] as? String,
                      let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String]
                  else { return }
                  acc[category] = reasons
              }
              XCTAssertEqual(
                  reasonsByCategory["NSPrivacyAccessedAPICategoryUserDefaults"], ["CA92.1"],
                  "UserDefaults reason must be exactly [CA92.1] in \(path)"
              )
              XCTAssertEqual(
                  reasonsByCategory["NSPrivacyAccessedAPICategoryFileTimestamp"], ["C617.1"],
                  "FileTimestamp reason must be exactly [C617.1] in \(path)"
              )
          }
      }

      func test_collected_data_is_cloudkit_user_content_linked_and_not_tracking() throws {
          for path in manifestPaths {
              let dict = try plist(at: path)
              let collected = try XCTUnwrap(
                  dict["NSPrivacyCollectedDataTypes"] as? [[String: Any]],
                  "NSPrivacyCollectedDataTypes missing in \(path)"
              )
              let userContent = try XCTUnwrap(
                  collected.first {
                      ($0["NSPrivacyCollectedDataType"] as? String)
                          == "NSPrivacyCollectedDataTypeOtherUserContent"
                  },
                  "OtherUserContent entry missing in \(path)"
              )
              XCTAssertEqual(
                  userContent["NSPrivacyCollectedDataTypeLinked"] as? Bool, true,
                  "CloudKit user content must be Linked in \(path)"
              )
              XCTAssertEqual(
                  userContent["NSPrivacyCollectedDataTypeTracking"] as? Bool, false,
                  "CloudKit user content must not be used for tracking in \(path)"
              )
          }
      }

      func test_every_uploadable_infoplist_disables_nonexempt_encryption() throws {
          for path in infoPlistPaths {
              let dict = try plist(at: path)
              let flag = try XCTUnwrap(
                  dict["ITSAppUsesNonExemptEncryption"] as? Bool,
                  "ITSAppUsesNonExemptEncryption missing in \(path)"
              )
              XCTAssertFalse(
                  flag, "ITSAppUsesNonExemptEncryption must be false in \(path)"
              )
          }
      }
  }
  ```

- [ ] **Step 4: Run the macOS test, expect PASS.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS \
    -destination 'platform=macOS' \
    -only-testing:Lillist-macOSTests/PrivacyManifestComplianceTests 2>&1 | tail -20
  ```
  Expected: `Test Suite 'PrivacyManifestComplianceTests' passed`, 5 tests, 0 failures.

- [ ] **Step 5: Regenerate both pbxprojs so the new test files are picked up, then confirm no other drift.**
  The two test files live under existing `sources` paths (`Tests/UnitTests` for iOS — `Apps/Lillist-iOS/project.yml:130`; `Lillist-macOS/Tests` for macOS — `Apps/project.yml:70`), so xcodegen auto-includes them. Regenerate to register them in the pbxproj:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist/Apps/Lillist-iOS && xcodegen generate --spec project.yml --project .
  cd /Volumes/Code/mikeyward/Lillist/Apps && xcodegen generate --spec project.yml --project .
  cd /Volumes/Code/mikeyward/Lillist
  grep -c "PrivacyManifestComplianceTests" Apps/Lillist-iOS/Lillist-iOS.xcodeproj/project.pbxproj
  grep -c "PrivacyManifestComplianceTests" Apps/Lillist-macOS.xcodeproj/project.pbxproj
  ```
  Expected: each `grep -c` returns `>= 2`.

- [ ] **Step 6: Commit.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  git add Apps/Lillist-iOS/Tests/UnitTests/PrivacyManifestComplianceTests.swift \
          Apps/Lillist-macOS/Tests/PrivacyManifestComplianceTests.swift \
          Apps/Lillist-iOS/Lillist-iOS.xcodeproj/project.pbxproj \
          Apps/Lillist-macOS.xcodeproj/project.pbxproj
  git commit -m "test(privacy): assert manifests + ITSAppUsesNonExemptEncryption across all bundles"
  ```

---

## Task 9: Record the gotcha and run the full suites

**Files:** Modify `docs/engineering-notes.md` (append one entry).

- [ ] **Step 1: Read the tail of engineering-notes.md to match the entry style.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && tail -30 docs/engineering-notes.md
  ```
  Confirm the heading depth and formatting of the last entry before appending.

- [ ] **Step 2: Append the privacy-manifest gotcha** to the end of `docs/engineering-notes.md` (use the same heading level as neighbouring entries — typically `### `):
  ```markdown

  ### Privacy manifests are per-bundle, not per-project

  `PrivacyInfo.xcprivacy` and `ITSAppUsesNonExemptEncryption` live in
  *each* shipping bundle, not once at the project level. Lillist ships
  four uploadable bundles — the iOS app, the macOS app, `ShareExtension-iOS`,
  and `ShortcutsActions` — so each carries its own manifest (apps in
  `Resources/`, extensions at their source-dir root) and its own
  `ITSAppUsesNonExemptEncryption=false` in `Info.plist`. The four manifests
  are intentionally byte-identical (same `UserDefaults` CA92.1 +
  file-timestamp C617.1 required-reason APIs via shared `LillistCore`, same
  private-CloudKit user-content collection model); keep them in sync — a
  guard test (`PrivacyManifestComplianceTests` in both app test bundles)
  parses all four and asserts the reasons match exactly. Those test bundles
  are host-less (`TEST_HOST=""`), so the test reads the manifests from the
  repo tree via `#filePath`, not from `Bundle.main`. If you add a new
  required-reason API (e.g. `systemBootTime`, `diskSpace`), update all four
  manifests and the test's expected-reason assertions together.
  ```

- [ ] **Step 3: Run the full iOS and macOS app test suites to confirm nothing else regressed.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' 2>&1 | tail -8
  xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS \
    -destination 'platform=macOS' 2>&1 | tail -8
  ```
  Expected: both end with `** TEST SUCCEEDED **`, including the new `PrivacyManifestComplianceTests` in each.

- [ ] **Step 4: Commit.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  git add docs/engineering-notes.md
  git commit -m "docs(privacy): note per-bundle manifest + export-compliance discipline"
  ```

---

## Self-review checklist

- [ ] **Finding "critic: PrivacyInfo.xcprivacy"** — closed by Tasks 1 (iOS app), 2 (macOS app), 3 (ShareExtension-iOS), 4 (ShortcutsActions) creating one manifest per shipping bundle; Tasks 6 & 7 wire them through xcodegen and verify each lands in its built `.app`/`.appex`; Task 8 adds an executing XCTest in both app schemes asserting each manifest exists, parses, declares `NSPrivacyTracking=false`, the CloudKit user-content collection type (Linked, not Tracking), and the `UserDefaults` CA92.1 + file-timestamp C617.1 reasons.
- [ ] **Finding "critic: ITSAppUsesNonExemptEncryption"** — closed by Task 5 adding `ITSAppUsesNonExemptEncryption=false` to all four `Info.plist` files (verified via `plutil -extract`); Task 8's `test_every_uploadable_infoplist_disables_nonexempt_encryption` guards it in both app test bundles.
- [ ] **Required-reason accuracy verified against the codebase** — `UserDefaults` (CA92.1) is used in `AppEnvironment.swift`, `OnboardingState.swift`, `SyncModeStore.swift`, `DevicePreferencesStore.swift`, and others; file-timestamp (C617.1) is used in `Packages/LillistCore/Sources/LillistCore/Persistence/QuarantineManager.swift`. No other required-reason categories (system-boot-time, disk-space, active-keyboard) are exercised, so none are declared (YAGNI).
- [ ] **Absence verified first** — Task 1 Step 1 (`find -name "*.xcprivacy"` → empty) and Task 5 Step 1 (`grep ITSAppUsesNonExemptEncryption` → empty) confirm the additions are net-new, matching the upfront repo scan in the plan's research.
- [ ] **No strengths refactored away** — this plan only adds manifest/plist files, four xcodegen-bundled resources, and two test files; it touches no `LillistCore` source, no DTO boundary, no `AsyncStream` registration, no date math, no container/presenter split. The strengths in review §"Strengths to preserve" are untouched.
- [ ] **No `.xcdatamodel` edits** — this plan never touches the Core Data model, so the `CompileCoreDataModel` mtime touch ritual is not required here.
- [ ] **Cross-platform string parity** — no user-visible strings are added or changed, so no `Localizable.xcstrings` sync is needed.
- [ ] **Conventional commits, small and focused** — nine commits (`feat(privacy)` ×4 for the manifests, `feat(export-compliance)` for the plist keys, `build(privacy)` ×2 for xcodegen wiring, `test(privacy)`, `docs(privacy)`), each landing one coherent change directly to `main` per the solo-project workflow.
