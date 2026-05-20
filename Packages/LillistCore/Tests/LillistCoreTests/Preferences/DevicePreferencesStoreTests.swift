import Testing
import Foundation
@testable import LillistCore

@Suite("DevicePreferencesStore")
struct DevicePreferencesStoreTests {
    /// Build a fresh, isolated suite name + clear any leftover values so
    /// tests don't interfere with each other or with the developer's
    /// real defaults.
    private static func freshSuiteName() -> String {
        let suite = "DevicePreferencesStoreTests-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        return suite
    }

    @Test("Defaults: onboarding not completed, quick capture enabled, default hotkey, status bar visible, crash prompts on")
    func defaultsForFreshInstall() async {
        let store = DevicePreferencesStore(suiteName: Self.freshSuiteName())
        #expect(await store.hasCompletedOnboarding() == false)
        #expect(await store.quickCaptureEnabled() == true)
        #expect(await store.quickCaptureHotkey() == "ctrl+opt+space")
        #expect(await store.statusBarItemVisible() == true)
        #expect(await store.crashPromptsEnabled() == true)
        #expect(await store.migrationFromCoreDataCompleted == false)
    }

    @Test("Onboarding flag round-trips")
    func onboardingRoundTrip() async {
        let store = DevicePreferencesStore(suiteName: Self.freshSuiteName())
        await store.setHasCompletedOnboarding(true)
        #expect(await store.hasCompletedOnboarding() == true)
        await store.setHasCompletedOnboarding(false)
        #expect(await store.hasCompletedOnboarding() == false)
    }

    @Test("Quick Capture enable + hotkey round-trip")
    func quickCaptureRoundTrip() async {
        let store = DevicePreferencesStore(suiteName: Self.freshSuiteName())
        await store.setQuickCaptureEnabled(false)
        await store.setQuickCaptureHotkey("cmd+shift+l")
        #expect(await store.quickCaptureEnabled() == false)
        #expect(await store.quickCaptureHotkey() == "cmd+shift+l")
    }

    @Test("Status bar visibility round-trips, defaulting to true")
    func statusBarRoundTrip() async {
        let store = DevicePreferencesStore(suiteName: Self.freshSuiteName())
        await store.setStatusBarItemVisible(false)
        #expect(await store.statusBarItemVisible() == false)
        await store.setStatusBarItemVisible(true)
        #expect(await store.statusBarItemVisible() == true)
    }

    @Test("Crash prompts toggle round-trips")
    func crashPromptsRoundTrip() async {
        let store = DevicePreferencesStore(suiteName: Self.freshSuiteName())
        await store.setCrashPromptsEnabled(false)
        #expect(await store.crashPromptsEnabled() == false)
        await store.setCrashPromptsEnabled(true)
        #expect(await store.crashPromptsEnabled() == true)
    }

    @Test("Migration marker is sticky")
    func migrationMarker() async {
        let store = DevicePreferencesStore(suiteName: Self.freshSuiteName())
        #expect(await store.migrationFromCoreDataCompleted == false)
        await store.markMigrationFromCoreDataCompleted()
        #expect(await store.migrationFromCoreDataCompleted == true)
    }

    @Test("Values persist across stores sharing a suite name")
    func acrossInstances() async {
        let suite = Self.freshSuiteName()
        let a = DevicePreferencesStore(suiteName: suite)
        await a.setHasCompletedOnboarding(true)
        await a.setQuickCaptureHotkey("ctrl+shift+space")
        await a.markMigrationFromCoreDataCompleted()

        let b = DevicePreferencesStore(suiteName: suite)
        #expect(await b.hasCompletedOnboarding() == true)
        #expect(await b.quickCaptureHotkey() == "ctrl+shift+space")
        #expect(await b.migrationFromCoreDataCompleted == true)
    }
}
