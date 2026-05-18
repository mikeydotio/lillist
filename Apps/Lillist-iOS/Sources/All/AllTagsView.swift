import SwiftUI
import LillistCore
import LillistUI

/// Thin wrapper around `LillistUI.AllTagsScreen`. Owns the live tag
/// tree fetch and the `.navigationDestination` that turns a tapped
/// tag's UUID into a `TagTaskListView`. Plan 20a Task 4b.
struct AllTagsView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var tree: [AllTagsScreen.TagNode] = []
    @State private var loadError: String?

    var body: some View {
        AllTagsScreen(
            tree: tree,
            loadError: loadError,
            syncIndicator: env.syncMonitor.indicator,
            onRefresh: { await reload() }
        )
        .navigationDestination(for: UUID.self) { id in
            TagTaskListView(tagID: id)
        }
        .task { await reload() }
    }

    private func reload() async {
        do {
            tree = try await Self.buildTree(env: env, parent: nil)
            loadError = nil
        } catch {
            loadError = "\(error)"
            tree = []
        }
    }

    private static func buildTree(env: AppEnvironment, parent: UUID?) async throws -> [AllTagsScreen.TagNode] {
        let kids = try await env.tagStore.children(of: parent)
        var out: [AllTagsScreen.TagNode] = []
        for k in kids {
            let grandkids = try await buildTree(env: env, parent: k.id)
            out.append(AllTagsScreen.TagNode(id: k.id, name: k.name, children: grandkids))
        }
        return out
    }
}
