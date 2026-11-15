import FlorettaCore
import SwiftUI

/// One setting row of the style inspector, drawn as an opaque block on the glass
/// panel.
///
/// Why macOS draws the block itself: the panel is the system inspector column's
/// Liquid Glass, and the only way that glass becomes visible is to stop the
/// grouped `Form` from painting its scroll background over it. On macOS that
/// same layer is also where `Form(.grouped)` draws its section plates — with the
/// background hidden the rows came back fully transparent and 13 pt text sat
/// straight on the canvas (checked with an offscreen render of a grouped `Form`:
/// the backdrop showed through every row). `listRowBackground` is ignored inside
/// a macOS `Form`, and `List(.insetGrouped)` does not exist there, so the rows
/// carry an opaque block of their own and the glass stays behind them.
///
/// iOS keeps the inset-grouped section cards it already draws, so nothing is
/// added there: a second plate inside a card would double the layer.
extension View {
    /// - Parameter enabled: `false` for hosts that are not the glass inspector.
    ///   The Settings form shares these rows and stays on the plain grouped
    ///   background.
    func inspectorRowBlock(enabled: Bool = true) -> some View {
        modifier(InspectorRowBlockModifier(enabled: enabled))
    }
}

private struct InspectorRowBlockModifier: ViewModifier {
    var enabled: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        #if os(macOS)
        if enabled {
            content
                // Every row claims the full row width, so blocks of different
                // content (a slider, a menu, a field) share one block edge.
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, CGFloat(InspectorPanelStyle.rowBlockVerticalPadding))
                .padding(.horizontal, CGFloat(InspectorPanelStyle.rowBlockHorizontalInset))
                .background(
                    RoundedRectangle(
                        cornerRadius: CGFloat(InspectorPanelStyle.rowBlockCornerRadius),
                        style: .continuous
                    )
                    .fill(blockColor)
                )
                .padding(.vertical, CGFloat(InspectorPanelStyle.rowBlockSpacing))
        } else {
            content
        }
        #else
        content
        #endif
    }

    /// An opaque colour, never a material and never a translucent wash: it is
    /// the layer that keeps chrome text off the blur.
    private var blockColor: Color {
        let scheme: MapColorScheme = colorScheme == .dark ? .dark : .light
        guard let parsed = BranchColor(hex: InspectorPanelStyle.rowBlockHex(for: scheme)) else {
            return .primary
        }
        return Color(red: parsed.red, green: parsed.green, blue: parsed.blue)
    }
}
