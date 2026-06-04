import Foundation
import os
import Testing
@preconcurrency import UserNotifications
@testable import LillistCore

/// Test double for `UNUserNotificationCenter`. Records added requests,
/// supports removal by identifier, tracks the most recent category set,
/// and exposes a controllable authorization flag.
///
/// Implemented as a `@unchecked Sendable` `final class` with a single
/// `OSAllocatedUnfairLock<State>` guarding all mutable state. The plan
/// originally specified an `actor + nonisolated` shape, but non-Sendable
/// `UN*` collection types cannot legally cross actor isolation under
/// Swift 6 strict concurrency (even with `@preconcurrency import`). The
/// locking matches `UNUserNotificationCenter`'s "serialize all calls"
/// semantics so tests don't accept interleavings the real API forbids.
///
/// Inspection accessors are `async` (returning Sendable snapshots) so
/// tests read like `await fake.addedRequests()` — mirroring the
/// protocol's own async call shape and making "snapshot, not live
/// property" syntactically obvious.
final class FakeUserNotificationCenter: UNUserNotificationCenterProtocol, @unchecked Sendable {
    private struct State {
        var added: [UNNotificationRequest] = []
        var removedIdentifiers: [[String]] = []
        var categories: Set<UNNotificationCategory> = []
        var authorizationGranted: Bool = true
        var requestAuthorizationCallCount: Int = 0
        /// Used by `currentAuthorizationStatus()` (Plan 10). Distinguishes
        /// `notDetermined` (first-launch) from `denied` without forcing
        /// tests to construct a real `UNNotificationSettings`.
        var currentStatusOverride: UNAuthorizationStatus = .notDetermined
    }
    private let state = OSAllocatedUnfairLock<State>(initialState: State())

    // MARK: - Protocol surface

    /// Faithful to `UNUserNotificationCenter.add`: a request whose
    /// identifier matches an existing pending request REPLACES it (the real
    /// API upserts; it never holds two pending requests with one identifier).
    /// `NotificationScheduler` relies on this — it builds
    /// `Dictionary(uniqueKeysWithValues:)` over pending identifiers, which
    /// traps on duplicates. Appending instead would let the fake accept
    /// interleavings (concurrent reconciles adding the same identifier) that
    /// the real center forbids.
    func add(_ request: UNNotificationRequest) async throws {
        state.withLock { s in
            s.added.removeAll { $0.identifier == request.identifier }
            s.added.append(request)
        }
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        state.withLock { $0.added }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        state.withLock { s in
            s.removedIdentifiers.append(identifiers)
            let set = Set(identifiers)
            s.added.removeAll { set.contains($0.identifier) }
        }
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) async {
        state.withLock { $0.categories = categories }
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        state.withLock { s in
            s.requestAuthorizationCallCount += 1
            return s.authorizationGranted
        }
    }

    func notificationSettings() async -> UNNotificationSettings {
        // We can't construct UNNotificationSettings from outside the framework;
        // tests that need to inspect settings should use requestAuthorization() instead.
        // If a test reaches this path, surface it as a test failure rather than
        // crashing the runner; fall back to the real center (which on Simulator
        // returns a denied state) so the caller still gets a UNNotificationSettings.
        Issue.record("FakeUserNotificationCenter.notificationSettings() called — tests should use requestAuthorization() instead")
        return await UNUserNotificationCenter.current().notificationSettings()
    }

    func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        state.withLock { $0.currentStatusOverride }
    }

    // MARK: - Test inspection accessors (Sendable snapshots)

    /// Snapshot of the current pending-request list.
    func addedRequests() async -> [UNNotificationRequest] {
        state.withLock { $0.added }
    }

    /// Snapshot count of currently-pending requests.
    func addedCount() async -> Int {
        state.withLock { $0.added.count }
    }

    /// Every batch of identifiers passed to `removePendingNotificationRequests`,
    /// in call order.
    func removedIdentifiersLog() async -> [[String]] {
        state.withLock { $0.removedIdentifiers }
    }

    /// The set of identifiers in the last `setNotificationCategories` call.
    func categoryIdentifiers() async -> Set<String> {
        state.withLock { Set($0.categories.map(\.identifier)) }
    }

    /// How many times `requestAuthorization` has been called.
    func requestAuthorizationCallCount() async -> Int {
        state.withLock { $0.requestAuthorizationCallCount }
    }

    // MARK: - Test control

    func setAuthorizationGranted(_ granted: Bool) async {
        state.withLock { $0.authorizationGranted = granted }
    }

    /// Drive `currentAuthorizationStatus()` independently of the
    /// "request → boolean grant" path. Used by Plan 10 to test the
    /// `.notDetermined` first-launch branch.
    func setCurrentAuthorizationStatus(_ status: UNAuthorizationStatus) async {
        state.withLock { $0.currentStatusOverride = status }
    }

    func reset() async {
        state.withLock { s in
            s.added.removeAll()
            s.removedIdentifiers.removeAll()
            s.categories.removeAll()
            s.requestAuthorizationCallCount = 0
        }
    }
}
