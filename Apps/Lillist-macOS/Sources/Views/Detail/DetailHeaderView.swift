import SwiftUI
import LillistCore
import LillistUI

struct DetailHeaderView: View {
    @Binding var title: String
    let status: Status
    let tagNames: [String]
    @Binding var start: Date?
    @Binding var deadline: Date?
    var onStatusMenu: (Status) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.title.bold())
                Menu {
                    ForEach(Status.allCases, id: \.self) { s in
                        Button { onStatusMenu(s) } label: {
                            Label(StatusGlyph.accessibilityLabel(for: s), systemImage: StatusGlyph.symbol(for: s))
                        }
                    }
                } label: {
                    Label(StatusGlyph.accessibilityLabel(for: status), systemImage: StatusGlyph.symbol(for: status))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(StatusPalette.fill(for: status)))
                        .foregroundStyle(StatusPalette.color(for: status))
                }
                .menuStyle(.borderlessButton)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Status: \(StatusGlyph.accessibilityLabel(for: status))"))
            }

            if !tagNames.isEmpty {
                HStack { ForEach(tagNames, id: \.self) { TagChipView(name: $0) } }
            }

            HStack {
                DatePicker("Start", selection: Binding(
                    get: { start ?? Date() }, set: { start = $0 }
                ), displayedComponents: [.date])
                .labelsHidden()
                .accessibilityLabel(String(localized: "Start date"))
                DatePicker("Deadline", selection: Binding(
                    get: { deadline ?? Date() }, set: { deadline = $0 }
                ), displayedComponents: [.date])
                .labelsHidden()
                .accessibilityLabel(String(localized: "Deadline"))
            }
            .font(.subheadline)
        }
        .padding()
    }
}
