import FlorettaCore
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Share sheet entry. Safari and Photos both land here, then the user picks a topic.
#if os(iOS)
final class ShareViewController: UIViewController {
    private let session = ShareComposeSession()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        preferredContentSize = CGSize(width: 420, height: 520)
        let host = UIHostingController(rootView: ShareComposeView(session: session))
        host.view.backgroundColor = .systemBackground
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        session.start(extensionContext)
    }
}
#else
final class ShareViewController: NSViewController {
    private let session = ShareComposeSession()

    override func loadView() {
        let host = NSHostingController(rootView: ShareComposeView(session: session))
        view = host.view
        preferredContentSize = NSSize(width: 420, height: 520)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        session.start(extensionContext)
    }
}
#endif
