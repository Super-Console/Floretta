import FlorettaCore
import SwiftUI

/// One label for both toolbar states.
/// The title stays in the `Label` so an overflow row and the Mac customization
/// panel can show it. `iconOnly` is what the toolbar itself draws.
struct EditorCommandLabel: View {
    var title: String
    var symbol: String
    var display: EditorCommandDisplay

    var body: some View {
        styled.accessibilityLabel(title)
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
