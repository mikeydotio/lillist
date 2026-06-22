import Testing
import Foundation
@testable import LillistCore

@Suite("LillistCoreContact recipient resolution")
struct LillistCoreContactTests {

    @Test("Info.plist value wins when present")
    func infoPlistValueWins() {
        let resolved = LillistCoreContact.resolveRecipient(
            infoDictionaryValue: "reports@example.com",
            environmentValue: "env@example.com"
        )
        #expect(resolved == "reports@example.com")
    }

    @Test("Falls back to the environment value when Info.plist is absent")
    func environmentFallback() {
        let resolved = LillistCoreContact.resolveRecipient(
            infoDictionaryValue: nil,
            environmentValue: "env@example.com"
        )
        #expect(resolved == "env@example.com")
    }

    @Test("Empty when neither source is configured")
    func unconfiguredIsEmpty() {
        let resolved = LillistCoreContact.resolveRecipient(
            infoDictionaryValue: nil,
            environmentValue: nil
        )
        #expect(resolved.isEmpty)
    }

    @Test("Blank / whitespace-only values are treated as unset")
    func whitespaceIsUnset() {
        // A build that leaves $(LILLIST_CONTACT_EMAIL) empty produces an
        // empty <string></string> in the Info.plist, which reads back as
        // "" — it must not be taken as a real recipient, and it must not
        // shadow a usable environment fallback.
        let emptyInfo = LillistCoreContact.resolveRecipient(
            infoDictionaryValue: "",
            environmentValue: nil
        )
        #expect(emptyInfo.isEmpty)

        let whitespaceInfoFallsThrough = LillistCoreContact.resolveRecipient(
            infoDictionaryValue: "   \n",
            environmentValue: "env@example.com"
        )
        #expect(whitespaceInfoFallsThrough == "env@example.com")
    }

    @Test("Resolved values are trimmed")
    func trimsSurroundingWhitespace() {
        let resolved = LillistCoreContact.resolveRecipient(
            infoDictionaryValue: "  reports@example.com  ",
            environmentValue: nil
        )
        #expect(resolved == "reports@example.com")
    }
}
