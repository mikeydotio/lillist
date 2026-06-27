import LillistCore

/// Single source of truth for which iCloud-sync modal is currently showing.
///
/// Both platform wrappers (`ICloudSyncSection` on iOS, `ICloudSyncPane` on
/// macOS) previously stacked several `.sheet`/`.fullScreenCover` modifiers on a
/// single view. SwiftUI reliably honors only the *last* presentation modifier of
/// each style on a given view, so presenting any of the earlier ones could be
/// clobbered — and, nested inside the Settings sheet, the failed presentation
/// cascaded up and tore down the whole Settings pane (the "Disable iCloud sheet
/// flashes then dismisses, taking Settings with it" bug). Driving every sync
/// modal through a single `.sheet(item:)` over this route removes the conflict:
/// one presentation slot, transitions are clean item swaps.
public enum SyncSheetRoute: Equatable, Identifiable {
    /// "Replace iCloud / Replace this device" enable picker.
    case choice
    /// "Sync first / disable now" confirmation before turning sync off.
    case disable
    /// Explains why sync is paused (account/network), with a disable shortcut.
    case pauseExplainer
    /// Live migration progress. The `id` is **constant** across phases so that
    /// streaming a new phase updates the presented sheet *in place* rather than
    /// dismissing and re-presenting it on every progress tick.
    case progress(MigrationPhase)

    public var id: String {
        switch self {
        case .choice: return "choice"
        case .disable: return "disable"
        case .pauseExplainer: return "pauseExplainer"
        case .progress: return "progress"
        }
    }

    /// Which modal a sync-toggle flip should open: enable → the choice picker,
    /// disable → the disable confirmation.
    public static func afterToggle(on: Bool) -> SyncSheetRoute {
        on ? .choice : .disable
    }
}
