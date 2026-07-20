import Testing
import Foundation
@testable import LillistCore

/// Exercises the real `EventKitRemindersGateway.items(inListID:)` against a
/// live (unauthorized, in this test environment) `EKEventStore` to confirm it
/// throws `RemindersGatewayError.listUnavailable` for an id that doesn't
/// resolve to a calendar, rather than silently returning `[]` (issue #50's
/// origin defect).
///
/// `EKEventStore.calendar(withIdentifier:)` is a pure local lookup — unlike
/// `requestFullAccessToReminders()`, it never triggers the system TCC prompt —
/// so this is expected to run cleanly under headless `swift test` with no
/// Reminders entitlement or granted access. If that assumption turns out
/// wrong on some host (hang, crash, or an unexpected authorization prompt),
/// this case belongs in the app-hosted `Lillist-iOSAppHostedTests` bundle
/// instead (the same pattern used for the live-swap Core Data tests), not
/// deleted — the deterministic reproduction of the drain-level bug already
/// lives in `RemindersImporterTests` via the fake gateway regardless.
@Suite("EventKitRemindersGateway")
struct EventKitRemindersGatewayTests {
    @Test("An id that doesn't resolve to a calendar throws listUnavailable, not an empty result")
    func unknownListThrowsListUnavailable() async throws {
        let gateway = EventKitRemindersGateway()
        await #expect(throws: RemindersGatewayError.listUnavailable(id: "definitely-not-a-real-calendar-id")) {
            _ = try await gateway.items(inListID: "definitely-not-a-real-calendar-id")
        }
    }
}
