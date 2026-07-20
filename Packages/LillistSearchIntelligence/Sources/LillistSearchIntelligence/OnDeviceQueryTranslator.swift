import Foundation
import LillistCore
#if canImport(FoundationModels)
import FoundationModels

/// Translates natural-language search queries using Apple's on-device
/// `SystemLanguageModel` — available from iOS 26 / macOS 26. This is the
/// baseline tier: no network round-trip, works on any capable device with
/// Apple Intelligence enabled. `FilterTranslatorFactory` upgrades to
/// `PrivateCloudComputeQueryTranslator` when that tier is available instead.
@available(iOS 26, macOS 26, *)
public struct OnDeviceQueryTranslator: FilterQueryTranslator {
    public let kind: TranslatorKind = .onDevice

    public init() {}

    public func generateIntermediateFilter(
        for query: String,
        context: TranslationContext
    ) async throws -> IntermediateFilter {
        let model = SystemLanguageModel.default
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
