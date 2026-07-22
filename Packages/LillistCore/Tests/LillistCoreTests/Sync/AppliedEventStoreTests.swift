import Testing
import Foundation
@testable import LillistCore

@Suite("AppliedEventStore")
struct AppliedEventStoreTests {
    private func freshDefaults() -> UserDefaults {
        let suiteName = "AppliedEventStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test("an ID never marked applied reports false")
    func unmarkedIDIsNotApplied() {
        let store = AppliedEventStore(defaults: freshDefaults())
        #expect(store.hasApplied(UUID()) == false)
    }

    @Test("markApplied makes hasApplied true, and only for that ID")
    func markAppliedIsRemembered() {
        let store = AppliedEventStore(defaults: freshDefaults())
        let applied = UUID()
        let untouched = UUID()

        store.markApplied(applied)

        #expect(store.hasApplied(applied))
        #expect(store.hasApplied(untouched) == false)
    }

    @Test("marking the same ID twice is idempotent")
    func markAppliedTwiceIsIdempotent() {
        let store = AppliedEventStore(defaults: freshDefaults())
        let id = UUID()

        store.markApplied(id)
        store.markApplied(id)

        #expect(store.hasApplied(id))
    }

    @Test("state persists across a new instance over the same defaults suite")
    func persistsAcrossInstances() {
        let defaults = freshDefaults()
        let id = UUID()
        AppliedEventStore(defaults: defaults).markApplied(id)

        let reloaded = AppliedEventStore(defaults: defaults)

        #expect(reloaded.hasApplied(id))
    }
}
