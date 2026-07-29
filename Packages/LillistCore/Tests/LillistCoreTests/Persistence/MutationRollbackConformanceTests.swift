import Testing
import Foundation

/// H5's class-kill: Swift's plain (non-`@objc`) final classes give no
/// runtime method-list reflection, so there is no `NSManagedObjectModel`-like
/// runtime object to walk the way `1d`'s model-derived export-completeness
/// test did. The mechanical, drift-proof alternative is a source-text scan:
/// every file that legitimately mutates the shared `viewContext` must call
/// `context.save()`/`context.rollback()` (or `ctx.save()`/`ctx.rollback()`)
/// **only** from inside `withMutationRollback`'s own definition
/// (`Persistence/MutationRollback.swift`) — nowhere else. A future method
/// that bypasses the helper and calls `try context.save()` directly fails
/// this test immediately, at the source-text level, independent of whether
/// anyone remembers to write a behavioral regression test for that specific
/// method.
///
/// See `docs/superpowers/plans/2026-07-28-plan-5a-mutation-scope-discipline.md`
/// §4 for the full design rationale, including why a `Mirror`-based
/// enumeration isn't available here.
@Suite("MutationRollback conformance (H5 class-kill)")
struct MutationRollbackConformanceTests {
    /// Every store/maintenance file expected to be fully migrated onto
    /// `withMutationRollback` — i.e. that should contain **zero** raw
    /// `.save()`/`.rollback()` calls on a managed object context. Grows as
    /// each store lands its own migration commit; see the plan doc's
    /// commit plan for the adoption order.
    static let migratedFiles: [String] = [
        "Stores/TaskStore.swift",
        "Stores/TaskStore+FollowUp.swift",
        "Stores/TagStore.swift",
        "Stores/TagStore+FindOrCreate.swift",
        "Stores/SmartFilterStore.swift",
        "Stores/JournalStore.swift",
        "Stores/SeriesStore.swift",
    ]

    @Test("Every enumerated migrated file exists on disk", arguments: migratedFiles)
    func migratedFileExists(relativePath: String) throws {
        let url = try Self.sourcesRoot().appendingPathComponent(relativePath)
        #expect(FileManager.default.fileExists(atPath: url.path), "\(relativePath) not found at \(url.path)")
    }

    @Test("Every enumerated migrated file has no raw context save/rollback call", arguments: migratedFiles)
    func migratedFileHasNoRawSaveOrRollback(relativePath: String) throws {
        let url = try Self.sourcesRoot().appendingPathComponent(relativePath)
        let text = try String(contentsOf: url, encoding: .utf8)
        let offenders = Self.rawSaveOrRollbackLines(in: text)
        #expect(offenders.isEmpty, "\(relativePath) bypasses withMutationRollback at: \(offenders.joined(separator: "; "))")
    }

    /// The completeness half of the class-kill: walk every `.swift` file
    /// under the directories that legitimately mutate the shared context
    /// and confirm each one is either (a) one of the enumerated
    /// `migratedFiles` above, verified clean by the test above, (b) a known,
    /// documented composition-only exemption (calls no raw save/rollback of
    /// its own — verified here, not just asserted), or (c) not yet migrated,
    /// in which case its raw calls are expected for now and tracked by this
    /// plan's remaining commits. This test only fails when a file OUTSIDE
    /// both the migrated list and the exemption list is found to contain a
    /// raw call — i.e. a genuinely new, undocumented bypass.
    @Test("No undocumented file outside the migrated/exempt lists bypasses the helper")
    func noUndocumentedBypass() throws {
        let root = try Self.sourcesRoot()
        let scanDirs = ["Stores", "Notifications"]
        let extraFiles = ["Persistence/TaskDuplicateReconciler.swift"]
        let exemptions: Set<String> = [
            // Composition-only: delegates every mutation to already-migrated
            // methods (`create`/`delete`), never touches the context itself.
            "Stores/SmartFilterStore+Defaults.swift",
            // Read-only: no mutating methods, verified by inspection (see
            // plan-5a §4).
            "Stores/TaskStore+Queries.swift",
        ]

        var swiftFiles: [String] = []
        for dir in scanDirs {
            let dirURL = root.appendingPathComponent(dir)
            guard let enumerator = FileManager.default.enumerator(at: dirURL, includingPropertiesForKeys: nil) else { continue }
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                let relative = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
                swiftFiles.append(relative)
            }
        }
        swiftFiles.append(contentsOf: extraFiles)

        let migrated = Set(Self.migratedFiles)
        var unexpectedOffenders: [String] = []
        for relativePath in swiftFiles {
            guard !migrated.contains(relativePath) else { continue }   // covered by the test above
            let url = root.appendingPathComponent(relativePath)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let offenders = Self.rawSaveOrRollbackLines(in: text)
            if exemptions.contains(relativePath) {
                #expect(offenders.isEmpty, "\(relativePath) is listed as a composition-only exemption but contains a raw call: \(offenders.joined(separator: "; "))")
                continue
            }
            if !offenders.isEmpty {
                unexpectedOffenders.append(relativePath)
            }
        }

        // Files not yet migrated are expected to appear here until their own
        // commit lands — this list is the plan's remaining scope, not a
        // failure. Update as each store migrates.
        let stillPending: Set<String> = [
            "Stores/AttachmentStore.swift",
            "Stores/PreferencesStore.swift",
            "Notifications/NotificationSpecStore.swift",
            "Persistence/TaskDuplicateReconciler.swift",
        ]
        let trulyUnexpected = Set(unexpectedOffenders).subtracting(stillPending)
        #expect(trulyUnexpected.isEmpty, "Undocumented bypass(es) found: \(trulyUnexpected.sorted().joined(separator: ", "))")
    }

    // MARK: - Helpers

    /// A line "bypasses" the helper if it calls `.save()` or `.rollback()`
    /// on something named `context`/`ctx`/`bg`/`bgContext` — the parameter
    /// names every store uses for its managed object context — excluding
    /// doc-comment lines (`///`) and `MutationRollback.swift` itself (not
    /// reachable here since the scan never includes that file's directory
    /// contents beyond what's explicitly listed).
    private static func rawSaveOrRollbackLines(in text: String) -> [String] {
        let pattern = #"\b(context|ctx|bg|bgContext)\.(save|rollback)\(\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var offenders: [String] = []
        text.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("///"), !trimmed.hasPrefix("//") else { return }
            let range = NSRange(line.startIndex..., in: line)
            if regex.firstMatch(in: line, range: range) != nil {
                offenders.append(trimmed)
            }
        }
        return offenders
    }

    /// `LillistCore`'s `Sources/LillistCore` directory, resolved relative to
    /// this test file's own path (`#filePath` gives an absolute path under
    /// `Packages/LillistCore/Tests/LillistCoreTests/Persistence/`).
    private static func sourcesRoot() throws -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        // .../Packages/LillistCore/Tests/LillistCoreTests/Persistence/MutationRollbackConformanceTests.swift
        // -> .../Packages/LillistCore/Sources/LillistCore
        let testsRoot = thisFile
            .deletingLastPathComponent()   // Persistence/
            .deletingLastPathComponent()   // LillistCoreTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // LillistCore/
        return testsRoot.appendingPathComponent("Sources/LillistCore")
    }
}
