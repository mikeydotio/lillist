import Foundation
import LillistCore
#if canImport(FoundationModels, _version: 2)
import FoundationModels

/// Translates natural-language search queries using Apple's
/// `PrivateCloudComputeLanguageModel` — the WWDC-2026 tier issue #51 asks
/// for, available from iOS 27 / macOS 27. Requires the iOS/macOS 27 SDK to
/// even compile (see the "Issue #70" entry in `docs/engineering-notes.md` for
/// the `_version: 2` compile-gate this file relies on); `FilterTranslatorFactory`
/// only constructs this type once it has already confirmed
/// `#available(iOS 27, macOS 27, *)` and that the model reports itself
/// available, and falls back to `OnDeviceQueryTranslator` otherwise.
@available(iOS 27, macOS 27, *)
public struct PrivateCloudComputeQueryTranslator: FilterQueryTranslator {
    public let kind: TranslatorKind = .privateCloudCompute

    public init() {}

    public func generateIntermediateFilter(
        for query: String,
        context: TranslationContext
    ) async throws -> IntermediateFilter {
        let model = PrivateCloudComputeLanguageModel()
        guard case .available = model.availability else {
            throw TranslationFailure.unsupported
        }
        let session = LanguageModelSession(
            model: model,
            instructions: FoundationModelsInstructions.build(for: context)
        )
        let generated = try await FoundationModelsInstructions.respond(session: session, query: query)
        return generated.toIntermediateFilter()
    }
}
#endif
