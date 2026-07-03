import SwiftUI
import WidgetKit

import LillistCore
import LillistUI

/// Renders a `FilterEntry` for whichever family the system asks for: the
/// rainbow card for the home-screen / desktop families, the accessory views on
/// the Lock Screen (iOS). Maps WidgetKit's `WidgetFamily` onto LillistUI's
/// WidgetKit-free `WidgetLayout`.
struct FilterWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: FilterEntry

    var body: some View {
        content
            .widgetURL(filterURL)
            .containerBackground(for: .widget) { LillistColor.workspace }
    }

    /// Whole-widget tap target: open the app focused on this filter. The "+" and
    /// the status chips are distinct tap targets that override this. The
    /// unfiltered "No Filter" view has no filter to focus, so it just opens the app.
    private var filterURL: URL? {
        guard let id = entry.snapshot?.filterID ?? entry.configuration.filter?.id,
              id != WidgetSnapshot.unfilteredID
        else { return nil }
        return DeepLink.filter(id).url
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot {
            switch family {
            #if os(iOS)
            case .accessoryCircular:
                WidgetAccessoryCircularView(snapshot: snapshot)
            case .accessoryRectangular:
                WidgetAccessoryRectangularView(snapshot: snapshot)
            case .accessoryInline:
                WidgetAccessoryInlineView(snapshot: snapshot)
            #endif
            default:
                WidgetFilterCardView(
                    snapshot: snapshot,
                    layout: Self.layout(for: family),
                    addURL: DeepLink.quickCapture.url,
                    // Tap a row (its title area) to open that task in the app.
                    rowURL: { DeepLink.task($0.id).url }
                ) { row in
                    // Tap the chip to advance the task's status in place
                    // (todo → started → done), matching the app.
                    Button(intent: AdvanceTaskStatusFromWidget(taskID: row.id.uuidString)) {
                        WidgetStatusChip(status: row.status)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            WidgetUnavailableView()
        }
    }

    private static func layout(for family: WidgetFamily) -> WidgetLayout {
        switch family {
        case .systemSmall: .small
        case .systemMedium: .medium
        case .systemLarge: .large
        case .systemExtraLarge: .extraLarge
        default: .medium
        }
    }
}

/// Shown when the snapshot cache is cold and couldn't be rebuilt (e.g. first
/// launch before the app has run, or App Group unavailable).
struct WidgetUnavailableView: View {
    var body: some View {
        VStack(spacing: LillistSpacing.s) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.title3)
                .foregroundStyle(LillistColor.textMuted)
            Text(verbatim: "Open Lillist to sync")
                .font(LillistTypography.subheadline)
                .foregroundStyle(LillistColor.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
