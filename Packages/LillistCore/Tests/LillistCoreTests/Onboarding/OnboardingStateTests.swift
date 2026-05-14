import Testing
import Foundation
@testable import LillistCore

@Suite("OnboardingState")
struct OnboardingStateTests {
    @Test("Fresh store reports not completed")
    func freshIsNotComplete() async throws {
        let p = try await TestStore.make()
        let prefs = PreferencesStore(persistence: p)
        let state = OnboardingState(preferences: prefs)
        let done = try await state.hasCompletedOnboarding()
        #expect(done == false)
    }

    @Test("markCompleted flips the flag")
    func markCompleted() async throws {
        let p = try await TestStore.make()
        let prefs = PreferencesStore(persistence: p)
        let state = OnboardingState(preferences: prefs)
        try await state.markCompleted()
        let done = try await state.hasCompletedOnboarding()
        #expect(done == true)
    }

    @Test("markCompleted is idempotent — singleton row preserved")
    func markCompletedIdempotent() async throws {
        let p = try await TestStore.make()
        let prefs = PreferencesStore(persistence: p)
        let state = OnboardingState(preferences: prefs)
        try await state.markCompleted()
        try await state.markCompleted()
        let done = try await state.hasCompletedOnboarding()
        #expect(done == true)
        #expect(try await prefs.rowCount() == 1)
    }

    @Test("resetForTesting flips the flag back")
    func resetFlipsBack() async throws {
        let p = try await TestStore.make()
        let prefs = PreferencesStore(persistence: p)
        let state = OnboardingState(preferences: prefs)
        try await state.markCompleted()
        try await state.resetForTesting()
        #expect(try await state.hasCompletedOnboarding() == false)
    }
}
