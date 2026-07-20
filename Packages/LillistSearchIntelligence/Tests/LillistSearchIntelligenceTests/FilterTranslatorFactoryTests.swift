import Testing
import Foundation
import LillistCore
@testable import LillistSearchIntelligence

/// `FilterTranslatorFactory` calls live, environment-dependent Apple
/// Intelligence availability APIs (`SystemLanguageModel.default.availability`,
/// `PrivateCloudComputeLanguageModel().availability`) that can't be mocked
/// or forced into a particular state from a test — whether a given run
/// returns a translator depends on the real device/simulator's Apple
/// Intelligence state, which is why this suite only asserts the *contract*
/// (never crashes; whatever it returns is well-formed) rather than a
/// specific tier. Live translation itself is verified manually on a
/// capable device, same as the iCloud live-swap tests.
@Suite("FilterTranslatorFactory")
struct FilterTranslatorFactoryTests {
    @Test("makeBest() never crashes and, when it returns a translator, it is never .mock")
    func makeBestContract() {
        let translator = FilterTranslatorFactory.makeBest()
        if let translator {
            #expect(translator.kind == .onDevice || translator.kind == .privateCloudCompute)
        }
    }

    @Test("isAgenticSearchSupported agrees with makeBest()'s nil-ness")
    func isAgenticSearchSupportedAgreesWithMakeBest() {
        #expect(FilterTranslatorFactory.isAgenticSearchSupported == (FilterTranslatorFactory.makeBest() != nil))
    }
}
