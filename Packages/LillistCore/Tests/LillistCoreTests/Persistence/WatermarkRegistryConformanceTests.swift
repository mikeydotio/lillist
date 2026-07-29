import Testing
import Foundation

/// `X12`/`L7`'s class-kill, mirroring `5a`'s `MutationRollbackConformanceTests`
/// source-text-scan precedent: `HistoryConsumerID` closes off-registry
/// construction at compile time (`PersistentHistoryTokenStore` can only be
/// built with a case from that enum), but nothing stops a future contributor
/// from bypassing it entirely — writing directly to `UserDefaults` with a
/// hand-typed key string that happens to match one of the three registered
/// watermark keys. This test catches that residual class: every registered
/// key literal must appear **only** in `HistoryConsumerID`'s own declaration.
/// A file that hardcodes one of these strings instead of routing through
/// `HistoryConsumerID`/`PersistentHistoryTokenStore` fails here immediately,
/// independent of whether anyone remembers to write a behavioral regression
/// test for that specific bypass.
@Suite("WatermarkRegistry conformance (X12/L7 class-kill)")
struct WatermarkRegistryConformanceTests {
    /// The three registered watermark key literals, exactly as declared in
    /// `HistoryConsumerID` — duplicated here deliberately (not read from the
    /// enum itself) so this test doesn't depend on the very type it's
    /// auditing for its list of "what to look for."
    static let registeredKeyLiterals: [String] = [
        "app.lillist.persistentHistoryToken",
        "app.lillist.diagnostics.historyToken",
        "app.lillist.backup.historyToken",
    ]

    @Test("Every registered watermark key literal appears only in HistoryConsumerID's own declaration", arguments: registeredKeyLiterals)
    func keyLiteralAppearsOnlyInDeclaration(literal: String) throws {
        let root = try Self.sourcesRoot()
        let quoted = "\"\(literal)\""
        var offenders: [String] = []

        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            Issue.record("Could not enumerate \(root.path)")
            return
        }
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            guard fileURL.lastPathComponent != "WatermarkRegistry.swift" else { continue }
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8), text.contains(quoted) else { continue }
            let relative = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
            offenders.append(relative)
        }

        #expect(offenders.isEmpty, "\(quoted) hardcoded outside WatermarkRegistry.swift in: \(offenders.sorted().joined(separator: ", ")) — route through HistoryConsumerID instead")
    }

    /// `LillistCore`'s `Sources/LillistCore` directory, resolved relative to
    /// this test file's own path — same technique `5a`'s
    /// `MutationRollbackConformanceTests` uses.
    private static func sourcesRoot() throws -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        let testsRoot = thisFile
            .deletingLastPathComponent()   // Persistence/
            .deletingLastPathComponent()   // LillistCoreTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // LillistCore/
        return testsRoot.appendingPathComponent("Sources/LillistCore")
    }
}
