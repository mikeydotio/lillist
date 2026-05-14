import Foundation
import UniformTypeIdentifiers

/// Decodes the heterogeneous payload an extension context delivers into a
/// shape the share sheet UI can pre-fill.
///
/// Recognized inputs (per `NSExtensionActivationRule` in Info.plist):
/// - Plain text (`UTType.plainText`)
/// - URL (`UTType.url`)
struct SharePayload {
    enum Item: Equatable {
        case text(String)
        case url(URL)
    }

    struct Decoded: Equatable {
        var suggestedTitle: String
        var notes: String?
        var url: URL?
    }

    let items: [Item]

    init(extensionContext: NSExtensionContext?) {
        var collected: [Item] = []
        for input in extensionContext?.inputItems as? [NSExtensionItem] ?? [] {
            for provider in input.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = (try? provider.loadItem(
                        forTypeIdentifier: UTType.url.identifier,
                        options: nil
                    )) as? URL {
                        collected.append(.url(url))
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = (try? provider.loadItem(
                        forTypeIdentifier: UTType.plainText.identifier,
                        options: nil
                    )) as? String {
                        collected.append(.text(text))
                    }
                }
            }
        }
        self.items = collected
    }

    /// Dependency-injectable variant for unit tests.
    init(items: [Item]) {
        self.items = items
    }

    static func makeStub(items: [Item]) -> SharePayload {
        SharePayload(items: items)
    }

    func decode() async throws -> Decoded {
        var title = ""
        var notes: String?
        var url: URL?
        for item in items {
            switch item {
            case .text(let str):
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                title = String(trimmed.prefix(80))
                if trimmed.count > 80 {
                    notes = trimmed
                }
            case .url(let u):
                url = u
                if title.isEmpty {
                    title = "Link: \(u.host ?? u.absoluteString)"
                }
            }
        }
        return Decoded(suggestedTitle: title, notes: notes, url: url)
    }
}
