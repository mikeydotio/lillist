import Foundation

/// Placeholder declaration so `ShareViewController` and `ShareRootView`
/// compile. Replaced by Task 18 with full text + URL decoding.
struct SharePayload {
    struct Decoded {
        var suggestedTitle: String
        var notes: String?
        var url: URL?
    }

    init(extensionContext: NSExtensionContext?) {}

    func decode() async throws -> Decoded {
        Decoded(suggestedTitle: "", notes: nil, url: nil)
    }
}
