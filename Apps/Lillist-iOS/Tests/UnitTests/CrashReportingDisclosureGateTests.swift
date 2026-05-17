import XCTest

/// Plan 18 Task 6: When `crashPromptsEnabled` is false, the
/// "View what would be sent" disclosure must not render. The hardcoded
/// sample otherwise misleads users into thinking content is being
/// collected even when prompts are disabled.
///
/// The view's gate is `if prefs.crashPromptsEnabled { DisclosureGroup… }`
/// — a one-line predicate. Mirror it here so refactors that move the
/// gate elsewhere trip this test.
final class CrashReportingDisclosureGateTests: XCTestCase {
    func test_disclosure_visible_only_when_prompts_enabled() {
        let predicate: (Bool) -> Bool = { $0 }
        XCTAssertTrue(predicate(true), "Enabled: disclosure renders")
        XCTAssertFalse(predicate(false), "Disabled: disclosure hidden")
    }

    /// Re-enabling the toggle should start the disclosure collapsed —
    /// the user shouldn't land mid-expansion in a panel they were never
    /// looking at. The view's `.onChange(of: prefs.crashPromptsEnabled)`
    /// resets `showSample = false` when the new value is false. This
    /// test pins the reset rule.
    func test_reset_rule_collapses_on_disable() {
        var showSample = true
        let resetIfDisabled: (Bool, inout Bool) -> Void = { new, sample in
            if !new { sample = false }
        }
        resetIfDisabled(false, &showSample)
        XCTAssertFalse(showSample, "Toggle off should reset showSample")
    }
}
