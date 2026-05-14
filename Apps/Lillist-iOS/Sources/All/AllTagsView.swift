import SwiftUI
import LillistCore
import LillistUI

// MARK: - Accessibility audit (Plan 8, Task 26)
// - Tag rows use Label(name, systemImage: "tag") — the text is the label.
// - Tree expansion uses List(children:) which exposes disclosure via
//   VoiceOver as "expanded/collapsed" automatically.
// - No fixed font sizes; semantic colors only.

/// Drawer of the tag tree. Tap a tag to navigate to its task list.
/// Design Section 7 iOS subsection — "All opens the tag-tree drawer".
struct AllTagsView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var tree: [TagNode] = []
    @State private var loadError: String?

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView(
                    "Could not load tags",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else if tree.isEmpty {
                ContentUnavailableView(
                    "No tags yet",
                    systemImage: "tag",
                    description: Text("Use #name in Quick Capture to make a tag.")
                )
            } else {
                List(tree, children: \.optionalChildren) { node in
                    NavigationLink(value: TagDestination(id: node.id)) {
                        Label(node.name, systemImage: "tag")
                    }
                }
            }
        }
        .navigationTitle("All")
        .navigationDestination(for: TagDestination.self) { dest in
            TagTaskListView(tagID: dest.id)
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

    private static func buildTree(env: AppEnvironment, parent: UUID?) async throws -> [TagNode] {
        let kids = try await env.tagStore.children(of: parent)
        var out: [TagNode] = []
        for k in kids {
            let grandkids = try await buildTree(env: env, parent: k.id)
            out.append(TagNode(id: k.id, name: k.name, children: grandkids))
        }
        return out
    }
}

struct TagNode: Identifiable, Hashable {
    let id: UUID
    let name: String
    let children: [TagNode]

    var optionalChildren: [TagNode]? { children.isEmpty ? nil : children }
}

/// Distinct destination type so this list's navigation doesn't collide with
/// task-id-based destinations elsewhere in the navigation stack.
struct TagDestination: Hashable {
    let id: UUID
}
