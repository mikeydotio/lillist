import XCTest

/// Guards issue #62: a Settings pane became unreachable behind the old
/// TabView's toolbar overflow. `PreferencesWindow`'s sidebar is enum-driven,
/// so asserting `PreferencesPane` is the closest unit-testable proxy for
/// "every pane is present and selectable." `PreferencesPane.swift` is
/// co-compiled into this standalone bundle via `Apps/project.yml` (no app
/// test host), so no `@testable import` is needed.
final class PreferencesPaneTests: XCTestCase {
    func test_hasAllElevenPanesInSidebarOrder() {
        XCTAssertEqual(PreferencesPane.allCases, [
            .iCloudSync, .general, .tagsAndFilters, .notifications, .trash,
            .backups, .quickCapture, .reminders, .crashReporting,
            .diagnostics, .advanced,
        ])
        XCTAssertEqual(PreferencesPane.allCases.count, 11)
    }

    func test_everyPaneHasNonEmptyTitleAndSystemImage() {
        for pane in PreferencesPane.allCases {
            XCTAssertFalse(
                pane.title.trimmingCharacters(in: .whitespaces).isEmpty,
                "\(pane) has an empty title"
            )
            XCTAssertFalse(
                pane.systemImage.trimmingCharacters(in: .whitespaces).isEmpty,
                "\(pane) has an empty systemImage"
            )
        }
    }

    func test_titlesAndSystemImagesAreUnique() {
        let titles = PreferencesPane.allCases.map(\.title)
        let systemImages = PreferencesPane.allCases.map(\.systemImage)
        XCTAssertEqual(Set(titles).count, titles.count, "Duplicate pane title found")
        XCTAssertEqual(Set(systemImages).count, systemImages.count, "Duplicate pane systemImage found")
    }

    func test_idMatchesRawValue() {
        for pane in PreferencesPane.allCases {
            XCTAssertEqual(pane.id, pane.rawValue)
        }
    }
}
