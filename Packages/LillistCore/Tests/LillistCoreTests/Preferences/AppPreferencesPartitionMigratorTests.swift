import Testing
import Foundation
@testable import LillistCore

@Suite("AppPreferencesPartitionMigrator")
struct AppPreferencesPartitionMigratorTests {
    private static func freshSuiteName() -> String {
        let suite = "AppPreferencesPartitionMigratorTests-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        return suite
    }

    @Test("Copies CD values into DevicePreferencesStore on first run")
    func firstRunCopiesFields() async throws {
        let persistence = try await TestStore.make()
        let cdPrefs = PreferencesStore(persistence: persistence)
        try await cdPrefs.update {
            $0.hasCompletedOnboarding = true
            $0.quickCaptureEnabled = false
            $0.quickCaptureHotkey = "ctrl+shift+space"
            $0.statusBarItemVisible = false
            $0.crashPromptsEnabled = false
        }

        let devicePrefs = DevicePreferencesStore(suiteName: Self.freshSuiteName())
        let migrator = AppPreferencesPartitionMigrator(
            preferences: cdPrefs,
            devicePreferences: devicePrefs
        )
        let outcome = try await migrator.runIfNeeded()

        #expect(outcome == .migrated)
        #expect(await devicePrefs.hasCompletedOnboarding() == true)
        #expect(await devicePrefs.quickCaptureEnabled() == false)
        #expect(await devicePrefs.quickCaptureHotkey() == "ctrl+shift+space")
        #expect(await devicePrefs.statusBarItemVisible() == false)
        #expect(await devicePrefs.crashPromptsEnabled() == false)
        #expect(await devicePrefs.migrationFromCoreDataCompleted == true)
    }

    @Test("Second run short-circuits without rewriting device prefs")
    func secondRunIsNoop() async throws {
        let persistence = try await TestStore.make()
        let cdPrefs = PreferencesStore(persistence: persistence)
        try await cdPrefs.update { $0.hasCompletedOnboarding = true }
        let devicePrefs = DevicePreferencesStore(suiteName: Self.freshSuiteName())
        let migrator = AppPreferencesPartitionMigrator(
            preferences: cdPrefs,
            devicePreferences: devicePrefs
        )
        _ = try await migrator.runIfNeeded()

        // Mutate the device prefs after migration; second run must not
        // clobber the post-migration value.
        await devicePrefs.setHasCompletedOnboarding(false)
        let outcome = try await migrator.runIfNeeded()
        #expect(outcome == .alreadyMigrated)
        #expect(await devicePrefs.hasCompletedOnboarding() == false)
    }
}
