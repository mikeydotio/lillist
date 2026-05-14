import Testing
import Foundation
@testable import LillistCore

@Suite("crashPromptsEnabled preference")
struct CrashPromptPreferenceTests {
    @Test("Default value is true")
    func defaultIsTrue() async throws {
        let persistence = try await TestStore.make()
        let store = PreferencesStore(persistence: persistence)
        let prefs = try await store.read()
        #expect(prefs.crashPromptsEnabled == true)
    }

    @Test("Setting false persists")
    func setFalsePersists() async throws {
        let persistence = try await TestStore.make()
        let store = PreferencesStore(persistence: persistence)
        try await store.setCrashPromptsEnabled(false)
        let prefs = try await store.read()
        #expect(prefs.crashPromptsEnabled == false)
    }

    @Test("Default helper exposes the canonical default")
    func defaultHelper() {
        #expect(PreferencesStore.Prefs.crashPromptsDefault == true)
    }
}
