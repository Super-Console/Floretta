import Foundation

/// Which of a theme's two color sets layout and export should paint.
/// Core stays free of SwiftUI: the app maps `ColorScheme` onto this.
public enum MapColorScheme: String, Equatable, Sendable {
    case light
    case dark
}

/// One preset: the existing `LayoutAppearance`, once for light and once for dark.
/// Node overrides stay on `MindMapNodeStyle`. This catalog does not store a second style record.
public struct MapTheme: Equatable, Sendable, Identifiable {
    public var id: String
    /// Chrome string. Callers localize it. It is not document text.
    public var nameKey: String
    public var light: LayoutAppearance
    public var dark: LayoutAppearance

    public init(id: String, nameKey: String, light: LayoutAppearance, dark: LayoutAppearance) {
        self.id = id
        self.nameKey = nameKey
        self.light = light
        self.dark = dark
    }
}

/// At most eight presets. The first is `LayoutAppearance.standard` in light mode,
/// so an unset document paints the same branches as before.
public enum MapThemeCatalog {
    public static let limit = 8
    public static let standardID = "ink"

    public static let all: [MapTheme] = [
        MapTheme(
            id: standardID,
            nameKey: "墨色",
            light: .standard,
            dark: dark(
                colors: [
                    BranchColor(red: 0.94, green: 0.48, blue: 0.40),
                    BranchColor(red: 0.40, green: 0.72, blue: 0.96),
                    BranchColor(red: 0.42, green: 0.82, blue: 0.58),
                    BranchColor(red: 0.96, green: 0.74, blue: 0.32),
                    BranchColor(red: 0.72, green: 0.56, blue: 0.90),
                ],
                center: BranchColor(red: 0.17, green: 0.15, blue: 0.14)
            )
        ),
        MapTheme(
            id: "sea",
            nameKey: "海色",
            light: light(colors: [
                BranchColor(red: 0.05, green: 0.40, blue: 0.52),
                BranchColor(red: 0.08, green: 0.32, blue: 0.62),
                BranchColor(red: 0.04, green: 0.46, blue: 0.44),
                BranchColor(red: 0.12, green: 0.28, blue: 0.70),
                BranchColor(red: 0.02, green: 0.50, blue: 0.58),
            ]),
            dark: dark(
                colors: [
                    BranchColor(red: 0.35, green: 0.86, blue: 0.92),
                    BranchColor(red: 0.40, green: 0.70, blue: 0.98),
                    BranchColor(red: 0.28, green: 0.90, blue: 0.78),
                    BranchColor(red: 0.55, green: 0.72, blue: 0.98),
                    BranchColor(red: 0.45, green: 0.92, blue: 0.88),
                ],
                center: BranchColor(red: 0.07, green: 0.13, blue: 0.16)
            )
        ),
        MapTheme(
            id: "grove",
            nameKey: "林色",
            light: light(colors: [
                BranchColor(red: 0.05, green: 0.38, blue: 0.14),
                BranchColor(red: 0.42, green: 0.50, blue: 0.08),
                BranchColor(red: 0.10, green: 0.46, blue: 0.22),
                BranchColor(red: 0.22, green: 0.40, blue: 0.10),
                BranchColor(red: 0.08, green: 0.32, blue: 0.18),
            ]),
            dark: dark(
                colors: [
                    BranchColor(red: 0.48, green: 0.90, blue: 0.58),
                    BranchColor(red: 0.78, green: 0.92, blue: 0.36),
                    BranchColor(red: 0.40, green: 0.82, blue: 0.48),
                    BranchColor(red: 0.62, green: 0.88, blue: 0.30),
                    BranchColor(red: 0.36, green: 0.78, blue: 0.52),
                ],
                center: BranchColor(red: 0.09, green: 0.14, blue: 0.10)
            )
        ),
        MapTheme(
            id: "ember",
            nameKey: "焰色",
            light: light(colors: [
                BranchColor(red: 0.72, green: 0.22, blue: 0.08),
                BranchColor(red: 0.78, green: 0.36, blue: 0.06),
                BranchColor(red: 0.62, green: 0.12, blue: 0.16),
                BranchColor(red: 0.80, green: 0.46, blue: 0.10),
                BranchColor(red: 0.55, green: 0.20, blue: 0.08),
            ]),
            dark: dark(
                colors: [
                    BranchColor(red: 0.98, green: 0.55, blue: 0.28),
                    BranchColor(red: 0.98, green: 0.74, blue: 0.30),
                    BranchColor(red: 0.98, green: 0.42, blue: 0.42),
                    BranchColor(red: 0.98, green: 0.62, blue: 0.22),
                    BranchColor(red: 0.96, green: 0.78, blue: 0.48),
                ],
                center: BranchColor(red: 0.16, green: 0.10, blue: 0.07)
            )
        ),
        MapTheme(
            id: "dusk",
            nameKey: "暮色",
            light: light(colors: [
                BranchColor(red: 0.40, green: 0.16, blue: 0.72),
                BranchColor(red: 0.52, green: 0.18, blue: 0.62),
                BranchColor(red: 0.34, green: 0.12, blue: 0.55),
                BranchColor(red: 0.58, green: 0.22, blue: 0.78),
                BranchColor(red: 0.46, green: 0.14, blue: 0.48),
            ]),
            dark: dark(
                colors: [
                    BranchColor(red: 0.72, green: 0.58, blue: 0.98),
                    BranchColor(red: 0.90, green: 0.52, blue: 0.96),
                    BranchColor(red: 0.62, green: 0.50, blue: 0.96),
                    BranchColor(red: 0.82, green: 0.64, blue: 0.98),
                    BranchColor(red: 0.78, green: 0.48, blue: 0.88),
                ],
                center: BranchColor(red: 0.11, green: 0.09, blue: 0.16)
            )
        ),
        MapTheme(
            id: "clay",
            nameKey: "陶色",
            light: light(colors: [
                BranchColor(red: 0.55, green: 0.28, blue: 0.14),
                BranchColor(red: 0.48, green: 0.36, blue: 0.16),
                BranchColor(red: 0.40, green: 0.32, blue: 0.22),
                BranchColor(red: 0.62, green: 0.40, blue: 0.18),
                BranchColor(red: 0.36, green: 0.26, blue: 0.16),
            ]),
            dark: dark(
                colors: [
                    BranchColor(red: 0.90, green: 0.68, blue: 0.48),
                    BranchColor(red: 0.86, green: 0.74, blue: 0.50),
                    BranchColor(red: 0.78, green: 0.70, blue: 0.58),
                    BranchColor(red: 0.94, green: 0.72, blue: 0.42),
                    BranchColor(red: 0.72, green: 0.60, blue: 0.46),
                ],
                center: BranchColor(red: 0.15, green: 0.12, blue: 0.09)
            )
        ),
        MapTheme(
            id: "bloom",
            nameKey: "花色",
            light: light(colors: [
                BranchColor(red: 0.72, green: 0.12, blue: 0.36),
                BranchColor(red: 0.78, green: 0.20, blue: 0.48),
                BranchColor(red: 0.64, green: 0.10, blue: 0.32),
                BranchColor(red: 0.70, green: 0.16, blue: 0.58),
                BranchColor(red: 0.82, green: 0.24, blue: 0.40),
            ]),
            dark: dark(
                colors: [
                    BranchColor(red: 0.98, green: 0.62, blue: 0.74),
                    BranchColor(red: 0.98, green: 0.70, blue: 0.84),
                    BranchColor(red: 0.96, green: 0.50, blue: 0.62),
                    BranchColor(red: 0.92, green: 0.62, blue: 0.96),
                    BranchColor(red: 0.98, green: 0.74, blue: 0.70),
                ],
                center: BranchColor(red: 0.16, green: 0.09, blue: 0.12)
            )
        ),
        MapTheme(
            id: "slate",
            nameKey: "岩色",
            light: light(colors: [
                BranchColor(red: 0.22, green: 0.28, blue: 0.36),
                BranchColor(red: 0.14, green: 0.38, blue: 0.40),
                BranchColor(red: 0.18, green: 0.28, blue: 0.58),
                BranchColor(red: 0.48, green: 0.18, blue: 0.24),
                BranchColor(red: 0.28, green: 0.36, blue: 0.16),
            ]),
            dark: dark(
                colors: [
                    BranchColor(red: 0.68, green: 0.76, blue: 0.86),
                    BranchColor(red: 0.42, green: 0.86, blue: 0.80),
                    BranchColor(red: 0.58, green: 0.74, blue: 0.98),
                    BranchColor(red: 0.96, green: 0.62, blue: 0.68),
                    BranchColor(red: 0.74, green: 0.88, blue: 0.46),
                ],
                center: BranchColor(red: 0.11, green: 0.12, blue: 0.15)
            )
        ),
    ]

    /// Nil, blank, and the standard id are omitted from JSON.
    /// Any other token is kept so a newer preset still round-trips.
    public static func persistedID(_ id: String?) -> String? {
        guard let id else { return nil }
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != standardID else { return nil }
        return trimmed
    }

    /// Light with no stored id returns `fallback`, which is `LayoutAppearance.standard`
    /// unless a caller built a custom engine. A stored id uses that preset.
    /// Dark with no stored id uses the standard preset's dark set.
    public static func appearance(
        themeID: String?,
        scheme: MapColorScheme,
        fallback: LayoutAppearance
    ) -> LayoutAppearance {
        let stored = persistedID(themeID)
        guard let stored, let theme = all.first(where: { $0.id == stored }) else {
            if scheme == .dark, let ink = all.first(where: { $0.id == standardID }) {
                return ink.dark
            }
            return fallback
        }
        return scheme == .dark ? theme.dark : theme.light
    }

    private static func light(colors: [BranchColor]) -> LayoutAppearance {
        var appearance = LayoutAppearance.standard
        appearance.palette = BranchPalette(colors: colors)
        return appearance
    }

    private static func dark(colors: [BranchColor], center: BranchColor) -> LayoutAppearance {
        var appearance = LayoutAppearance.standard
        appearance.palette = BranchPalette(colors: colors)
        appearance.centerFill = center
        appearance.centerBorder = BranchColor(
            red: min(1, center.red + 0.28),
            green: min(1, center.green + 0.28),
            blue: min(1, center.blue + 0.28)
        )
        appearance.centerText = BranchColor(red: 0.95, green: 0.95, blue: 0.96)
        appearance.level1Text = BranchColor(red: 0.09, green: 0.08, blue: 0.07)
        appearance.deeperText = BranchColor(red: 0.09, green: 0.08, blue: 0.07)
        appearance.deeperFillMix = 0.38
        return appearance
    }
}
