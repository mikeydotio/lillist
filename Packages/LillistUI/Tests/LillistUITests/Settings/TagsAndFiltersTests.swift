import XCTest
@testable import LillistUI

/// Unit coverage for the pure logic behind the Tags & Filters management screen:
/// tag-tree flattening, delete-confirmation copy, and name validity. Mirrors the
/// `ICloudSyncStatusLineTests` precedent — assert the deterministic value helpers,
/// leave the rendered surface to manual verification.
final class TagNodeFlattenTests: XCTestCase {
    private func input(
        _ id: UUID,
        _ name: String,
        parent: UUID? = nil,
        position: Double = 0,
        hex: String? = nil
    ) -> FlatTagInput {
        FlatTagInput(id: id, name: name, tintHex: hex, parentID: parent, position: position)
    }

    func test_empty_returnsEmpty() {
        XCTAssertTrue(TagNode.flatten([]).isEmpty)
    }

    func test_singleRoot_depthZero_noDescendants() {
        let id = UUID()
        let nodes = TagNode.flatten([input(id, "Solo")])
        XCTAssertEqual(nodes.map(\.id), [id])
        XCTAssertEqual(nodes[0].depth, 0)
        XCTAssertEqual(nodes[0].descendantCount, 0)
    }

    func test_parentWithChildren_preorder_childrenSortedByPosition() {
        let parent = UUID(), alpha = UUID(), beta = UUID()
        let nodes = TagNode.flatten([
            input(parent, "Parent"),
            input(beta, "Beta", parent: parent, position: 2),
            input(alpha, "Alpha", parent: parent, position: 1),
        ])
        // Parent first, then children in position order.
        XCTAssertEqual(nodes.map(\.id), [parent, alpha, beta])
        XCTAssertEqual(nodes.map(\.depth), [0, 1, 1])
        XCTAssertEqual(nodes[0].descendantCount, 2)
        XCTAssertEqual(nodes[1].descendantCount, 0)
        XCTAssertEqual(nodes[2].descendantCount, 0)
    }

    func test_deepChain_depthAndDescendantCountAccumulate() {
        let a = UUID(), b = UUID(), c = UUID()
        let nodes = TagNode.flatten([
            input(a, "A"),
            input(c, "C", parent: b),
            input(b, "B", parent: a),
        ])
        XCTAssertEqual(nodes.map(\.id), [a, b, c])
        XCTAssertEqual(nodes.map(\.depth), [0, 1, 2])
        XCTAssertEqual(nodes.map(\.descendantCount), [2, 1, 0])
    }

    func test_multipleRoots_sortedByPositionThenName() {
        let r2 = UUID(), r1 = UUID(), r3 = UUID()
        let nodes = TagNode.flatten([
            input(r2, "B", position: 5),
            input(r1, "A", position: 1),
            input(r3, "C", position: 5),   // ties r2 on position → name tiebreak
        ])
        XCTAssertEqual(nodes.map(\.id), [r1, r2, r3])
    }

    func test_orphanWithMissingParent_treatedAsRoot_notDropped() {
        let missing = UUID(), id = UUID()
        let nodes = TagNode.flatten([input(id, "Orphan", parent: missing)])
        XCTAssertEqual(nodes.map(\.id), [id])
        XCTAssertEqual(nodes[0].depth, 0)
    }

    func test_tintHexPreserved() {
        let id = UUID()
        let nodes = TagNode.flatten([input(id, "Tinted", hex: "#FF0000")])
        XCTAssertEqual(nodes[0].tintHex, "#FF0000")
    }
}

final class TagsFiltersCopyTests: XCTestCase {
    func test_deleteTag_noDescendants_omitsNestedWarning() {
        let msg = TagEditorSheet.deleteConfirmationMessage(name: "Errands", descendantCount: 0)
        XCTAssertTrue(msg.contains("Errands"))
        XCTAssertFalse(msg.lowercased().contains("nested"))
    }

    func test_deleteTag_oneDescendant_usesSingular() {
        let msg = TagEditorSheet.deleteConfirmationMessage(name: "Home", descendantCount: 1)
        XCTAssertTrue(msg.contains("1 nested tag"))
        XCTAssertFalse(msg.contains("nested tags"))
    }

    func test_deleteTag_manyDescendants_usesPluralWithCount() {
        let msg = TagEditorSheet.deleteConfirmationMessage(name: "Home", descendantCount: 4)
        XCTAssertTrue(msg.contains("4 nested tags"))
    }

    func test_deleteFilter_namesTheFilter() {
        let msg = FilterEditorSheet.deleteConfirmationMessage(name: "This Week")
        XCTAssertTrue(msg.contains("This Week"))
    }

    func test_nameValidity_rejectsEmptyAndWhitespace() {
        XCTAssertFalse(TagsFiltersEditing.isNameValid(""))
        XCTAssertFalse(TagsFiltersEditing.isNameValid("   \n\t"))
        XCTAssertTrue(TagsFiltersEditing.isNameValid("Errands"))
        XCTAssertTrue(TagsFiltersEditing.isNameValid("  padded  "))
    }

    func test_normalized_trimsSurroundingWhitespace() {
        XCTAssertEqual(TagsFiltersEditing.normalized("  Errands \n"), "Errands")
    }
}
