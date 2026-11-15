import Foundation

/// The style inspector's two layers, written down as numbers so a test can read
/// them without a renderer.
///
/// The panel is one system glass plate. Every setting row is an opaque block on
/// top of it: 13 pt chrome text on a blur picks the canvas colours up through
/// the glyphs, so the panel is the only transparent layer and the rows never are.
public enum InspectorPanelStyle {
    /// Raw value of the `AppleGlassChromeRole` the panel container wraps itself
    /// in. Kept here so a contract test can pin the container to that role.
    public static let glassRole = "inspectorPanel"

    /// Opaque row block. Light keeps the white the grouped form rows already
    /// had; dark is Apple's raised grey — a solid value, not a translucent
    /// wash, so it cannot go grey or dirty when it sits on glass.
    public static let rowBlockLightHex = "#FFFFFF"
    public static let rowBlockDarkHex = "#2C2C2E"

    /// Body and secondary ink on a row block. These are the system label values;
    /// the row block has to clear them on its own, without a stroke.
    public static let inkLightHex = "#1D1D1F"
    public static let inkDarkHex = "#F5F5F7"
    public static let secondaryInkLightHex = "#6E6E73"
    public static let secondaryInkDarkHex = "#A1A1A6"

    /// The panel's own paper: what a row block sits on when the glass has
    /// nothing colourful under it. It is the reference for "the block is raised
    /// off the panel".
    public static let panelBackdropLightHex = "#F2F2F7"
    public static let panelBackdropDarkHex = "#1C1C1E"

    public static let rowBlockCornerRadius: Double = 8
    public static let rowBlockHorizontalInset: Double = 10
    public static let rowBlockVerticalPadding: Double = 5
    public static let rowBlockSpacing: Double = 2

    public static func rowBlockHex(for scheme: MapColorScheme) -> String {
        scheme == .dark ? rowBlockDarkHex : rowBlockLightHex
    }

    public static func inkHex(for scheme: MapColorScheme) -> String {
        scheme == .dark ? inkDarkHex : inkLightHex
    }

    public static func secondaryInkHex(for scheme: MapColorScheme) -> String {
        scheme == .dark ? secondaryInkDarkHex : secondaryInkLightHex
    }

    public static func panelBackdropHex(for scheme: MapColorScheme) -> String {
        scheme == .dark ? panelBackdropDarkHex : panelBackdropLightHex
    }
}
