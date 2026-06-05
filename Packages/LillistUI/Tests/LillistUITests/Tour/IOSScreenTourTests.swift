#if os(iOS)
import XCTest
import SwiftUI
import SnapshotTesting
import LillistCore
@testable import LillistUI

// Renders iPhone-sized approximations of the iOS app's screens after
// the 3-tab restructure. The five Tab-era screens (Today, All, Filters,
// Search, AllTags) collapsed into a single primary `TasksScreen` with
// an expanding filter header, sort menu, outline list, and trailing-
// only delete swipe. The TaskDetail, QuickCapture, Onboarding, and
// iCloud-required screens remain as parallel surfaces and keep their
// inline-composed snapshots from the previous suite.
@MainActor
final class IOSScreenTourTests: XCTestCase {

    private let phoneSize = CGSize(width: 393, height: 852)   // iPhone 16 Pro logical size

    // MARK: - Sample data

    private func task(
        _ title: String,
        id: UUID = UUID(),
        parent: UUID? = nil,
        status: Status = .todo,
        deadline: Date? = nil,
        modifiedAt: Date? = Date(timeIntervalSince1970: 1_780_000_000)
    ) -> TaskStore.TaskRecord {
        TaskStore.TaskRecord(
            id: id, title: title, notes: "", status: status,
            start: nil, startHasTime: false,
            deadline: deadline, deadlineHasTime: deadline != nil,
            position: 0, isPinned: false, parentID: parent,
            createdAt: Date(timeIntervalSince1970: 1_780_000_000),
            modifiedAt: modifiedAt,
            closedAt: status == .closed ? Date(timeIntervalSince1970: 1_780_000_000) : nil,
            deletedAt: nil
        )
    }

    private func node(_ record: TaskStore.TaskRecord,
                      tagNames: [String] = [],
                      children: [TaskNode] = []) -> TaskNode {
        TaskNode(record: record, tagNames: tagNames, children: children)
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

    private func sampleRoots() -> [TaskNode] {
        let shipID = UUID()
        let shipNode = node(
            task("Ship 1.0 release", id: shipID, status: .blocked,
                 deadline: Date(timeIntervalSince1970: 1_780_300_000)),
            children: [
                node(task("Pull metrics from beta", parent: shipID, status: .closed)),
                node(task("Draft hero paragraph", parent: shipID, status: .started)),
                node(task("Get screenshots from QA", parent: shipID, status: .blocked))
            ]
        )
        return [
            node(task("Buy milk")),
            node(task("Draft launch email", status: .started)),
            shipNode,
            node(task("Reply to investors")),
            node(task("Sync with design", status: .started)),
            node(task("Renew domain")),
            node(task("Read DDIA ch. 6"))
        ]
    }

    private func savedFilterChips() -> [SavedFilterChipSpec] {
        [
            SavedFilterChipSpec(id: UUID(), title: "Inbox"),
            SavedFilterChipSpec(id: UUID(), title: "Upcoming")
        ]
    }

    // MARK: - TasksScreen states

    func test_01_tasks_default_light() {
        let view = phoneShell(fab: true) {
            TasksScreen(
                roots: sampleRoots(),
                syncIndicator: .idle(lastSync: nil),
                buildVersion: "0.1.0 (16)",
                sort: .constant(.personalized),
                isFilterHeaderExpanded: .constant(false),
                searchText: .constant(""),
                selectedTokens: .constant([]),
                selectedSavedFilters: .constant([]),
                savedFilters: savedFilterChips(),
                dragController: DragController()
            )
        }
        assertScreen(view, name: "01-tasks-default-light", colorScheme: .light, size: phoneSize)
    }

    func test_02_tasks_default_dark() {
        let view = phoneShell(fab: true) {
            TasksScreen(
                roots: sampleRoots(),
                syncIndicator: .idle(lastSync: nil),
                buildVersion: "0.1.0 (16)",
                sort: .constant(.personalized),
                isFilterHeaderExpanded: .constant(false),
                searchText: .constant(""),
                selectedTokens: .constant([]),
                selectedSavedFilters: .constant([]),
                savedFilters: savedFilterChips(),
                dragController: DragController()
            )
        }
        assertScreen(view, name: "02-tasks-default-dark", colorScheme: .dark, size: phoneSize)
    }

    func test_03_tasks_filter_expanded_today_token_light() {
        let view = phoneShell(fab: true) {
            TasksScreen(
                roots: sampleRoots(),
                syncIndicator: .idle(lastSync: nil),
                buildVersion: "0.1.0 (16)",
                sort: .constant(.personalized),
                isFilterHeaderExpanded: .constant(true),
                searchText: .constant("ship"),
                selectedTokens: .constant([.today]),
                selectedSavedFilters: .constant([]),
                savedFilters: savedFilterChips(),
                dragController: DragController()
            )
        }
        assertScreen(view, name: "03-tasks-filter-expanded-light", colorScheme: .light, size: phoneSize)
    }

    func test_04_tasks_sort_due_light() {
        let view = phoneShell(fab: true) {
            TasksScreen(
                roots: sampleRoots(),
                syncIndicator: .idle(lastSync: nil),
                buildVersion: "0.1.0 (16)",
                sort: .constant(.due),
                isFilterHeaderExpanded: .constant(false),
                searchText: .constant(""),
                selectedTokens: .constant([]),
                selectedSavedFilters: .constant([]),
                savedFilters: savedFilterChips(),
                dragController: DragController()
            )
        }
        assertScreen(view, name: "04-tasks-sort-due-light", colorScheme: .light, size: phoneSize)
    }

    /// Closed root tasks are now visible in the default list — the
    /// pull-to-refresh "archive" gesture is what hides them. This
    /// snapshot guards the new "completed stays in place" UX.
    func test_11_tasks_completed_rows_visible_light() {
        var roots = sampleRoots()
        roots.append(node(task("Buy milk", status: .closed)))
        roots.append(node(task("Read DDIA ch. 6", status: .closed)))
        let view = phoneShell(fab: true) {
            TasksScreen(
                roots: roots,
                syncIndicator: .idle(lastSync: nil),
                buildVersion: "0.1.0 (16)",
                sort: .constant(.personalized),
                isFilterHeaderExpanded: .constant(false),
                searchText: .constant(""),
                selectedTokens: .constant([]),
                selectedSavedFilters: .constant([]),
                savedFilters: savedFilterChips(),
                dragController: DragController()
            )
        }
        assertScreen(view, name: "11-tasks-completed-rows-visible-light",
                     colorScheme: .light, size: phoneSize)
    }

    /// "21 tasks archived. Tap to undo." banner pinned to the bottom
    /// after a pull-to-refresh archive sweep. The `reduceTransparencyOverride`
    /// is set so the toast's `accessibleMaterial` paints its opaque
    /// fallback — system materials don't render in the headless test
    /// host, leaving the capsule invisible without this override.
    func test_12_tasks_archive_toast_light() {
        let view = phoneShell(fab: true) {
            TasksScreen(
                roots: sampleRoots(),
                syncIndicator: .idle(lastSync: nil),
                buildVersion: "0.1.0 (16)",
                sort: .constant(.personalized),
                isFilterHeaderExpanded: .constant(false),
                searchText: .constant(""),
                selectedTokens: .constant([]),
                selectedSavedFilters: .constant([]),
                isArchiveToastPresented: .constant(true),
                savedFilters: savedFilterChips(),
                archivedCount: 21,
                dragController: DragController()
            )
        }
        .environment(\.reduceTransparencyOverride, true)
        assertScreen(view, name: "12-tasks-archive-toast-light",
                     colorScheme: .light, size: phoneSize)
    }

    /// Snapshot showing `TasksScreen` with an in-progress `.onto` drag:
    /// the phantom "Reply to investors" row should appear near "Sync with
    /// design", which should be rendered with a drop-target border. The
    /// source row at index 3 is invisible (opacity 0) while dragging.
    func test_13_tasks_mid_drag_light() {
        let controller = DragController(onDrop: { _, _ in })
        let roots = sampleRoots()

        // roots[3] = "Reply to investors", roots[4] = "Sync with design"
        let draggedID = roots[3].record.id
        let targetID  = roots[4].record.id

        controller.flatRows = roots.map {
            DragReorderRow(id: $0.record.id, parentID: nil, depth: 0)
        }
        // Synthetic geometry matching the list rendering order.
        var y: CGFloat = 100
        for root in roots {
            controller.geometry[root.record.id] = CGRect(
                x: 12, y: y, width: 369, height: 44
            )
            y += 50
        }
        controller.beginDrag(
            rowID: draggedID,
            originalHeight: 44,
            cursorY: controller.geometry[targetID]?.midY ?? 250
        )
        controller.setResolvedTarget(.onto(targetID: targetID))

        let view = phoneShell(fab: true) {
            TasksScreen(
                roots: roots,
                syncIndicator: .idle(lastSync: nil),
                buildVersion: "0.1.0 (16)",
                sort: .constant(.personalized),
                isFilterHeaderExpanded: .constant(false),
                searchText: .constant(""),
                selectedTokens: .constant([]),
                selectedSavedFilters: .constant([]),
                savedFilters: savedFilterChips(),
                dragController: controller
            )
        }
        assertScreen(view, name: "13-tasks-mid-drag-light", colorScheme: .light, size: phoneSize)
    }

    func test_05_tasks_empty_state_light() {
        let view = phoneShell(fab: true) {
            TasksScreen(
                roots: [],
                syncIndicator: .idle(lastSync: nil),
                buildVersion: "0.1.0 (16)",
                sort: .constant(.personalized),
                isFilterHeaderExpanded: .constant(false),
                searchText: .constant(""),
                selectedTokens: .constant([]),
                selectedSavedFilters: .constant([]),
                savedFilters: savedFilterChips(),
                dragController: DragController()
            )
        }
        assertScreen(view, name: "05-tasks-empty-state-light", colorScheme: .light, size: phoneSize)
    }

    func test_08_settings_light() {
        let view = SettingsScreen(onDone: {}) {
            Section("GENERAL") {
                settingRow(label: "Default list", value: "Today")
                settingRow(label: "First weekday", value: "Monday")
                settingRow(label: "Show subtasks inline", value: "On")
            }
            Section("NOTIFICATIONS") {
                settingRow(label: "Notifications", value: "Enabled")
                settingRow(label: "All-day reminder", value: "9:00 AM")
                settingRow(label: "Snooze default", value: "1 hour")
                settingRow(label: "Morning summary", value: "Weekdays")
            }
            Section("QUICK CAPTURE") {
                settingRow(label: "Share extension", value: "Enabled")
                settingRow(label: "Default list", value: "Inbox")
            }
            Section("CRASH REPORTING") {
                settingRow(label: "Prompt after crashes", value: "On")
                settingRow(label: "Include logs", value: "On")
            }
            Section("ABOUT") {
                settingRow(label: "Version", value: "1.0 (42)")
                settingRow(label: "iCloud", value: "Synced just now")
            }
        }
        .frame(width: phoneSize.width, height: phoneSize.height)
        // SettingsScreen renders a SwiftUI Form, whose per-section AA drift
        // breaches exact-pixel on cold-cache renders (see engineering-notes
        // 2026-05-17 "Form views drift on cold-cache runs"). Relax this one
        // tour snapshot to the Form precision pair; all other tour snapshots
        // stay exact-pixel so they keep catching real regressions.
        assertScreen(view, name: "08-settings-light", colorScheme: .light,
                     size: phoneSize, precision: 0.99, perceptualPrecision: 0.98)
    }

    // MARK: - Non-Tasks screens (inline-composed)

    func test_06_taskDetail_light() {
        let view = ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                detailNavBar(title: "Draft launch email", leading: "Today", trailing: "Edit")
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
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
                        Divider()
                        labelledSection(title: "NOTES") {
                            Text("Outline the customer announcement: highlight CloudKit sync, the new recurrence engine, and the iOS quick-capture share extension.")
                                .font(.system(size: 14))
                        }
                        Divider()
                        labelledSection(title: "SUBTASKS") {
                            VStack(spacing: 4) {
                                taskRow("Pull metrics from beta program", status: .closed)
                                taskRow("Draft hero paragraph", status: .started)
                                taskRow("Get screenshots from QA", status: .blocked,
                                        tags: ["urgent"])
                                taskRow("Schedule review with Alex")
                            }
                        }
                        Divider()
                        labelledSection(title: "JOURNAL") {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "bubble.left")
                                    .foregroundStyle(.tertiary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("May 14, 9:14am")
                                        .font(.caption2).foregroundStyle(.tertiary)
                                    Text("Got first draft to Alex for review. Waiting on the screenshots from QA before sending out broadly.")
                                        .font(.system(size: 13))
                                }
                            }
                        }
                        Spacer(minLength: 80)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                }
            }
            .frame(width: phoneSize.width, height: phoneSize.height)
            .background(Color(.systemBackground))

            FloatingAddButton(onTap: {})
                .padding(.trailing, 18)
                .padding(.bottom, 32)
        }
        assertScreen(view, name: "06-task-detail-light", colorScheme: .light, size: phoneSize)
    }

    func test_07_quickCaptureDialog_dark() {
        let view = ZStack(alignment: .top) {
            Color.black.opacity(0.35).ignoresSafeArea()
            QuickCaptureDialog(
                text: .constant("Buy lemons #errands ^tomorrow"),
                onSubmit: {}
            )
            .padding(.top, 80)
            .padding(.horizontal, 24)
        }
        .frame(width: phoneSize.width, height: phoneSize.height)
        assertScreen(view, name: "07-quick-capture-dialog-dark", colorScheme: .dark, size: phoneSize)
    }

    func test_09_onboarding_light() {
        let view = VStack(spacing: 28) {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "checklist")
                    .font(.system(size: 60, weight: .light))
                    .foregroundStyle(.tint)
                Text("Welcome to Lillist")
                    .font(.system(size: 30, weight: .semibold))
                Text("Your tasks, projects, and journal — synced across every Apple device with iCloud.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            VStack(alignment: .leading, spacing: 14) {
                onboardingBullet(icon: "sparkles", title: "Five smart filters",
                                 message: "Today, Upcoming, Overdue, Inbox, Completed — ready out of the box.")
                onboardingBullet(icon: "bell.badge", title: "Notifications when you ask",
                                 message: "Reminders fire only after you opt in — Lillist won't pester.")
                onboardingBullet(icon: "icloud", title: "Private CloudKit sync",
                                 message: "Your data stays inside your iCloud account. No third-party servers.")
            }
            .padding(.horizontal, 28)
            Spacer()
            VStack(spacing: 10) {
                Button(action: {}) {
                    Text("Set up notifications")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                Button("Maybe later", action: {})
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 32)
        }
        .frame(width: phoneSize.width, height: phoneSize.height)
        .background(Color(.systemBackground))
        assertScreen(view, name: "09-onboarding-light", colorScheme: .light, size: phoneSize)
    }

    func test_10_iCloudRequired_light() {
        let view = VStack(spacing: 24) {
            Spacer()
            Image(systemName: "icloud.slash")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(.secondary)
            Text("iCloud is required")
                .font(.system(size: 24, weight: .semibold))
            Text("Lillist stores everything in your private iCloud database. Sign in to iCloud in Settings to get started.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button(action: {}) {
                Text("Open Settings")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 36)
        }
        .frame(width: phoneSize.width, height: phoneSize.height)
        .background(Color(.systemBackground))
        assertScreen(view, name: "10-icloud-required-light", colorScheme: .light, size: phoneSize)
    }

    // MARK: - Shell helper

    /// Wraps a migrated screen in a NavigationStack, sized to the
    /// iPhone tour viewport, with the FloatingAddButton overlay the
    /// real iOS shell paints.
    @ViewBuilder
    private func phoneShell<C: View>(
        fab: Bool,
        @ViewBuilder content: () -> C
    ) -> some View {
        ZStack(alignment: .bottomTrailing) {
            NavigationStack { content() }
                .frame(width: phoneSize.width, height: phoneSize.height)
                .background(Color(.systemBackground))

            if fab {
                FloatingAddButton(onTap: {})
                    .padding(.trailing, 18)
                    .padding(.bottom, 88)
            }
        }
    }

    // MARK: - Mock chrome retained for test_06 / test_09 only

    @ViewBuilder
    private func detailNavBar(title: String,
                              leading: String?, trailing: String?) -> some View {
        VStack(spacing: 0) {
            HStack {
                if let leading {
                    Text(leading)
                        .font(.system(size: 16))
                        .foregroundStyle(.tint)
                } else {
                    Spacer().frame(width: 60)
                }
                Spacer()
                Text(title).font(.system(size: 17, weight: .semibold))
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 16))
                        .foregroundStyle(.tint)
                } else {
                    Spacer().frame(width: 60)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private func labelledSection<Body: View>(title: String,
                                             @ViewBuilder _ body: () -> Body) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            body()
        }
    }

    @ViewBuilder
    private func onboardingBullet(icon: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(message).font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Settings row mock (test_08 only)

    @ViewBuilder
    private func settingRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    // MARK: - Assertion

    private func assertScreen<V: View>(
        _ view: V,
        name: String,
        colorScheme: ColorScheme,
        size: CGSize,
        precision: Float = 1,
        perceptualPrecision: Float = 1,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let host = UIHostingController(rootView:
            view.environment(\.colorScheme, colorScheme)
                .environment(\.locale, Locale(identifier: "en_US"))
        )
        host.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.layoutIfNeeded()
        let traits = UITraitCollection { mutableTraits in
            mutableTraits.userInterfaceStyle = colorScheme == .dark ? .dark : .light
            mutableTraits.displayScale = 2
        }
        assertSnapshot(
            of: host,
            as: .image(precision: precision,
                       perceptualPrecision: perceptualPrecision,
                       size: size,
                       traits: traits),
            named: name,
            fileID: fileID, file: filePath, testName: testName, line: line, column: column
        )
    }
}
#endif
