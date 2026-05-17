import Foundation

/// # LillistUI
///
/// Cross-platform SwiftUI component library shared by Lillist's
/// macOS and iOS app targets. Owns the design system, the
/// accessibility-environment helpers, and the shared building
/// blocks both shells compose into platform-specific surfaces.
///
/// ## Public surface
///
/// - **`Components/`** — atomic views: `TaskRowView`,
///   `SidebarRowView`, `StatusIndicatorView`, `BreadcrumbView`,
///   `EmptyStateView`, `TagChipView`, `SyncStatusDotView`.
/// - **`Theme/`** — design tokens. `StatusGlyph`, `TagTint`,
///   `StatusPalette`, `SyncPalette`, and `Tokens.swift` (spacing /
///   radius / typography / timing) — the canonical entry point.
/// - **`Accessibility/`** — environment-aware modifiers
///   (`accessibleAnimation`, `accessibleMaterial`,
///   `ContrastTuned.value(in:standard:increased:)`), platform-aware
///   `AccessibilityAnnouncements.post(_:priority:)`, and the WCAG
///   relative-luminance / contrast-ratio helpers in `ContrastMath`.
/// - **`Recurrence/`** — `RecurrenceEditorView` and view-model.
///   Backed by `LillistCore.RecurrenceRule`.
/// - **`QuickCapture/`** — the macOS panel host
///   (`QuickCaptureView`), shared parser (`QuickCaptureParser`),
///   canonical token list (`QuickCaptureDateSuggestions`).
/// - **`Status/`** — `StatusCycler`, `SyncStatusMonitor`,
///   `SyncIndicator`.
/// - **`DragDrop/`** — cross-platform drag/drop helpers.
/// - **`CrashReporting/`** — shared crash-report submission sheet.
/// - **`iOS/`** — iOS-only views/helpers (`FloatingAddButton`,
///   `QuickCaptureField`, `SizeClassRouter`, `SyncStatusBadge`).
///
/// ## Convention
///
/// Public types live under the directory matching their concern.
/// Update this landing page when adding new directories so the
/// surface stays discoverable.
public enum LillistUI {
    /// SemVer for LillistUI. Bump on public-API changes; pre-1.0,
    /// every release may break.
    public static let version = "0.1.0"
}
