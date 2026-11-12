import Foundation

/// App-level appearance preset. This is not a lock: each mode stores its own
/// profile, and the user may change fonts or colors after picking a mode.
public enum AppearanceMode: String, CaseIterable, Codable, Sendable {
    case classic
    case modern
    case custom

    public var titleKey: String {
        switch self {
        case .classic: "经典模式"
        case .modern: "现代模式"
        case .custom: "自定义"
        }
    }
}

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

/// Editable content typography and color for one appearance mode.
public struct AppearanceProfile: Equatable, Codable, Sendable {
    public var light: AppearanceColorSet
    public var dark: AppearanceColorSet
    /// Catalog id such as `system-serif` or `system-sans`. A classic profile may store a sans id.
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
    public static let defaultMode: AppearanceMode = .classic

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

    public static func defaultProfile(for mode: AppearanceMode) -> AppearanceProfile {
        switch mode {
        case .classic, .custom:
            return AppearanceProfile(
                light: AppearanceColorSet(
                    canvasHex: "#F6F1E4",
                    textHex: "#3A2A22",
                    secondaryTextHex: "#7A6A5A",
                    nodeFillHex: "#F7EFE1"
                ),
                dark: AppearanceColorSet(
                    canvasHex: "#241C17",
                    textHex: "#F7EFE1",
                    secondaryTextHex: "#C4B4A4",
                    nodeFillHex: "#312820"
                ),
                fontFamilyID: "system-serif",
                fontSizeScale: 1,
                lineHeight: 1.25,
                cornerRadius: 12
            )
        case .modern:
            return AppearanceProfile(
                light: AppearanceColorSet(
                    canvasHex: "#FFFFFF",
                    textHex: "#000000",
                    secondaryTextHex: "#6B6B6B",
                    nodeFillHex: "#FFFFFF"
                ),
                dark: AppearanceColorSet(
                    canvasHex: "#000000",
                    textHex: "#FFFFFF",
                    secondaryTextHex: "#A0A0A0",
                    nodeFillHex: "#000000"
                ),
                fontFamilyID: "system-sans",
                fontSizeScale: 1,
                lineHeight: 1.2,
                cornerRadius: 8
            )
        }
    }

    /// Decode a `[mode raw value: profile]` payload. Missing or invalid data falls back to defaults.
    public static func profiles(from data: Data?) -> [AppearanceMode: AppearanceProfile] {
        var result: [AppearanceMode: AppearanceProfile] = [:]
        for mode in AppearanceMode.allCases {
            result[mode] = defaultProfile(for: mode)
        }
        guard let data, !data.isEmpty else { return result }
        guard let decoded = try? JSONDecoder().decode([String: AppearanceProfile].self, from: data) else {
            return result
        }
        for (raw, profile) in decoded {
            if let mode = AppearanceMode(rawValue: raw) {
                result[mode] = profile
            }
        }
        return result
    }

    public static func encodeProfiles(_ profiles: [AppearanceMode: AppearanceProfile]) throws -> Data {
        var raw: [String: AppearanceProfile] = [:]
        for (mode, profile) in profiles {
            raw[mode.rawValue] = profile
        }
        return try JSONEncoder().encode(raw)
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
