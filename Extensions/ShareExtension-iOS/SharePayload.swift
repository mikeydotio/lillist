import Foundation
import UniformTypeIdentifiers

/// Decodes the heterogeneous payload an extension context delivers into a
/// shape the share sheet UI can pre-fill.
///
/// Recognized inputs (per `NSExtensionActivationRule` in Info.plist):
/// - Plain text (`UTType.plainText`)
/// - URL (`UTType.url`)
///
/// `init(extensionContext:)` is synchronous and only **captures** the
/// matching `NSItemProvider`s; the actual item data is loaded inside the
/// async `decode()` pipeline using `loadItem(forTypeIdentifier:options:)`'s
/// async overload. The synchronous, closure-less form of `loadItem`
/// returns `Void` and silently drops the data — using it would make the
/// share sheet never receive the shared URL or text.
///
/// `@unchecked Sendable` because the struct is constructed on the main
/// actor in `ShareViewController.viewDidLoad` and then sent into
/// `ShareRootView`'s async `decode()` pipeline. `NSItemProvider` is
/// documented as thread-safe but isn't yet annotated Sendable in this
/// SDK, so we vouch for the safety at the SharePayload level — every
/// stored value (Item, NSItemProvider) is read-only in practice once
/// the struct is constructed.
struct SharePayload: @unchecked Sendable {
    enum Item: Equatable {
        case text(String)
        case url(URL)
    }

    struct Decoded: Equatable {
        var suggestedTitle: String
        var notes: String?
        var url: URL?
    }

    /// Two construction paths funnel into the same `decode()` pipeline:
    /// production captures providers from the extension context and
    /// resolves them asynchronously; tests inject already-resolved items
    /// via `init(items:)` to skip the system loaders entirely.
    private enum Source {
        case providers([NSItemProvider])
        case items([Item])
    }

    private let source: Source

    init(extensionContext: NSExtensionContext?) {
        var collected: [NSItemProvider] = []
        for input in extensionContext?.inputItems as? [NSExtensionItem] ?? [] {
            for provider in input.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
                    || provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    collected.append(provider)
                }
            }
        }
        self.source = .providers(collected)
    }

    /// Dependency-injectable variant for unit tests.
    init(items: [Item]) {
        self.source = .items(items)
    }

    static func makeStub(items: [Item]) -> SharePayload {
        SharePayload(items: items)
    }

    func decode() async throws -> Decoded {
        let items = await resolveItems()
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

    private func resolveItems() async -> [Item] {
        switch source {
        case .items(let items):
            return items
        case .providers(let providers):
            var result: [Item] = []
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = (try? await provider.loadItem(
                        forTypeIdentifier: UTType.url.identifier,
                        options: nil
                    )) as? URL {
                        result.append(.url(url))
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = (try? await provider.loadItem(
                        forTypeIdentifier: UTType.plainText.identifier,
                        options: nil
                    )) as? String {
                        result.append(.text(text))
                    }
                }
            }
            return result
        }
    }
}
