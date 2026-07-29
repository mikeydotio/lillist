import Testing
import Foundation
@testable import LillistCore

/// `L6`: `Series.rule`'s setter used `try?` and fell back to `ruleJSON = nil`
/// on any encode failure — symptom-masking that would silently drop a
/// series' recurrence data rather than surfacing the error, unlike this
/// codebase's sibling JSON-column pattern (`SmartFilterStore.encode(_:)`),
/// which already throws. Fixed by replacing the property setter with a
/// throwing `setRule(_:)` method.
///
/// A genuinely encode-failing `RecurrenceRule` cannot be constructed through
/// any public API today — both `CalendarRule.interval` and
/// `AfterCompletionRule.interval` clamp out-of-range values (including
/// non-finite doubles, per `X16`) before they're ever stored, so
/// `JSONEncoder().encode(_:)` cannot fail for a value this type produces.
/// This suite therefore proves two things instead: (1) the positive path —
/// `setRule` round-trips a valid rule through `ruleJSON`/`rule` exactly —
/// and (2) a source-text conformance check (mirroring `5a`'s
/// `MutationRollbackConformanceTests`/`5c`'s
/// `WatermarkRegistryConformanceTests` precedent) that the `try?`-swallow
/// anti-pattern this plan removes never reappears in this file. Run the
/// conformance test against the pre-fix source and it fails immediately —
/// the genuine red→green proof for a fix whose failure mode is otherwise
/// unreachable through the public type.
@Suite("Series.rule encode discipline (L6)")
struct SeriesRuleEncodeDisciplineTests {
    @Test("setRule round-trips a valid rule through ruleJSON/rule")
    func setRuleRoundTrips() async throws {
        let p = try await TestStore.make()
        let ctx = p.container.viewContext
        try await ctx.perform {
            let series = Series(context: ctx)
            series.id = UUID()
            let rule = RecurrenceRule.calendar(.init(freq: .weekly, interval: 2, byDay: [.monday, .thursday]))
            try series.setRule(rule)
            #expect(series.ruleJSON != nil)
            #expect(series.rule == rule)
        }
    }

    @Test("setRule never nils an existing rule on a subsequent call — a later valid call simply replaces it")
    func setRuleNeverProducesANilRuleFromAValidCall() async throws {
        let p = try await TestStore.make()
        let ctx = p.container.viewContext
        try await ctx.perform {
            let series = Series(context: ctx)
            series.id = UUID()
            try series.setRule(.calendar(.init(freq: .daily, interval: 1)))
            #expect(series.rule != nil)
            try series.setRule(.calendar(.init(freq: .monthly, interval: 3)))
            #expect(series.rule == .calendar(.init(freq: .monthly, interval: 3)), "a second successful setRule call must fully replace the prior rule, never leave it nil")
        }
    }

    @Test("Series+CoreData.swift contains no try?-swallowed rule encode (class-kill for the removed anti-pattern)")
    func noSilentEncodeSwallowRemains() throws {
        let root = try Self.sourcesRoot()
        let fileURL = root.appendingPathComponent("ManagedObjects/Series+CoreData.swift")
        let text = try String(contentsOf: fileURL, encoding: .utf8)

        // The pre-fix shape was `let data = try? JSONEncoder().encode(newValue)`
        // inside the `rule` setter, falling through to `ruleJSON = nil` on
        // failure. Assert neither survives: no `try?` immediately preceding
        // a `JSONEncoder().encode` call, and the setter is gone (`rule` is
        // now get-only; the throwing `setRule(_:)` replaces it).
        #expect(!text.contains("try? JSONEncoder().encode"), "a try?-swallowed encode reappeared in \(fileURL.lastPathComponent) — route through the throwing setRule(_:) instead")
        #expect(text.contains("func setRule("), "setRule(_:) is missing — did the throwing write path get reverted?")
        #expect(!text.contains("set {"), "Series.rule must stay a get-only computed property; a reintroduced setter would resurrect the L6 anti-pattern")
    }

    /// `LillistCore`'s `Sources/LillistCore` directory, resolved relative to
    /// this test file's own path — same technique `5a`'s
    /// `MutationRollbackConformanceTests`/`5c`'s
    /// `WatermarkRegistryConformanceTests` use.
    private static func sourcesRoot() throws -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        let testsRoot = thisFile
            .deletingLastPathComponent()   // Recurrence/
            .deletingLastPathComponent()   // LillistCoreTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // LillistCore/
        return testsRoot.appendingPathComponent("Sources/LillistCore")
    }
}
