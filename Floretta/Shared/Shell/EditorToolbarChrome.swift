import FlorettaCore
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// One label for both toolbar states.
/// The title stays in the `Label` so an overflow row and the Mac customization
/// panel can show it. `iconOnly` is what the toolbar itself draws.
struct EditorCommandLabel: View {
    var title: String
    var symbol: String
    var display: EditorCommandDisplay
    var accessibilityIdentifier: String? = nil

    var body: some View {
        // Nested UIMenu / UIAction rows drop Button-level identifiers; the
        // SF Symbol Image is what the AX tree actually keeps (see compact
        // share-submenu dumps). Mirror the smoke identifier there too.
        styled
            .accessibilityLabel(title)
            .modifier(CommandAccessibilityIdentifier(identifier: accessibilityIdentifier))
    }

    @ViewBuilder
    private var styled: some View {
        switch display {
        case .iconOnly:
            base.labelStyle(.iconOnly)
        case .iconAndTitle:
            base.labelStyle(.titleAndIcon)
        }
    }

    private var base: some View {
        Label {
            Text(verbatim: title)
        } icon: {
            Image(systemName: symbol)
                .modifier(CommandAccessibilityIdentifier(identifier: accessibilityIdentifier))
        }
    }
}

struct CommandAccessibilityIdentifier: ViewModifier {
    var identifier: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}


#if os(iOS)
/// A toolbar `UIButton` that presents a `UIMenu` we build ourselves.
/// SwiftUI `Menu` drops `accessibilityIdentifier` when it converts nested
/// rows into `UIAction` (compact share submenu keeps only the SF Symbol
/// name). Setting `UIAction.accessibilityIdentifier` here is what the AX
/// tree and XCUITest actually see.
struct IdentifiedSystemMenuButton: UIViewRepresentable {
    var symbol: String
    var accessibilityIdentifier: String
    var accessibilityLabel: String
    var help: String
    var makeMenu: () -> UIMenu

    @MainActor
    final class Coordinator {
        var makeMenu: () -> UIMenu
        init() {
            makeMenu = { UIMenu(children: []) }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.showsMenuAsPrimaryAction = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        context.coordinator.makeMenu = makeMenu
        button.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [coordinator = context.coordinator] completion in
                completion(coordinator.makeMenu().children)
            }
        ])
        apply(to: button)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.makeMenu = makeMenu
        apply(to: button)
    }

    private func apply(to button: UIButton) {
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        button.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
        button.accessibilityIdentifier = accessibilityIdentifier
        button.isAccessibilityElement = true
        button.accessibilityLabel = accessibilityLabel
        button.accessibilityHint = help
        button.accessibilityTraits.insert(.button)
    }
}
#endif
