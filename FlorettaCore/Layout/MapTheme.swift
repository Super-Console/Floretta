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
    /// A color-scheme id resolves to that scheme in both appearances. The scheme
    /// already carries branch colors, canvas paper, and line thickness on `LayoutAppearance`.
    public static func appearance(
        themeID: String?,
        scheme: MapColorScheme,
        fallback: LayoutAppearance
    ) -> LayoutAppearance {
        let stored = persistedID(themeID)
        if let stored, let preset = MapColorPresetCatalog.preset(id: stored) {
            return preset.appearance
        }
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

/// One named color scheme. Applying it stores `id` in `MindMapDocument.themeID`.
/// Layout then reads `appearance`, the same record a branch theme already uses:
/// palette for branch colors, `canvasBackground` for the paper, `linkStroke` for thickness.
/// Topics that already store `fillHex` or `borderWidth` keep those.
public struct MapColorPreset: Equatable, Sendable, Identifiable {
    public var id: String
    public var nameKey: String
    public var branchColors: [BranchColor]
    public var canvasBackground: BranchColor
    public var lineWidth: CGFloat
    public var appearance: LayoutAppearance

    public init(
        id: String,
        nameKey: String,
        branchColors: [BranchColor],
        canvasBackground: BranchColor,
        lineWidth: CGFloat,
        level1Text: BranchColor = .white,
        deeperText: BranchColor = .black,
        centerFill: BranchColor = .white,
        centerText: BranchColor = .black,
        centerBorder: BranchColor = .black,
        deeperFillMix: Double = 0.82
    ) {
        self.id = id
        self.nameKey = nameKey
        self.branchColors = branchColors
        self.canvasBackground = canvasBackground
        self.lineWidth = lineWidth
        var appearance = LayoutAppearance.standard
        appearance.palette = BranchPalette(colors: branchColors)
        appearance.canvasBackground = canvasBackground
        appearance.linkStroke = lineWidth
        appearance.level1Text = level1Text
        appearance.deeperText = deeperText
        appearance.centerFill = centerFill
        appearance.centerText = centerText
        appearance.centerBorder = centerBorder
        appearance.deeperFillMix = deeperFillMix
        self.appearance = appearance
    }
}

/// Six built-in schemes. They are not part of the eight branch themes.
/// Both lists resolve through `MapThemeCatalog.appearance`.
public enum MapColorPresetCatalog {
    public static let all: [MapColorPreset] = [
        MapColorPreset(
            id: "dawn",
            nameKey: "晨曦",
            branchColors: [
                color(176, 78, 58),
                color(168, 104, 28),
                color(146, 72, 64),
                color(184, 112, 48),
                color(120, 86, 52),
            ],
            canvasBackground: color(255, 247, 237),
            lineWidth: 2.25
        ),
        MapColorPreset(
            id: "mist",
            nameKey: "极简灰",
            branchColors: [
                color(28, 28, 30),
                color(58, 58, 62),
                color(88, 88, 92),
                color(44, 48, 52),
                color(72, 76, 80),
            ],
            canvasBackground: color(245, 245, 245),
            lineWidth: 1
        ),
        MapColorPreset(
            id: "salt",
            nameKey: "海盐",
            branchColors: [
                color(20, 92, 112),
                color(16, 116, 122),
                color(28, 78, 130),
                color(36, 108, 108),
                color(14, 84, 96),
            ],
            canvasBackground: color(236, 244, 246),
            lineWidth: 1.75
        ),
        MapColorPreset(
            id: "citrus",
            nameKey: "橘叶",
            branchColors: [
                color(196, 78, 12),
                color(168, 96, 16),
                color(32, 110, 64),
                color(176, 64, 28),
                color(46, 122, 78),
            ],
            canvasBackground: color(255, 244, 232),
            lineWidth: 3
        ),
        MapColorPreset(
            id: "night",
            nameKey: "夜紫",
            branchColors: [
                color(206, 176, 255),
                color(240, 176, 224),
                color(176, 168, 255),
                color(232, 196, 255),
                color(196, 160, 240),
            ],
            canvasBackground: color(28, 22, 42),
            lineWidth: 1.5,
            level1Text: color(22, 16, 32),
            deeperText: color(22, 16, 32),
            centerFill: color(46, 36, 68),
            centerText: color(244, 238, 255),
            centerBorder: color(118, 96, 156),
            deeperFillMix: 0.22
        ),
        MapColorPreset(
            id: "forest",
            nameKey: "森林",
            branchColors: [
                color(22, 84, 48),
                color(46, 110, 62),
                color(28, 78, 56),
                color(64, 96, 40),
                color(18, 72, 58),
            ],
            canvasBackground: color(236, 242, 234),
            lineWidth: 2
        ),
    ]

    public static func preset(id: String) -> MapColorPreset? {
        all.first { $0.id == id }
    }

    private static func color(_ red: Int, _ green: Int, _ blue: Int) -> BranchColor {
        BranchColor(
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255
        )
    }
}
