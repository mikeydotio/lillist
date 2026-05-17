#if os(macOS)
import XCTest
import SwiftUI
import SnapshotTesting
import LillistCore
@testable import LillistUI

// Renders full-window approximations of the macOS app's screens for
// visual review. Composed from the public LillistUI components plus
// inline mock chrome — the real RootSplitView/SidebarView/TaskListView
// live in the app target and aren't reachable from this test bundle.
@MainActor
final class MacOSScreenTourTests: XCTestCase {

    // MARK: - Sample data

    private func task(
        _ title: String,
        status: Status = .todo,
        deadline: Date? = nil
    ) -> TaskStore.TaskRecord {
        TaskStore.TaskRecord(
            id: UUID(), title: title, notes: "", status: status,
            start: nil, startHasTime: false,
            deadline: deadline, deadlineHasTime: deadline != nil,
            position: 0, isPinned: false, parentID: nil,
            createdAt: Date(timeIntervalSince1970: 1_780_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_780_000_000),
            closedAt: status == .closed ? Date(timeIntervalSince1970: 1_780_000_000) : nil,
            deletedAt: nil
        )
    }

    private func taskRow(
        _ title: String,
        status: Status = .todo,
        deadline: Date? = nil,
        tags: [String] = []
    ) -> some View {
        TaskRowView(
            task: task(title, status: status, deadline: deadline),
            tagNames: tags,
            onStatusClick: {}, onStatusSet: { _ in }
        )
    }

    private struct MockSidebar: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                section("SMART FILTERS")
                SidebarRowView(icon: "sun.max", label: "Today", badge: 6, kind: .smartFilter)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                SidebarRowView(icon: "calendar", label: "Upcoming", badge: 14, kind: .smartFilter)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                SidebarRowView(icon: "exclamationmark.triangle", label: "Overdue", badge: 2, kind: .smartFilter)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                SidebarRowView(icon: "tray", label: "Inbox", badge: 3, kind: .smartFilter)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                SidebarRowView(icon: "checkmark.circle", label: "Completed", kind: .smartFilter)
                    .padding(.horizontal, 10).padding(.vertical, 4)

                section("TAGS")
                SidebarRowView(icon: "tag", label: "work", badge: 8,
                               tint: TagTint(hex: "#3366FF"), kind: .tag)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                SidebarRowView(icon: "tag", label: "errands", badge: 4,
                               tint: TagTint(hex: "#22AA66"), kind: .tag)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                SidebarRowView(icon: "tag", label: "personal", badge: 11,
                               tint: TagTint(hex: "#FF6644"), kind: .tag)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                SidebarRowView(icon: "tag", label: "reading",
                               tint: TagTint(hex: "#AA66FF"), kind: .tag)
                    .padding(.horizontal, 10).padding(.vertical, 4)

                section("OTHER")
                SidebarRowView(icon: "trash", label: "Trash", badge: 2, kind: .trash)
                    .padding(.horizontal, 10).padding(.vertical, 4)

                Spacer()

                HStack {
                    SyncStatusDotView(
                        indicator: .idle(lastSync: Date(timeIntervalSince1970: 1_780_000_000)),
                        onRetry: {}
                    )
                    Text("Synced just now")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(10)
            }
            .frame(width: 240)
            .background(Color(NSColor.controlBackgroundColor))
        }

        @ViewBuilder
        private func section(_ title: String) -> some View {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 14)
                .padding(.bottom, 4)
                .padding(.leading, 16)
        }
    }

    // MARK: - Screens

    func test_01_mainWindow_today_light() {
        assertScreen(
            mainWindow(scheme: .light),
            name: "01-main-window-today-light",
            colorScheme: .light,
            size: CGSize(width: 1280, height: 800)
        )
    }

    func test_02_mainWindow_today_dark() {
        assertScreen(
            mainWindow(scheme: .dark),
            name: "02-main-window-today-dark",
            colorScheme: .dark,
            size: CGSize(width: 1280, height: 800)
        )
    }

    func test_03_mainWindow_emptyDetail_light() {
        let view = HStack(spacing: 0) {
            MockSidebar()
            Divider()
            taskListPane()
                .frame(width: 380)
            Divider()
            EmptyStateView(
                title: "No task selected",
                message: "Choose a task from the list to view its details, notes, and history.",
                systemImage: "doc.text"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
        }
        assertScreen(
            view,
            name: "03-main-window-empty-detail-light",
            colorScheme: .light,
            size: CGSize(width: 1280, height: 800)
        )
    }

    func test_04_quickCapture_empty_light() {
        let view = VStack {
            Spacer()
            QuickCaptureView(text: .constant(""), onSubmit: { _ in }, onCancel: {})
            Spacer()
        }
        .frame(width: 580, height: 160)
        .background(.regularMaterial)
        assertScreen(
            view,
            name: "04-quick-capture-empty-light",
            colorScheme: .light,
            size: CGSize(width: 580, height: 160)
        )
    }

    func test_05_quickCapture_typed_dark() {
        let view = VStack {
            Spacer()
            QuickCaptureView(
                text: .constant("Finalize launch plan #work ^friday"),
                onSubmit: { _ in }, onCancel: {}
            )
            Spacer()
        }
        .frame(width: 580, height: 180)
        .background(.regularMaterial)
        assertScreen(
            view,
            name: "05-quick-capture-typed-dark",
            colorScheme: .dark,
            size: CGSize(width: 580, height: 180)
        )
    }

    func test_06_recurrenceEditor_weekly_light() {
        var vm = RecurrenceEditorViewModel(rule: nil)
        vm.repeats = true
        vm.mode = .calendar
        vm.freq = .weekly
        vm.interval = 1
        vm.byDay = [.monday, .wednesday, .friday]
        let binding = Binding(get: { vm }, set: { vm = $0 })
        let view = RecurrenceEditorView(viewModel: binding, onCommit: { _ in }, onCancel: {})
            .frame(width: 480, height: 720)
        assertScreen(
            view,
            name: "06-recurrence-editor-weekly-light",
            colorScheme: .light,
            size: CGSize(width: 480, height: 720)
        )
    }

    func test_07_recurrenceEditor_afterCompletion_dark() {
        var vm = RecurrenceEditorViewModel(rule: nil)
        vm.repeats = true
        vm.mode = .afterCompletion
        vm.afterCompletionSeconds = 86_400 * 7
        let binding = Binding(get: { vm }, set: { vm = $0 })
        let view = RecurrenceEditorView(viewModel: binding, onCommit: { _ in }, onCancel: {})
            .frame(width: 480, height: 360)
        assertScreen(
            view,
            name: "07-recurrence-editor-after-completion-dark",
            colorScheme: .dark,
            size: CGSize(width: 480, height: 360)
        )
    }

    func test_08_crashReportSheet_light() {
        let model = makeCrashReportModel(description: "I was reorganizing tags in the sidebar when the window froze.")
        let view = CrashReportSheet(
            model: model,
            buildVersion: "1.0 (42)",
            osVersion: "macOS 26.2",
            deviceModel: "MacBookPro18,2"
        )
        .frame(width: 520, height: 640)
        assertScreen(
            view,
            name: "08-crash-report-sheet-light",
            colorScheme: .light,
            size: CGSize(width: 520, height: 640)
        )
    }

    func test_09_emptyTaskList_light() {
        let view = EmptyStateView(
            title: "Nothing to do today",
            message: "Tasks with a start or deadline on or before today appear here. Add one with ⌘N.",
            systemImage: "sun.max"
        )
        .frame(width: 700, height: 480)
        .background(Color(NSColor.textBackgroundColor))
        assertScreen(
            view,
            name: "09-empty-task-list-light",
            colorScheme: .light,
            size: CGSize(width: 700, height: 480)
        )
    }

    func test_10_taskListDense_light() {
        let view = VStack(alignment: .leading, spacing: 0) {
            BreadcrumbView(path: ["Smart Filters", "Today"])
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    taskRow("Buy milk", tags: ["errands"])
                    taskRow("Draft launch email", status: .started, tags: ["work", "urgent"])
                    taskRow("Ship 1.0 release", status: .blocked,
                            deadline: Date(timeIntervalSince1970: 1_780_300_000),
                            tags: ["work"])
                    taskRow("Reply to investors", tags: ["work"])
                    taskRow("Sync with design", status: .started, tags: ["work"])
                    taskRow("Pay rent", status: .closed)
                    taskRow("Renew domain", tags: ["personal"])
                    taskRow("Read 'Designing Data-Intensive Apps' ch. 6",
                            tags: ["reading"])
                    taskRow("Plan birthday dinner",
                            deadline: Date(timeIntervalSince1970: 1_780_500_000),
                            tags: ["personal"])
                    taskRow("Renew passport", status: .blocked,
                            deadline: Date(timeIntervalSince1970: 1_785_000_000),
                            tags: ["personal", "urgent"])
                    taskRow("Order new monitor cable", tags: ["errands"])
                    taskRow("Schedule dentist", status: .closed)
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
            }
        }
        .frame(width: 720, height: 800)
        .background(Color(NSColor.textBackgroundColor))
        assertScreen(
            view,
            name: "10-task-list-dense-light",
            colorScheme: .light,
            size: CGSize(width: 720, height: 800)
        )
    }

    // MARK: - Helpers

    private func mainWindow(scheme: ColorScheme) -> some View {
        HStack(spacing: 0) {
            MockSidebar()
            Divider()
            taskListPane()
                .frame(width: 420)
            Divider()
            taskDetailPane()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func taskListPane() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Today")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
            BreadcrumbView(path: ["Smart Filters", "Today"])
                .padding(.horizontal, 14).padding(.bottom, 8)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    taskRow("Buy milk", tags: ["errands"])
                    taskRow("Draft launch email", status: .started, tags: ["work", "urgent"])
                    taskRow("Ship 1.0 release", status: .blocked,
                            deadline: Date(timeIntervalSince1970: 1_780_300_000),
                            tags: ["work"])
                    taskRow("Reply to investors", tags: ["work"])
                    taskRow("Sync with design", status: .started, tags: ["work"])
                    taskRow("Pay rent", status: .closed)
                    taskRow("Renew domain", tags: ["personal"])
                    taskRow("Read DDIA ch. 6", tags: ["reading"])
                }
                .padding(.horizontal, 6).padding(.vertical, 6)
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    private func taskDetailPane() -> some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    StatusIndicatorView(status: .started, onClick: {}, onSetStatus: { _ in })
                    Text("Draft launch email")
                        .font(.system(size: 22, weight: .semibold))
                    Spacer()
                }

                HStack(spacing: 6) {
                    TagChipView(name: "work", tint: TagTint(hex: "#3366FF"))
                    TagChipView(name: "urgent", tint: TagTint(hex: "#FF6644"))
                    Label("May 22", systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Notes") {
                Text("""
                Outline the customer announcement: highlight CloudKit sync, \
                the new recurrence engine, and the iOS quick-capture share \
                extension. Pair with marketing on hero copy and screenshots.
                """)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            }

            Section("Subtasks") {
                taskRow("Pull metrics from beta program", status: .closed)
                taskRow("Draft hero paragraph", status: .started)
                taskRow("Get screenshots from QA", status: .blocked,
                        tags: ["urgent"])
                taskRow("Schedule review with Alex")
            }

            Section("Journal") {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "bubble.left")
                        .foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("May 14, 9:14am")
                            .font(.caption2).foregroundStyle(.tertiary)
                        Text("Got first draft to Alex for review. Waiting on the screenshots from QA before sending out broadly.")
                            .font(.system(size: 12))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .background(Color(NSColor.textBackgroundColor))
    }

    private func makeCrashReportModel(description: String) -> CrashReportViewModel {
        let canary = CrashCanary(
            pid: 1, startedAt: Date(timeIntervalSince1970: 1_780_000_000),
            buildVersion: "1.0 (42)", hostname: "Lillist.local"
        )
        let reporter = CrashReporter(
            canaryFile: CanaryFile(url: FileManager.default.temporaryDirectory.appendingPathComponent("tour-\(UUID()).json")),
            buildVersion: "1.0 (42)", osVersion: "macOS 26.2", deviceModel: "MacBookPro18,2",
            hostname: "Lillist.local",
            logFetcher: TourNoopLogFetcher(), breadcrumbs: BreadcrumbBuffer(),
            transport: TourNoopTransport()
        )
        let model = CrashReportViewModel(pending: canary, reporter: reporter)
        model.userDescription = description
        return model
    }

    /// Wraps `assertSnapshot` so each screen gets a deterministic file
    /// name we can copy out of __Snapshots__ verbatim.
    private func assertScreen<V: View>(
        _ view: V,
        name: String,
        colorScheme: ColorScheme,
        size: CGSize,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let host = makeHostingView(
            SnapshotHost(colorScheme: colorScheme) { view },
            size: size
        )
        assertSnapshot(
            of: host,
            as: .image(size: size),
            named: name,
            fileID: fileID, file: filePath, testName: testName, line: line, column: column
        )
    }
}

private struct TourNoopLogFetcher: LogFetching {
    func fetchRecentLines(since: Date, subsystem: String) async throws -> [String] { [] }
}

private actor TourNoopTransport: CrashReportTransport {
    func send(_ report: CrashReport) async throws {}
}
#endif
