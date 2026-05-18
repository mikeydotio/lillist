#if os(iOS)
import SwiftUI
import LillistCore

/// Tag-tree drawer reachable from the "All" tab. Pure presentation —
/// the hosting iOS app's `AllTagsView` owns the @State for the loaded
/// tree, the `.task` that fetches it, and the `.navigationDestination`
/// that turns a tapped tag's UUID into a `TagTaskListView`. Plan 20a
/// Task 4b: composition lives in `LillistUI` so the
/// `IOSScreenTourTests` snapshot suite renders the real screen.
public struct AllTagsScreen: View {
    /// Recursive tag tree node — id, display name, optional children.
    /// Lifted into LillistUI alongside `AllTagsScreen` so the snapshot
    /// suite can build mock trees without reaching into iOS app types.
    public struct TagNode: Identifiable, Hashable, Sendable {
        public let id: UUID
        public let name: String
        public let children: [TagNode]

        public init(id: UUID, name: String, children: [TagNode] = []) {
            self.id = id
            self.name = name
            self.children = children
        }

        public var optionalChildren: [TagNode]? {
            children.isEmpty ? nil : children
        }
    }

    public var tree: [TagNode]
    public var loadError: String?
    public var syncIndicator: SyncIndicator
    public var onRefresh: @MainActor () async -> Void

    @Environment(\.quickCaptureAction) private var quickCaptureAction

    public init(
        tree: [TagNode],
        loadError: String? = nil,
        syncIndicator: SyncIndicator = .idle(lastSync: nil),
        onRefresh: @escaping @MainActor () async -> Void = {}
    ) {
        self.tree = tree
        self.loadError = loadError
        self.syncIndicator = syncIndicator
        self.onRefresh = onRefresh
    }

    public var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView(
                    "Could not load tags",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else if tree.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "No tags yet", bundle: .module),
                          systemImage: "tag")
                } description: {
                    Text("Use #name in Quick Capture to make a tag.")
                } actions: {
                    Button {
                        quickCaptureAction()
                    } label: {
                        Label(String(localized: "Capture a task", bundle: .module),
                              systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List(tree, children: \.optionalChildren) { node in
                    NavigationLink(value: node.id) {
                        Label(node.name, systemImage: "tag")
                    }
                }
            }
        }
        .navigationTitle(Text(String(localized: "All", bundle: .module)))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SyncStatusBadge(indicator: syncIndicator)
            }
        }
        .refreshable { await onRefresh() }
    }
}
#endif
