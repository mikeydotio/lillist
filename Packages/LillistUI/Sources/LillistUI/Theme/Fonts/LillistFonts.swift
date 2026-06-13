import SwiftUI
import CoreText

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Registers the bundled Plus Jakarta Sans faces (OFL-licensed, vendored
/// under `Resources/Fonts/`) for the current process.
///
/// Registration is `.process`-scoped, which is correct for every
/// consumer of LillistUI — both apps, the share extension, and test
/// runners — without any per-target `UIAppFonts` plist plumbing (SPM
/// resource-bundle fonts can't be declared there anyway).
///
/// The one-shot is a `static let`, so it is thread-safe and runs at
/// most once. `LillistTypography`'s font factory calls
/// `registerIfNeeded()` lazily; app entry points may also call it
/// eagerly to avoid a first-frame fallback flash.
public enum LillistFonts {
    /// The PostScript family stem. Weight names append directly:
    /// `PlusJakartaSans-SemiBold`.
    public static let familyStem = "PlusJakartaSans"

    /// Bundled weights, file-name == PostScript-name suffixes.
    public static let weights = ["Regular", "Medium", "SemiBold", "Bold", "ExtraBold"]

    /// Registers the bundled faces if they aren't registered yet.
    /// Returns `true` when Plus Jakarta Sans is usable in this process.
    /// On failure (corrupt resources, sandbox surprises) callers fall
    /// back to system fonts — `LillistTypography` handles that
    /// automatically.
    @discardableResult
    public static func registerIfNeeded() -> Bool { registered }

    private static let registered: Bool = {
        // Already present (e.g. a host app registered them)? Done.
        if faceIsUsable("\(familyStem)-Regular") { return true }

        let urls = weights.compactMap { weight in
            Bundle.module.url(forResource: "\(familyStem)-\(weight)", withExtension: "ttf")
        }
        guard urls.count == weights.count else { return false }

        // Errors for individual fonts (e.g. already registered) are
        // tolerable; the usability probe below is the real verdict.
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)

        return faceIsUsable("\(familyStem)-Regular")
    }()

    /// Whether a face with the given PostScript name resolves to an
    /// actual font (not a fallback) in this process.
    static func faceIsUsable(_ postScriptName: String) -> Bool {
        #if canImport(UIKit)
        return UIFont(name: postScriptName, size: 12) != nil
        #elseif canImport(AppKit)
        return NSFont(name: postScriptName, size: 12) != nil
        #endif
    }
}
