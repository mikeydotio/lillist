import XCTest
import SwiftUI
import SnapshotTesting
import LillistUI

/// App-hosted snapshot regression for the Rainbow Glass surfaces.
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

    // MARK: - fixtures

    private let fabSize = CGSize(width: 220, height: 180)
    private let buttonsSize = CGSize(width: 240, height: 470)
    private let togglesSize = CGSize(width: 280, height: 130)

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
