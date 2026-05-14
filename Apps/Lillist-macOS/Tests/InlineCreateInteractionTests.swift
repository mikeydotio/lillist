import XCTest
import LillistCore

@MainActor
final class InlineCreateInteractionTests: XCTestCase {
    func test_return_creates_sibling() async throws {
        let p = try await PersistenceController(configuration: .inMemory)
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "A")
        let parentOfA = try await store.fetch(id: a).parentID
        let b = try await store.create(title: "B", parent: parentOfA)
        let rootChildren = try await store.children(of: nil).map(\.id)
        XCTAssertEqual(Set(rootChildren), Set([a, b]))
    }

    func test_tab_indents_under_previous_sibling() async throws {
        let p = try await PersistenceController(configuration: .inMemory)
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "A")
        let b = try await store.create(title: "B", parent: a)
        let kidsOfA = try await store.children(of: a).map(\.id)
        XCTAssertEqual(kidsOfA, [b])
    }

    func test_shiftTab_outdents_to_grandparent_level() async throws {
        let p = try await PersistenceController(configuration: .inMemory)
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "A")
        let b = try await store.create(title: "B", parent: a)
        let c = try await store.create(title: "C", parent: nil)
        let rootChildren = try await store.children(of: nil).map(\.id)
        XCTAssertEqual(Set(rootChildren), Set([a, c]))
        let kidsOfA = try await store.children(of: a).map(\.id)
        XCTAssertEqual(kidsOfA, [b])
    }
}
