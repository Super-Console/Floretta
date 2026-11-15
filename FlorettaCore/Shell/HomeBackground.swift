import Foundation

/// What the home page sits on. The preference stores this semantic choice, not
/// an RGB value, so the same choice resolves to a different concrete color in
/// light and in dark. That keeps the setting meaningful when the system turns
/// dark instead of dropping a bright sheet into a dark room.
public enum HomeBackground: String, CaseIterable, Codable, Sendable {
    /// 纸质米白. Warm paper in light, a warm near-black in dark.
    case paper
    /// 纯白. White sheet in light, a neutral near-black in dark.
    case white

    public static let `default`: HomeBackground = .paper

    public var titleKey: String {
        switch self {
        case .paper: "纸质米白"
        case .white: "纯白"
        }
    }

    /// Concrete page color for one scheme. Only this function knows the hexes;
    /// every caller asks for a scheme.
    public func pageHex(for scheme: MapColorScheme) -> String {
        switch (self, scheme) {
        case (.paper, .light): "#FBF7F0"
        case (.paper, .dark): "#1B1917"
        case (.white, .light): "#FFFFFF"
        case (.white, .dark): "#121212"
        }
    }

    public func page(on scheme: MapColorScheme) -> BranchColor {
        BranchColor(hex: pageHex(for: scheme)) ?? .white
    }

    /// Page, raised card surface, and the two inks the home page draws with.
    public func palette(for scheme: MapColorScheme) -> HomePalette {
        HomePalette.forBackground(self, scheme: scheme)
    }
}

/// The home page's colors for one scheme. Cards are raised by lightness, not by
/// a border: an outline in a dark page reads as dirt, not as a card edge.
public struct HomePalette: Equatable, Sendable {
    public var pageHex: String
    public var cardHex: String
    public var inkHex: String
    public var secondaryInkHex: String

    public init(pageHex: String, cardHex: String, inkHex: String, secondaryInkHex: String) {
        self.pageHex = pageHex
        self.cardHex = cardHex
        self.inkHex = inkHex
        self.secondaryInkHex = secondaryInkHex
    }

    /// How far a card sits above the page in dark. Between 4% and 6% by design.
    public static let cardElevation = 0.05

    public static func forBackground(_ background: HomeBackground, scheme: MapColorScheme) -> HomePalette {
        let page = background.pageHex(for: scheme)
        switch scheme {
        case .light:
            return HomePalette(
                pageHex: page,
                cardHex: "#FFFFFF",
                inkHex: "#1F1C18",
                secondaryInkHex: "#5F574E"
            )
        case .dark:
            let raised = (BranchColor(hex: page) ?? .black).lightened(by: cardElevation)
            return HomePalette(
                pageHex: page,
                cardHex: ColorContrast.hex(raised),
                inkHex: "#F2EEE7",
                secondaryInkHex: "#A8A29A"
            )
        }
    }

    public var page: BranchColor { BranchColor(hex: pageHex) ?? .white }
    public var card: BranchColor { BranchColor(hex: cardHex) ?? .white }
    public var ink: BranchColor { BranchColor(hex: inkHex) ?? .black }
    public var secondaryInk: BranchColor { BranchColor(hex: secondaryInkHex) ?? .black }
}

extension HomeBackground {
    /// Stored document paper, canonicalised to `#RRGGBB`, or nil when the raw
    /// value is missing or unreadable. Old files therefore stay "no paper".
    public static func canonicalHex(_ raw: String?) -> String? {
        guard let raw, let color = BranchColor(hex: raw) else { return nil }
        return ColorContrast.hex(color)
    }
}

extension MindMapDocument {
    /// The paper this document draws on. Its own stored color wins; a file with
    /// no stored color keeps whatever the app appearance resolved to.
    public func resolvedCanvasBackground(fallback: BranchColor?) -> BranchColor? {
        if let canvasBackgroundHex, let stored = BranchColor(hex: canvasBackgroundHex) {
            return stored
        }
        return fallback
    }
}

/// WCAG relative luminance and contrast. Pure math on `#RRGGBB`, so a test can
/// assert the palettes without a screenshot or a renderer.
public enum ColorContrast {
    /// `nil` when the string is not `#RRGGBB`.
    public static func relativeLuminance(hex: String) -> Double? {
        guard let color = BranchColor(hex: hex) else { return nil }
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
    }

    /// Contrast ratio in 1...21. `nil` when either color is malformed.
    public static func ratio(hex a: String, hex b: String) -> Double? {
        guard let first = relativeLuminance(hex: a), let second = relativeLuminance(hex: b) else { return nil }
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// `#RRGGBB` for a color already in the 0...1 range.
    public static func hex(_ color: BranchColor) -> String {
        func channel(_ value: Double) -> Int {
            Int((min(max(value, 0), 1) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", channel(color.red), channel(color.green), channel(color.blue))
    }

    /// Body text on the page must clear this. WCAG AA for normal text.
    public static let bodyMinimum: Double = 4.5
}
