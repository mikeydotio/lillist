import SwiftUI
import LillistCore

/// Color tokens for task statuses. Plan 14 introduced the design-token
/// foundation (`LillistSpacing`, `LillistRadius`, `LillistTypography`,
/// `SyncPalette`); the status-pill palette landed as a Plan 15 follow-up
/// so the macOS detail header (Plan 15 Task 6) can paint each status
/// with a recognisable hue. The same palette is intended for re-use on
/// iOS once the equivalent pill view lands.
public enum StatusPalette {
    public static func color(for status: Status) -> Color {
        switch status {
        case .todo:    return Color.secondary
        case .started: return Color.accentColor
        case .blocked: return Color.orange
        case .closed:  return Color.green
        }
    }

    /// A muted fill suitable for backgrounds (capsules, badges). Keeps
    /// the same hue as `color(for:)` but at lower opacity so foreground
    /// text/icons retain contrast.
    public static func fill(for status: Status) -> some ShapeStyle {
        color(for: status).opacity(0.18)
    }
}
