import Testing
import Foundation
@testable import LillistCore

@Suite("OnboardingState")
struct OnboardingStateTests {
    /// Each test gets its own UserDefaults suite name so state can't leak.
    private static func makeStore() -> DevicePreferencesStore {
        let suite = "OnboardingStateTests-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        return DevicePreferencesStore(suiteName: suite)
    }

    private static func makeStore(suiteName: String) -> DevicePreferencesStore {
        DevicePreferencesStore(suiteName: suiteName)
    }

    @Test("Fresh store reports not completed")
    func freshIsNotComplete() async {
        let state = OnboardingState(devicePreferences: Self.makeStore())
        let done = await state.hasCompletedOnboarding()
        #expect(done == false)
    }

    @Test("markCompleted flips the flag")
    func markCompleted() async {
        let state = OnboardingState(devicePreferences: Self.makeStore())
        await state.markCompleted()
        let done = await state.hasCompletedOnboarding()
        #expect(done == true)
    }

    @Test("markCompleted is idempotent")
    func markCompletedIdempotent() async {
        let state = OnboardingState(devicePreferences: Self.makeStore())
        await state.markCompleted()
        await state.markCompleted()
        #expect(await state.hasCompletedOnboarding() == true)
    }

    @Test("resetForTesting flips the flag back")
    func resetFlipsBack() async {
        let state = OnboardingState(devicePreferences: Self.makeStore())
        await state.markCompleted()
        await state.resetForTesting()
        #expect(await state.hasCompletedOnboarding() == false)
    }

    @Test("Onboarding flag survives Core Data store deletion (Plan 21 regression guard)")
    func surivesStoreDeletion() async throws {
        // The point of Plan 21's partition: a destructive sync-mode
        // migration wipes Core Data without touching App Group
        // UserDefaults. The onboarding flag must survive that.
        let suite = "OnboardingStateTests-survivesStoreDeletion-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)

        let stateBeforeMigration = OnboardingState(devicePreferences: Self.makeStore(suiteName: suite))
        await stateBeforeMigration.markCompleted()
        #expect(await stateBeforeMigration.hasCompletedOnboarding() == true)

        // Simulate destructive CD wipe by tearing the in-memory store
        // down and building a fresh one. DevicePreferencesStore stays
        // backed by the same UserDefaults suite.
        let freshPersistence = try await TestStore.make()
        let freshPrefs = PreferencesStore(persistence: freshPersistence)
        // Sanity: brand-new CD store has no onboarding completion flag set.
        #expect(try await freshPrefs.read().hasCompletedOnboarding == false)

        // OnboardingState still reports completed because its source
        // of truth survived the CD wipe.
        let stateAfterMigration = OnboardingState(devicePreferences: Self.makeStore(suiteName: suite))
        #expect(await stateAfterMigration.hasCompletedOnboarding() == true)
    }
}
