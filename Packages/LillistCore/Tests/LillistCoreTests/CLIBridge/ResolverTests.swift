import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge.Resolver")
struct ResolverTests {
    private func makeStore() async throws -> (PersistenceController, TaskStore) {
        let p = try await TestStore.make()
        return (p, TaskStore(persistence: p))
    }

    @Test("UUID-prefix token resolves to a single task")
    func uuidPrefix() async throws {
        let (p, store) = try await makeStore()
        let id = try await store.create(title: "Buy milk")
        let prefix = String(id.uuidString.lowercased().prefix(6))
        let result = try await CLIBridge.Resolver.resolve(
            token: prefix,
            scope: .anywhere,
            destructiveness: .readOnly,
            persistence: p
        )
        #expect(result.id == id)
        #expect(result.matchKind == .uuidPrefix)
    }

    @Test("Full UUID resolves with uuidExact match kind")
    func uuidExact() async throws {
        let (p, store) = try await makeStore()
        let id = try await store.create(title: "Buy milk")
        let result = try await CLIBridge.Resolver.resolve(
            token: id.uuidString,
            scope: .anywhere,
            destructiveness: .readOnly,
            persistence: p
        )
        #expect(result.id == id)
        #expect(result.matchKind == .uuidExact)
    }

    @Test("Exact title (case-insensitive) wins over substring")
    func exactWinsOverSubstring() async throws {
        let (p, store) = try await makeStore()
        _ = try await store.create(title: "Buy milk for tomorrow")
        let exact = try await store.create(title: "Buy milk")
        let result = try await CLIBridge.Resolver.resolve(
            token: "buy milk",
            scope: .anywhere,
            destructiveness: .readOnly,
            persistence: p
        )
        #expect(result.id == exact)
        #expect(result.matchKind == .exactTitle)
    }

    @Test("Substring match returns best-effort result for read-only verbs")
    func substringReadOnly() async throws {
        let (p, store) = try await makeStore()
        let only = try await store.create(title: "Buy milk for tomorrow")
        let result = try await CLIBridge.Resolver.resolve(
            token: "milk",
            scope: .anywhere,
            destructiveness: .readOnly,
            persistence: p
        )
        #expect(result.id == only)
        #expect(result.matchKind == .substring)
    }

    @Test("Multiple substring matches throw .ambiguous with candidates")
    func ambiguousMultiple() async throws {
        let (p, store) = try await makeStore()
        _ = try await store.create(title: "Buy milk")
        _ = try await store.create(title: "Buy bread")
        do {
            _ = try await CLIBridge.Resolver.resolve(
                token: "Buy",
                scope: .anywhere,
                destructiveness: .readOnly,
                persistence: p
            )
            Issue.record("expected ambiguous")
        } catch let LillistError.ambiguous(ids) {
            #expect(ids.count == 2)
        } catch {
            Issue.record("unexpected: \(error)")
        }
    }

    @Test("Destructive verb on partial substring match refuses to act")
    func destructiveRefusesPartial() async throws {
        let (p, store) = try await makeStore()
        _ = try await store.create(title: "Buy groceries weekly")
        do {
            _ = try await CLIBridge.Resolver.resolve(
                token: "groc",
                scope: .anywhere,
                destructiveness: .destructive,
                persistence: p
            )
            Issue.record("expected validationFailed")
        } catch LillistError.validationFailed {
            // expected
        } catch {
            Issue.record("unexpected: \(error)")
        }
    }

    @Test("Destructive verb on exact match is allowed")
    func destructiveExactAllowed() async throws {
        let (p, store) = try await makeStore()
        let id = try await store.create(title: "Buy milk")
        let result = try await CLIBridge.Resolver.resolve(
            token: "Buy milk",
            scope: .anywhere,
            destructiveness: .destructive,
            persistence: p
        )
        #expect(result.id == id)
    }

    @Test("Destructive verb on full UUID is allowed")
    func destructiveUUIDAllowed() async throws {
        let (p, store) = try await makeStore()
        let id = try await store.create(title: "Buy milk")
        let result = try await CLIBridge.Resolver.resolve(
            token: id.uuidString,
            scope: .anywhere,
            destructiveness: .destructive,
            persistence: p
        )
        #expect(result.id == id)
    }

    @Test("Default scope excludes trashed tasks")
    func excludesTrashed() async throws {
        let (p, store) = try await makeStore()
        let id = try await store.create(title: "Soon gone")
        try await store.softDelete(id: id)
        do {
            _ = try await CLIBridge.Resolver.resolve(
                token: "soon",
                scope: .anywhere,
                destructiveness: .readOnly,
                persistence: p
            )
            Issue.record("expected notFound")
        } catch LillistError.notFound {
            // expected
        } catch {
            Issue.record("unexpected: \(error)")
        }
    }

    @Test("Default scope excludes closed tasks; includeClosed extends")
    func excludesClosed() async throws {
        let (p, store) = try await makeStore()
        let id = try await store.create(title: "Done item")
        try await store.transition(id: id, to: .closed)
        do {
            _ = try await CLIBridge.Resolver.resolve(
                token: "done",
                scope: .anywhere,
                destructiveness: .readOnly,
                persistence: p
            )
            Issue.record("expected notFound")
        } catch LillistError.notFound {
            // expected
        } catch {
            Issue.record("unexpected: \(error)")
        }
        let result = try await CLIBridge.Resolver.resolve(
            token: "done",
            scope: .anywhereIncludingClosed,
            destructiveness: .readOnly,
            persistence: p
        )
        #expect(result.id == id)
    }

    @Test("Diacritic insensitive: naïve matches naive")
    func diacriticInsensitive() async throws {
        // Token must contain at least one non-hex character so the hex-prefix
        // routing rule (^[0-9a-f]{4,}$) doesn't preempt the title path.
        let (p, store) = try await makeStore()
        let id = try await store.create(title: "Be naïve about it")
        let result = try await CLIBridge.Resolver.resolve(
            token: "naive",
            scope: .anywhere,
            destructiveness: .readOnly,
            persistence: p
        )
        #expect(result.id == id)
    }

    @Test("All-hex token shorter than UUID is treated as a UUID prefix, not a title substring")
    func hexTokenTreatedAsUUIDPrefix() async throws {
        // Documents the design's `^[0-9a-f]{4,}$` rule: a token of all-hex
        // characters routes to UUID-prefix matching, not title fuzzy match.
        let (p, store) = try await makeStore()
        _ = try await store.create(title: "Visit café")
        await #expect(throws: LillistError.notFound) {
            _ = try await CLIBridge.Resolver.resolve(
                token: "cafe",
                scope: .anywhere,
                destructiveness: .readOnly,
                persistence: p
            )
        }
    }

    @Test("Scope.descendantsOf restricts to subtree")
    func descendantsScope() async throws {
        let (p, store) = try await makeStore()
        let parent = try await store.create(title: "Project")
        _ = try await store.create(title: "Buy milk")
        let inside = try await store.create(title: "Buy supplies", parent: parent)
        let result = try await CLIBridge.Resolver.resolve(
            token: "buy",
            scope: .descendantsOf(parent),
            destructiveness: .readOnly,
            persistence: p
        )
        #expect(result.id == inside)
    }

    @Test("Shortest unique short IDs computed from ambiguous candidates")
    func shortIDs() throws {
        let id1 = UUID(uuidString: "AABBCCDD-1111-2222-3333-444444444444")!
        let id2 = UUID(uuidString: "AABBCCEE-1111-2222-3333-444444444444")!
        let shorts = CLIBridge.Resolver.shortestUniqueShortIDs([id1, id2], minLength: 4)
        #expect(shorts[id1] != nil)
        #expect(shorts[id2] != nil)
        #expect(shorts[id1]! != shorts[id2]!)
    }

    @Test("Destructive partial-match error points at the real working path, not the dead --exact flag")
    func destructivePartialErrorMessage() async throws {
        let (p, store) = try await makeStore()
        _ = try await store.create(title: "Buy groceries weekly")
        do {
            _ = try await CLIBridge.Resolver.resolve(
                token: "groc",
                scope: .anywhere,
                destructiveness: .destructive,
                persistence: p
            )
            Issue.record("expected validationFailed")
        } catch let LillistError.validationFailed(issues) {
            let combined = issues.map(\.message).joined(separator: " ")
            #expect(combined.contains("--exact") == false)
            #expect(combined.contains("full title") || combined.contains("UUID"))
        } catch {
            Issue.record("unexpected: \(error)")
        }
    }
}
