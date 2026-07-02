import SwiftUI
import WidgetKit

import LillistUI

/// Entry point for the Lillist widget extension (iOS + macOS).
///
/// Font registration is *process-scoped* (`CTFontManagerRegisterFontURLs`
/// with `.process` scope), so the host app registering Plus Jakarta Sans does
/// **not** carry into this separate extension process. Register here in `init`
/// or every widget view silently falls back to the system font. See the
/// Rainbow Logic notes in `CLAUDE.md` and `LillistFonts`.
@main
struct LillistWidgetBundle: WidgetBundle {
    init() {
        LillistFonts.registerIfNeeded()
    }

    var body: some Widget {
        FilterWidget()
    }
}
