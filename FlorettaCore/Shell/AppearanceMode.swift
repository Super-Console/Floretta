import Foundation

/// One light or dark set of content colors. Values are `#RRGGBB`.
public struct AppearanceColorSet: Equatable, Codable, Sendable {
    public var canvasHex: String
    public var textHex: String
    public var secondaryTextHex: String
    public var nodeFillHex: String

    public init(canvasHex: String, textHex: String, secondaryTextHex: String, nodeFillHex: String) {
        self.canvasHex = canvasHex
        self.textHex = textHex
        self.secondaryTextHex = secondaryTextHex
        self.nodeFillHex = nodeFillHex
    }

    public var canvas: BranchColor { BranchColor(hex: canvasHex) ?? .white }
    public var text: BranchColor { BranchColor(hex: textHex) ?? .black }
    public var secondaryText: BranchColor { BranchColor(hex: secondaryTextHex) ?? .black }
    public var nodeFill: BranchColor { BranchColor(hex: nodeFillHex) ?? .white }
}

/// Editable content typography and color. There is one profile now: the
/// classic / modern / custom presets are gone, and no family is tied to a mode.
public struct AppearanceProfile: Equatable, Codable, Sendable {
    public var light: AppearanceColorSet
    public var dark: AppearanceColorSet
    /// Catalog id such as `system-sans` or `system-serif`.
    public var fontFamilyID: String
    public var fontSizeScale: Double
    public var lineHeight: Double
    public var cornerRadius: Double

    public init(
        light: AppearanceColorSet,
        dark: AppearanceColorSet,
        fontFamilyID: String,
        fontSizeScale: Double,
        lineHeight: Double,
        cornerRadius: Double
    ) {
        self.light = light
        self.dark = dark
        self.fontFamilyID = fontFamilyID
        self.fontSizeScale = fontSizeScale
        self.lineHeight = lineHeight
        self.cornerRadius = cornerRadius
    }

    public func colors(for scheme: MapColorScheme) -> AppearanceColorSet {
        scheme == .dark ? dark : light
    }

    /// Content font identity, resolved through the same catalog the inspector
    /// lists, so a serif is a family the user picked and nothing else.
    public var fontFamily: AppearanceFontFamily? {
        AppearanceCatalog.family(id: fontFamilyID)
    }

    public var fontIsSerif: Bool {
        fontFamily?.kind == .serif
    }
}

public enum AppearanceFontKind: String, Codable, Sendable {
    case serif
    case sans
}

/// A user-selectable family. The id is what persists.
public struct AppearanceFontFamily: Equatable, Sendable, Identifiable {
    public var id: String
    public var nameKey: String
    public var kind: AppearanceFontKind
    public var isSystem: Bool
    /// File name under `Floretta/Resources/Fonts/`, if this family is bundled.
    public var resourceFileName: String?
    /// Declared PostScript name of the bundled Regular face, if any.
    public var postScriptName: String?

    public init(
        id: String,
        nameKey: String,
        kind: AppearanceFontKind,
        isSystem: Bool,
        resourceFileName: String? = nil,
        postScriptName: String? = nil
    ) {
        self.id = id
        self.nameKey = nameKey
        self.kind = kind
        self.isSystem = isSystem
        self.resourceFileName = resourceFileName
        self.postScriptName = postScriptName
    }
}

public enum AppearanceCatalog {
    /// Content default. Sans, because a serif on 13–15pt chrome reads as a mismatch
    /// and the canvas default should not surprise anyone. Serif is one pick away.
    public static let defaultFontFamilyID = "system-sans"

    public static let families: [AppearanceFontFamily] = [
        AppearanceFontFamily(id: "system-serif", nameKey: "系统衬线", kind: .serif, isSystem: true),
        AppearanceFontFamily(id: "system-sans", nameKey: "跟随系统", kind: .sans, isSystem: true),
        AppearanceFontFamily(id: "eb-garamond", nameKey: "EB Garamond", kind: .serif, isSystem: false, resourceFileName: "EBGaramond-Regular.otf", postScriptName: "EBGaramond-Regular"),
        AppearanceFontFamily(id: "crimson-pro", nameKey: "Crimson Pro", kind: .serif, isSystem: false, resourceFileName: "CrimsonPro-Regular.otf", postScriptName: "CrimsonPro-Regular"),
        AppearanceFontFamily(id: "libre-baskerville", nameKey: "Libre Baskerville", kind: .serif, isSystem: false, resourceFileName: "LibreBaskerville-Regular.otf", postScriptName: "LibreBaskerville-Regular"),
        AppearanceFontFamily(id: "noto-serif", nameKey: "Noto Serif", kind: .serif, isSystem: false, resourceFileName: "NotoSerif-Regular.otf", postScriptName: "NotoSerif-Regular"),
        AppearanceFontFamily(id: "inter", nameKey: "Inter", kind: .sans, isSystem: false, resourceFileName: "Inter-Regular.otf", postScriptName: "Inter-Regular"),
        AppearanceFontFamily(id: "ibm-plex-sans", nameKey: "IBM Plex Sans", kind: .sans, isSystem: false, resourceFileName: "IBMPlexSans-Regular.otf", postScriptName: "IBMPlexSans"),
        AppearanceFontFamily(id: "noto-sans", nameKey: "Noto Sans", kind: .sans, isSystem: false, resourceFileName: "NotoSans-Regular.otf", postScriptName: "NotoSans-Regular"),
    ]

    public static func family(id: String) -> AppearanceFontFamily? {
        families.first { $0.id == id }
    }

    /// The one content profile. Its paper follows the home background so a new
    /// install looks like one decision, not two.
    public static func defaultProfile(homeBackground: HomeBackground = .default) -> AppearanceProfile {
        AppearanceProfile(
            light: AppearanceColorSet(
                canvasHex: homeBackground.pageHex(for: .light),
                textHex: "#3A2A22",
                secondaryTextHex: "#7A6A5A",
                nodeFillHex: "#FFFFFF"
            ),
            dark: AppearanceColorSet(
                canvasHex: homeBackground.pageHex(for: .dark),
                textHex: "#F7EFE1",
                secondaryTextHex: "#C4B4A4",
                nodeFillHex: "#262523"
            ),
            fontFamilyID: defaultFontFamilyID,
            fontSizeScale: 1,
            lineHeight: 1.25,
            cornerRadius: 12
        )
    }

    /// Decode one stored profile. Invalid or empty data falls back to the default.
    public static func profile(from data: Data?, fallback: HomeBackground = .default) -> AppearanceProfile {
        guard let data, !data.isEmpty,
              let decoded = try? JSONDecoder().decode(AppearanceProfile.self, from: data) else {
            return defaultProfile(homeBackground: fallback)
        }
        return decoded
    }

    public static func encodeProfile(_ profile: AppearanceProfile) throws -> Data {
        try JSONEncoder().encode(profile)
    }

    /// Legacy `[mode raw value: profile]` payload. Only the migration reads this;
    /// no view writes it any more.
    public static func legacyProfiles(from data: Data?) -> [String: AppearanceProfile] {
        guard let data, !data.isEmpty,
              let decoded = try? JSONDecoder().decode([String: AppearanceProfile].self, from: data) else {
            return [:]
        }
        return decoded
    }

    public static func encodeLegacyProfiles(_ profiles: [String: AppearanceProfile]) throws -> Data {
        try JSONEncoder().encode(profiles)
    }
}

extension AppearanceProfile {
    /// Overlays this profile's paper, node fill, ink, and corner radius on a map theme.
    /// Per-node stored colors in `LayoutEngine` still win over `uniformFill` / text defaults.
    public func applying(to appearance: LayoutAppearance, scheme: MapColorScheme) -> LayoutAppearance {
        var result = appearance
        let colors = colors(for: scheme)
        result.canvasBackground = colors.canvas
        result.uniformFill = colors.nodeFill
        result.centerText = colors.text
        result.level1Text = colors.text
        result.deeperText = colors.text
        result.cornerRadius = CGFloat(max(cornerRadius, 0))
        return result
    }

    public var clampedFontSizeScale: Double {
        min(max(fontSizeScale, 0.5), 2.0)
    }
}
