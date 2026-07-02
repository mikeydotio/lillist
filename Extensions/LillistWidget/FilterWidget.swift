import SwiftUI
import WidgetKit

/// The configurable Lillist widget: pick a saved smart filter (`SelectFilterIntent`)
/// and see its tasks. Supports every system family + iOS Lock Screen accessories.
struct FilterWidget: Widget {
    static let kind = "app.lillist.FilterWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: SelectFilterIntent.self,
            provider: FilterTimelineProvider()
        ) { entry in
            FilterWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(Text(verbatim: "Lillist Filter"))
        .description(Text(verbatim: "Show a saved smart filter's tasks."))
        .supportedFamilies(Self.supportedFamilies)
        // The rainbow card fills edge-to-edge (its border IS the widget edge),
        // so disable the system content margins that would inset it.
        .contentMarginsDisabled()
    }

    private static var supportedFamilies: [WidgetFamily] {
        var families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
        #if os(iOS)
        families += [.accessoryCircular, .accessoryRectangular, .accessoryInline]
        #endif
        return families
    }
}
