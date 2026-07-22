import Foundation
import LillistCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The single centralized seam that selects the best available
/// `FilterQueryTranslator` tier — mirroring the `#available` degradation
/// pattern in `LillistUI/Theme/GlassSurface.swift`. Prefers Private Cloud
/// Compute (iOS/macOS 27+) when the SDK is present and the model reports
/// itself available, falls back to on-device (iOS/macOS 26+), and returns
/// `nil` when neither tier is usable — callers treat `nil` as "hide the
/// smart-search affordance", never as an error.
public enum FilterTranslatorFactory {
    public static func makeBest() -> (any FilterQueryTranslator)? {
        #if canImport(FoundationModels)
        #if canImport(FoundationModels, _version: 2)
        if #available(iOS 27, macOS 27, *) {
            if case .available = PrivateCloudComputeLanguageModel().availability {
                return PrivateCloudComputeQueryTranslator()
            }
        }
        #endif
        if #available(iOS 26, macOS 26, *) {
            if case .available = SystemLanguageModel.default.availability {
                return OnDeviceQueryTranslator()
            }
        }
        #endif
        return nil
    }

    /// Whether the smart-search affordance should be offered at all —
    /// consulted by the UI/CLI before showing the "sparkles" toggle.
    public static var isAgenticSearchSupported: Bool {
        makeBest() != nil
    }
}
