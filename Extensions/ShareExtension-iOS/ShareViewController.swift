import UIKit
import SwiftUI

/// UIKit entry point for the Share Extension. Hosts `ShareRootView` (SwiftUI)
/// via `UIHostingController` and routes cancel/save back through the
/// `NSExtensionContext` so the system dismisses correctly.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let payload = SharePayload(extensionContext: extensionContext)
        let root = ShareRootView(
            payload: payload,
            onCancel: { [weak self] in self?.cancel() },
            onSaved: { [weak self] in self?.complete() }
        )
        let hosting = UIHostingController(rootView: root)
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        hosting.didMove(toParent: self)
    }

    private func cancel() {
        extensionContext?.cancelRequest(
            withError: NSError(domain: "io.mikeydotio.Lillist.Share", code: -1)
        )
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
