import Testing
import Foundation
@testable import LillistCore

@Suite("AccountIdentityStore")
struct AccountIdentityStoreTests {
    /// A test-controlled `AccountIdentityProbing` that returns whatever
    /// token was last set, mirroring `FileMigrationJournalStore`-adjacent
    /// tests' `MockProvider`-style seams.
    final class FakeProbe: AccountIdentityProbing, @unchecked Sendable {
        var next: AccountIdentityToken?
        init(_ next: AccountIdentityToken? = nil) { self.next = next }
        func currentIdentity() -> AccountIdentityToken? { next }
    }

    /// Builds two distinct, stable tokens for comparison tests. Each call
    /// archives a freshly-allocated `NSString` wrapped as the "ubiquity
    /// token" stand-in — two archives of equal strings must compare equal
    /// via `AccountIdentityToken.==`, two different strings must not.
    private func token(_ value: String) -> AccountIdentityToken {
        let object = NSString(string: value)
        return AccountIdentityToken(ubiquityToken: object)!
    }

    // MARK: - AccountIdentityToken equality

    @Test("test_S3_tokenEqualityViaRoundTripArchive")
    func tokenEqualityViaRoundTripArchive() {
        let a1 = token("account-A")
        let a2 = token("account-A")
        let b = token("account-B")
        #expect(a1 == a2, "two archives of an equal underlying object must compare equal")
        #expect(a1 != b, "two archives of different underlying objects must not compare equal")
    }

    // MARK: - check()

    @Test("test_S3_firstLaunchAdoptsSilently")
    func firstLaunchAdoptsSilently() throws {
        let storage = InMemoryAccountIdentityRecordStore()
        let probe = FakeProbe(token("account-A"))
        let store = AccountIdentityStore(probe: probe, storage: storage)

        let result = try store.check()

        #expect(result == .firstLaunch)
        #expect(try storage.readIdentity() == token("account-A"), "first launch must adopt the current identity")
    }

    @Test("test_S3_firstLaunchWithNoCurrentIdentityIsANoOp")
    func firstLaunchWithNoCurrentIdentityIsANoOp() throws {
        let storage = InMemoryAccountIdentityRecordStore()
        let probe = FakeProbe(nil)
        let store = AccountIdentityStore(probe: probe, storage: storage)

        let result = try store.check()

        #expect(result == .firstLaunch)
        #expect(try storage.readIdentity() == nil, "nothing to adopt when no iCloud account is signed in yet")
    }

    @Test("test_S3_matchingIdentityReturnsMatch")
    func matchingIdentityReturnsMatch() throws {
        let storage = InMemoryAccountIdentityRecordStore()
        let probe = FakeProbe(token("account-A"))
        let store = AccountIdentityStore(probe: probe, storage: storage)
        _ = try store.check() // adopts on first launch

        let result = try store.check()

        #expect(result == .match)
    }

    @Test("test_S3_signedOutIsNotAMismatch_storageUntouched")
    func signedOutIsNotAMismatch() throws {
        let storage = InMemoryAccountIdentityRecordStore()
        let probe = FakeProbe(token("account-A"))
        let store = AccountIdentityStore(probe: probe, storage: storage)
        _ = try store.check() // adopts account-A

        probe.next = nil // signed out entirely
        let result = try store.check()

        #expect(result == .signedOut)
        #expect(try storage.readIdentity() == token("account-A"), "a temporary sign-out must not forget the last-known identity")
    }

    @Test("test_S3_differingIdentityReturnsMismatch")
    func differingIdentityReturnsMismatch() throws {
        let storage = InMemoryAccountIdentityRecordStore()
        let probe = FakeProbe(token("account-A"))
        let store = AccountIdentityStore(probe: probe, storage: storage)
        _ = try store.check() // adopts account-A

        probe.next = token("account-B")
        let result = try store.check()

        #expect(result == .mismatch)
        #expect(try storage.readIdentity() == token("account-A"), "check() must never mutate storage on a mismatch — adoption is a separate, explicit call")
    }

    // MARK: - adoptCurrentIdentity()

    @Test("test_S3_adoptCurrentIdentityPersistsForNextCheck")
    func adoptCurrentIdentityPersistsForNextCheck() throws {
        let storage = InMemoryAccountIdentityRecordStore()
        let probe = FakeProbe(token("account-A"))
        let store = AccountIdentityStore(probe: probe, storage: storage)
        _ = try store.check() // adopts account-A

        probe.next = token("account-B")
        #expect(try store.check() == .mismatch)

        try store.adoptCurrentIdentity()
        #expect(try store.check() == .match, "adopting the current identity must make the next check see a match")
    }

    @Test("test_S3_adoptCurrentIdentityThrowsWhenSignedOut")
    func adoptCurrentIdentityThrowsWhenSignedOut() throws {
        let storage = InMemoryAccountIdentityRecordStore()
        let probe = FakeProbe(nil)
        let store = AccountIdentityStore(probe: probe, storage: storage)

        #expect(throws: (any Error).self) {
            try store.adoptCurrentIdentity()
        }
    }
}

@Suite("FileAccountIdentityStore")
struct FileAccountIdentityStoreTests {
    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("lillist-account-identity-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("account-identity.json")
    }

    @Test("Reading a missing file returns nil, not an error")
    func readMissingIsNil() throws {
        let store = FileAccountIdentityStore(url: makeTempURL())
        #expect(try store.readIdentity() == nil)
    }

    @Test("Write then read round-trips the token")
    func writeThenReadRoundTrips() throws {
        let url = makeTempURL()
        let store = FileAccountIdentityStore(url: url)
        let object = NSString(string: "account-A")
        let token = AccountIdentityToken(ubiquityToken: object)!

        try store.writeIdentity(token)
        let read = try store.readIdentity()

        #expect(read == token)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test("clear() removes a previously-written identity")
    func clearRemoves() throws {
        let url = makeTempURL()
        let store = FileAccountIdentityStore(url: url)
        let token = AccountIdentityToken(ubiquityToken: NSString(string: "account-A"))!
        try store.writeIdentity(token)

        try store.clear()

        #expect(try store.readIdentity() == nil)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test("clear() on a never-written store is a harmless no-op")
    func clearOnMissingIsNoOp() throws {
        let store = FileAccountIdentityStore(url: makeTempURL())
        #expect(throws: Never.self) {
            try store.clear()
        }
    }
}
