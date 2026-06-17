import XCTest
import SwiftUI
import SnapshotTesting
import LillistCore
import LillistUI

/// App-hosted snapshot regression for the Rainbow Glass surfaces — the
/// FAB (lavender glass, matching the Quick Capture "Add task" button),
/// buttons, and toggles — and for the two iOS controls that blank the
/// *offscreen* `LillistUITests` capture and therefore must render here:
///   - the `QuickCaptureDialog` (`.panel` glass), and
///   - `StatusIndicatorView` (a `Menu` hit layer — the Menu, not glass,
///     is what blanks offscreen; see the 2026-06-14 refinement).
///
/// Liquid Glass only composites in a live key window, so glass snapshots
/// MUST run here — this bundle is app-hosted, so
/// `drawHierarchyInKeyWindow: true` renders through the simulator's live
/// window. The standalone `LillistUITests` bundle cannot capture glass
/// (it blanks the whole image); see docs/engineering-notes.md 2026-06-12.
///
/// Re-record after an intentional glass change:
///   xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
///     -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
///     -only-testing:Lillist-iOSAppHostedTests/GlassSnapshotTests \
///     RECORD_SNAPSHOTS=YES
final class GlassSnapshotTests: XCTestCase {
    private var recordMode: SnapshotTestingConfiguration.Record {
        ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : .missing
    }

    /// Guards the capture path itself: if a toolchain change ever stops
    /// glass compositing in app-hosted snapshots, this blanks and fails
    /// loudly, instead of silently weakening every other glass baseline.
    @MainActor
    func test_glassCaptureStillWorks() {
        let view = ZStack {
            backdrop
            Circle().fill(.clear).frame(width: 80, height: 80)
                .glassEffect(.regular.tint(.purple).interactive(), in: Circle())
        }
        snapshot(view, size: CGSize(width: 220, height: 180), dark: false)
    }

    @MainActor func test_fab_light() { snapshot(fab, size: fabSize, dark: false) }
    @MainActor func test_fab_dark()  { snapshot(fab, size: fabSize, dark: true) }

    @MainActor func test_buttons_light() { snapshot(buttonGallery, size: buttonsSize, dark: false) }
    @MainActor func test_buttons_dark()  { snapshot(buttonGallery, size: buttonsSize, dark: true) }

    @MainActor func test_toggles_light() { snapshot(toggleGallery, size: togglesSize, dark: false) }
    @MainActor func test_toggles_dark()  { snapshot(toggleGallery, size: togglesSize, dark: true) }

    // QuickCaptureDialog — `.panel` glass, migrated here from
    // `LillistUITests/iOS/iOSSnapshotTests` (it blanked offscreen).
    @MainActor func test_quickCaptureDialog_empty_light()  { snapshot(quickCapture(""), size: captureSize, dark: false) }
    @MainActor func test_quickCaptureDialog_empty_dark()   { snapshot(quickCapture(""), size: captureSize, dark: true) }
    @MainActor func test_quickCaptureDialog_parsed_light() { snapshot(quickCapture("Buy milk #errands ^tomorrow"), size: captureTallSize, dark: false) }
    @MainActor func test_quickCaptureDialog_error_light()  { snapshot(quickCapture("Anything", error: "Couldn't create task"), size: captureTallSize, dark: false) }

    // The interactive status control — its `Menu` hit layer blanks the
    // offscreen capture, so the visual moved here from `iOSSnapshotTests`.
    @MainActor func test_statusIndicator_light() { snapshot(statusGallery, size: statusSize, dark: false) }
    @MainActor func test_statusIndicator_dark()  { snapshot(statusGallery, size: statusSize, dark: true) }

    // The TasksScreen empty state — `RainbowEmptyStateView`, whose
    // `DotGridBackdrop` composites via `.drawingGroup()` (Metal). Like
    // Liquid Glass, Metal does not render in the offscreen
    // `CALayer.render(in:)` capture, so this case moved here from
    // `IOSScreenTourTests` (see docs/engineering-notes.md 2026-06-15).
    @MainActor func test_emptyState_light() { snapshot(emptyState, size: emptySize, dark: false) }
    @MainActor func test_emptyState_dark()  { snapshot(emptyState, size: emptySize, dark: true) }

    // MARK: - fixtures

    private let fabSize = CGSize(width: 220, height: 180)
    private let buttonsSize = CGSize(width: 240, height: 470)
    private let togglesSize = CGSize(width: 280, height: 130)
    private let captureSize = CGSize(width: 380, height: 200)
    private let captureTallSize = CGSize(width: 380, height: 240)
    private let statusSize = CGSize(width: 240, height: 80)
    private let emptySize = CGSize(width: 390, height: 600)

    /// Mirrors `TasksScreen`'s no-tasks empty state: the rainbow-gradient
    /// checklist icon, headline + message, dot-grid backdrop, and the
    /// lavender glass "Capture a task" CTA.
    @MainActor
    private var emptyState: some View {
        RainbowEmptyStateView(
            title: "No tasks yet",
            message: "Every open task shows up here. Capture one to get started.",
            systemImage: "checklist"
        ) {
            Button {
            } label: {
                Label("Capture a task", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.rainbow(.lavender))
        }
    }

    /// The iOS Quick Capture dialog (`.panel` Liquid Glass) over the
    /// dimmed scrim its real presentation uses.
    @MainActor
    private func quickCapture(_ text: String, error: String? = nil) -> some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            QuickCaptureDialog(text: .constant(text), errorMessage: error, onSubmit: {})
                .padding(.horizontal, 24)
        }
    }

    /// All four status states of the interactive control (a `Menu` hit
    /// layer over the solid `StatusCubeView` chip), at the 44pt hit size.
    @MainActor
    private var statusGallery: some View {
        ZStack {
            LillistColor.workspace.ignoresSafeArea()
            HStack(spacing: LillistSpacing.l) {
                StatusIndicatorView(status: .todo, onClick: {}, onSetStatus: { _ in })
                StatusIndicatorView(status: .started, onClick: {}, onSetStatus: { _ in })
                StatusIndicatorView(status: .blocked, onClick: {}, onSetStatus: { _ in })
                StatusIndicatorView(status: .closed, onClick: {}, onSetStatus: { _ in })
            }
        }
    }

    /// Every RainbowButtonStyle variant, glass over a rainbow wash.
    @MainActor
    private var buttonGallery: some View {
        let variants: [(String, RainbowButtonStyle.Variant)] = [
            ("Add task", .lavender), ("Delete", .orange), ("Mark done", .green),
            ("Focus", .blue), ("Run intent", .purple), ("Celebrate", .rainbow),
            ("Secondary", .secondary), ("Ghost", .ghost),
        ]
        return ZStack {
            wash
            VStack(spacing: LillistSpacing.m) {
                ForEach(variants, id: \.0) { title, variant in
                    Button(title) {}.buttonStyle(.rainbow(variant))
                }
            }
        }
    }

    /// The Rainbow Glass toggle in both states.
    @MainActor
    private var toggleGallery: some View {
        ZStack {
            wash
            VStack(spacing: LillistSpacing.l) {
                Toggle("Notifications", isOn: .constant(true)).toggleStyle(.rainbow)
                Toggle("Quiet hours", isOn: .constant(false)).toggleStyle(.rainbow)
            }
            .font(LillistTypography.body)
            .foregroundStyle(LillistColor.textBody)
            .padding(.horizontal, LillistSpacing.xl)
        }
    }

    /// A clean rainbow wash (no overlapping text) for the galleries.
    private var wash: some View {
        ZStack {
            LillistColor.workspace
            RainbowGradient.vertical.opacity(0.16)
        }
        .ignoresSafeArea()
    }

    @MainActor
    private var fab: some View { ZStack { backdrop; FloatingAddButton(onTap: {}) } }

    private var backdrop: some View {
        ZStack {
            LillistColor.workspace
            RainbowGradient.vertical.opacity(0.16)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(0..<6, id: \.self) { _ in
                    Text("content refracting through the glass")
                        .font(LillistTypography.subheadline)
                        .foregroundStyle(LillistColor.textBody)
                }
            }
            .padding()
        }
        .ignoresSafeArea()
    }

    @MainActor
    private func snapshot(_ view: some View, size: CGSize, dark: Bool, function: String = #function) {
        let hosted = view
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, dark ? .dark : .light)
        let host = UIHostingController(rootView: hosted)
        host.overrideUserInterfaceStyle = dark ? .dark : .light
        host.view.frame = CGRect(origin: .zero, size: size)
        withSnapshotTesting(record: recordMode) {
            assertSnapshot(
                of: host,
                as: .image(drawHierarchyInKeyWindow: true, size: size),
                testName: function
            )
        }
    }
}
