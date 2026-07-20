// Cross-platform: shared by the iOS app and the macOS main window.
import SwiftUI

/// State of an in-flight or completed natural-language search translation.
/// Deliberately free of `LillistCore`/`LillistSearchIntelligence` — the
/// host translates and hands back only what the UI needs to render, so
/// this package never touches FoundationModels.
public enum SmartSearchState: Equatable, Sendable {
    /// Smart mode is on but nothing has been submitted yet.
    case idle
    /// A translation is in flight — never triggered by every keystroke,
    /// only by explicit submit (translation costs hundreds of ms–seconds).
    case translating
    /// A translation completed. `explanation` is `nil` when the query
    /// mapped to nothing usable ("couldn't understand that").
    case translated(explanation: String?, unmappedTerms: [String])
    /// The translator itself failed (not a mapping failure).
    case failed(message: String)
    /// No capable translator was available at submit time (a race against
    /// the static `isAvailable` check below — e.g. Apple Intelligence was
    /// disabled mid-session).
    case unsupported
}

/// The natural-language search affordance: a toggle that switches the
/// shared search field between literal substring matching and
/// AI-interpreted natural language, plus a status strip showing what a
/// submitted query was interpreted as (or why it couldn't be). Pure
/// presentation — `FilterHeader` hosts this; the app-level container owns
/// `isSmartMode` and drives `state` from its own translation calls.
public struct SmartSearchField: View {
    public var isAvailable: Bool
    @Binding public var isSmartMode: Bool
    public var state: SmartSearchState
    public var onSave: () -> Void

    public init(
        isAvailable: Bool,
        isSmartMode: Binding<Bool>,
        state: SmartSearchState,
        onSave: @escaping () -> Void = {}
    ) {
        self.isAvailable = isAvailable
        self._isSmartMode = isSmartMode
        self.state = state
        self.onSave = onSave
    }

    public var body: some View {
        if isAvailable {
            VStack(alignment: .leading, spacing: 4) {
                toggleRow
                if isSmartMode {
                    statusStrip
                }
            }
        }
    }

    private var toggleRow: some View {
        HStack(spacing: 6) {
            Button {
                isSmartMode.toggle()
            } label: {
                Label {
                    Text(String(localized: "Smart Search", bundle: .module))
                } icon: {
                    Image(systemName: "sparkles")
                        .symbolVariant(isSmartMode ? .fill : .none)
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(
                    isSmartMode
                        ? AnyShapeStyle(RainbowPalette.focusBlue.base)
                        : AnyShapeStyle(LillistColor.textFaint)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Smart Search", bundle: .module))
            .accessibilityIdentifier("SmartSearchToggle")
            .accessibilityAddTraits(isSmartMode ? [.isSelected] : [])

            if isSmartMode {
                Text(String(localized: "Describe what you're looking for, then press Return.", bundle: .module))
                    .font(LillistTypography.caption2)
                    .foregroundStyle(LillistColor.textFaint)
            }
        }
    }

    @ViewBuilder
    private var statusStrip: some View {
        switch state {
        case .idle:
            EmptyView()

        case .translating:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(String(localized: "Interpreting…", bundle: .module))
                    .font(LillistTypography.caption)
                    .foregroundStyle(LillistColor.textFaint)
            }
            .accessibilityIdentifier("SmartSearchTranslating")

        case .translated(let explanation, let unmappedTerms):
            VStack(alignment: .leading, spacing: 2) {
                if let explanation {
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(format: String(localized: "Interpreted as: %@", bundle: .module), explanation))
                            .font(LillistTypography.caption)
                            .foregroundStyle(LillistColor.textFaint)
                        Spacer(minLength: 8)
                        Button(String(localized: "Save as Filter", bundle: .module), action: onSave)
                            .font(LillistTypography.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(RainbowPalette.focusBlue.base)
                            .accessibilityIdentifier("SmartSearchSaveAsFilter")
                    }
                } else {
                    Text(String(localized: "Couldn't understand that query — showing a plain text search instead.", bundle: .module))
                        .font(LillistTypography.caption)
                        .foregroundStyle(LillistColor.textFaint)
                }
                if !unmappedTerms.isEmpty {
                    Text(String(format: String(localized: "Ignored: %@", bundle: .module), unmappedTerms.joined(separator: ", ")))
                        .font(LillistTypography.caption2)
                        .foregroundStyle(LillistColor.textFaint)
                }
            }
            .accessibilityIdentifier("SmartSearchTranslated")

        case .failed(let message):
            Text(message)
                .font(LillistTypography.caption)
                .foregroundStyle(LillistColor.textFaint)
                .accessibilityIdentifier("SmartSearchFailed")

        case .unsupported:
            Text(String(localized: "Smart search requires Apple Intelligence, which isn't available on this device.", bundle: .module))
                .font(LillistTypography.caption)
                .foregroundStyle(LillistColor.textFaint)
                .accessibilityIdentifier("SmartSearchUnsupported")
        }
    }
}
