#if os(iOS)
import SwiftUI
import LillistCore

/// Search-result row: title with the matched query highlighted, plus
/// (when present) the first notes line that also matched. Uses
/// `AttributedString.backgroundColor` for the highlight so VoiceOver
/// reads the title naturally without spelling out the highlight.
///
/// Lifted into `LillistUI` for Plan 20a so `SearchScreen` can render
/// directly from the snapshot suite without the iOS app target.
public struct SearchResultRowView: View {
    public let task: TaskStore.TaskRecord
    public let query: String

    public init(task: TaskStore.TaskRecord, query: String = "") {
        self.task = task
        self.query = query
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.highlightedTitle(title: task.title, query: query))
                .font(LillistTypography.body)
                .strikethrough(task.status == .closed)
            if let snippet = matchingSnippet {
                Text(snippet)
                    .font(LillistTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "\(task.title), \(statusLabel)", bundle: .module))
    }

    /// Returns the task title wrapped in an `AttributedString` where every
    /// case-insensitive occurrence of `query` gets a yellow background
    /// attribute. Empty query → plain title.
    public nonisolated static func highlightedTitle(title: String, query: String) -> AttributedString {
        var attr = AttributedString(title)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return attr }
        let lowerTitle = title.lowercased()
        let lowerQuery = trimmedQuery.lowercased()
        var searchStart = lowerTitle.startIndex
        while let range = lowerTitle.range(of: lowerQuery, range: searchStart..<lowerTitle.endIndex) {
            let attrLower = AttributedString.Index(range.lowerBound, within: attr)
            let attrUpper = AttributedString.Index(range.upperBound, within: attr)
            if let lower = attrLower, let upper = attrUpper {
                attr[lower..<upper].backgroundColor = .yellow.opacity(0.3)
            }
            searchStart = range.upperBound
        }
        return attr
    }

    private var matchingSnippet: String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard task.notes.localizedCaseInsensitiveContains(trimmed) else { return nil }
        return task.notes
            .components(separatedBy: .newlines)
            .first { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    private var statusLabel: String {
        StatusGlyph.accessibilityLabel(for: task.status)
    }
}
#endif
