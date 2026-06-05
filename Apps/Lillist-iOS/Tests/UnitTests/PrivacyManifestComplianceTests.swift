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
