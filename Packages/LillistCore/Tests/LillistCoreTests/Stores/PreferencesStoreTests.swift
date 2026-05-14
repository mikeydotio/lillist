import Testing
import Foundation
@testable import LillistCore

@Suite("PreferencesStore")
struct PreferencesStoreTests {
    @Test("Defaults on first read")
    func defaults() async throws {
        let p = try await TestStore.make()
        let store = PreferencesStore(persistence: p)
        let prefs = try await store.read()
        #expect(prefs.trashRetentionDays == 30)
        #expect(prefs.defaultAllDayHour == 9)
        #expect(prefs.defaultAllDayMinute == 0)
        #expect(prefs.morningSummaryEnabled == true)
    }

    @Test("Update persists across reads")
    func updatePersists() async throws {
        let p = try await TestStore.make()
        let store = PreferencesStore(persistence: p)
        try await store.update { $0.trashRetentionDays = 60 }
        let prefs = try await store.read()
        #expect(prefs.trashRetentionDays == 60)
    }

    @Test("Update is idempotent — single singleton row")
    func singletonRow() async throws {
        let p = try await TestStore.make()
        let store = PreferencesStore(persistence: p)
        try await store.update { $0.trashRetentionDays = 60 }
        try await store.update { $0.trashRetentionDays = 90 }
        #expect(try await store.rowCount() == 1)
    }

    // MARK: - Plan 10 new fields

    @Test("New onboarding/quick-capture fields default to spec values")
    func newDefaults() async throws {
        let p = try await TestStore.make()
        let store = PreferencesStore(persistence: p)
        let prefs = try await store.read()
        #expect(prefs.hasCompletedOnboarding == false)
        #expect(prefs.quickCaptureEnabled == true)
        #expect(prefs.quickCaptureHotkey == "ctrl+opt+space")
        #expect(prefs.statusBarItemVisible == true)
        // crashPromptsEnabled is the Plan 9 name; Plan 10 binds the
        // Settings UI's "Show prompt after crash" toggle to this field.
        #expect(prefs.crashPromptsEnabled == true)
        #expect(prefs.defaultTagTintHex == "#7F8FA6")
    }

    @Test("hasCompletedOnboarding round-trips")
    func onboardingRoundTrip() async throws {
        let p = try await TestStore.make()
        let store = PreferencesStore(persistence: p)
        try await store.update { $0.hasCompletedOnboarding = true }
        let prefs = try await store.read()
        #expect(prefs.hasCompletedOnboarding == true)
    }
}
