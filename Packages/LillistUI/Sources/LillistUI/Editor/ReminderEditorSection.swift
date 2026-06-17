import SwiftUI
import LillistCore

/// Net-new reminder-editing surface for the unified editor. Lists the task's
/// notification specs and offers adding a new one — an absolute-time nudge or
/// an offset before the start/deadline.
///
/// Presentation-only: the host wires `onAdd` / `onDelete` to the model
/// (`addReminder` / `deleteReminder`), which auto-promotes a draft first.
public struct ReminderEditorSection: View {
    public var reminders: [NotificationSpecStore.SpecRecord]
    public var onAdd: (NotificationKind, Int32?, Date?) -> Void
    public var onDelete: (UUID) -> Void

    private enum Choice: Hashable, CaseIterable {
        case atTime, beforeDeadline, beforeStart
    }

    /// Minutes-before options for offset reminders.
    private static let offsetOptions: [Int32] = [0, 5, 10, 30, 60, 120, 1440]

    @State private var choice: Choice = .atTime
    @State private var fireDate: Date = Date()
    @State private var offsetMinutes: Int32 = 30

    public init(
        reminders: [NotificationSpecStore.SpecRecord],
        onAdd: @escaping (NotificationKind, Int32?, Date?) -> Void,
        onDelete: @escaping (UUID) -> Void
    ) {
        self.reminders = reminders
        self.onAdd = onAdd
        self.onDelete = onDelete
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LillistSpacing.s) {
            ForEach(reminders, id: \.id) { spec in
                HStack {
                    Label {
                        Text(Self.describe(spec))
                            .font(LillistTypography.subheadline)
                            .foregroundStyle(LillistColor.textBody)
                    } icon: {
                        Image(systemName: "bell.fill")
                            .foregroundStyle(RainbowPalette.cautionAmber.base)
                    }
                    Spacer(minLength: 0)
                    Button {
                        onDelete(spec.id)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(LillistColor.textFaint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Delete reminder", bundle: .module))
                }
            }

            Picker(selection: $choice) {
                Text("At a time", bundle: .module).tag(Choice.atTime)
                Text("Before deadline", bundle: .module).tag(Choice.beforeDeadline)
                Text("Before start", bundle: .module).tag(Choice.beforeStart)
            } label: {
                Text("Reminder kind", bundle: .module)
            }
            .pickerStyle(.menu)

            switch choice {
            case .atTime:
                DatePicker(
                    selection: $fireDate,
                    displayedComponents: [.date, .hourAndMinute]
                ) {
                    Text("Notify at", bundle: .module)
                }
            case .beforeDeadline, .beforeStart:
                Picker(selection: $offsetMinutes) {
                    ForEach(Self.offsetOptions, id: \.self) { mins in
                        Text(Self.offsetLabel(mins)).tag(mins)
                    }
                } label: {
                    Text("How early", bundle: .module)
                }
                .pickerStyle(.menu)
            }

            Button {
                add()
            } label: {
                Text("Add reminder", bundle: .module)
            }
            .buttonStyle(.rainbow(.lavender, size: .sm))
            .accessibilityIdentifier("AddReminderButton")
        }
    }

    private func add() {
        switch choice {
        case .atTime:
            onAdd(.nudge, nil, fireDate)
        case .beforeDeadline:
            onAdd(.offsetDeadline, offsetMinutes, nil)
        case .beforeStart:
            onAdd(.offsetStart, offsetMinutes, nil)
        }
    }

    // MARK: - Formatting (pure, testable)

    nonisolated static func offsetLabel(_ minutes: Int32) -> String {
        switch minutes {
        case 0: return String(localized: "At the time", bundle: .module)
        case 60: return String(localized: "1 hour before", bundle: .module)
        case 120: return String(localized: "2 hours before", bundle: .module)
        case 1440: return String(localized: "1 day before", bundle: .module)
        default: return String(localized: "\(Int(minutes)) min before", bundle: .module)
        }
    }

    nonisolated static func describe(_ spec: NotificationSpecStore.SpecRecord) -> String {
        switch spec.kind {
        case .nudge:
            if let date = spec.fireDate {
                let f = DateFormatter()
                f.dateStyle = .medium
                f.timeStyle = .short
                return f.string(from: date)
            }
            return String(localized: "At a set time", bundle: .module)
        case .offsetDeadline:
            return String(localized: "\(offsetLabel(spec.offsetMinutes ?? 0)) deadline", bundle: .module)
        case .offsetStart:
            return String(localized: "\(offsetLabel(spec.offsetMinutes ?? 0)) start", bundle: .module)
        case .defaultDeadline:
            return String(localized: "Default deadline reminder", bundle: .module)
        case .defaultStart:
            return String(localized: "Default start reminder", bundle: .module)
        }
    }
}
