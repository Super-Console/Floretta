import CoreText
import FlorettaCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

private enum AppearanceProfileKey: EnvironmentKey {
    static let defaultValue = AppearanceCatalog.defaultProfile(for: .classic)
}

extension EnvironmentValues {
    var appearanceProfile: AppearanceProfile {
        get { self[AppearanceProfileKey.self] }
        set { self[AppearanceProfileKey.self] = newValue }
    }
}

/// Registers bundled OFL faces and builds a zh/en/ja/ko cascade.
/// Core stays Foundation-only; CoreText lives here.
enum ThemeFontCascade {
    /// Process-wide registration, done once. `static let` is the Swift 6-safe once token.
    private static let registration: Bool = {
        for url in bundledFontURLs() {
            var error: Unmanaged<CFError>?
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            if let error {
                _ = error.takeRetainedValue()
            }
        }
        return true
    }()

    static let chineseSerifNames = ["STSongti-SC-Regular", "STSong", "STSongti-TC-Regular"]
    static let japaneseSerifNames = ["Hiragino Mincho ProN", "HiraMinProN-W3"]
    static let koreanSerifNames = ["AppleMyungjo"]
    static let chineseSansNames = ["PingFangSC-Regular", "PingFang SC"]
    static let japaneseSansNames = ["HiraginoSans-W3", "Hiragino Sans"]
    static let koreanSansNames = ["AppleSDGothicNeo-Regular", "Apple SD Gothic Neo"]

    static func registerBundledFonts() {
        _ = registration
    }

    static func bundledFontURLs() -> [URL] {
        var urls: [URL] = []
        var seen = Set<URL>()
        let names = AppearanceCatalog.families.compactMap(\.resourceFileName)
        for bundle in bundlesToSearch() {
            for name in names {
                let stem = (name as NSString).deletingPathExtension
                let ext = (name as NSString).pathExtension
                let found = bundle.url(forResource: stem, withExtension: ext, subdirectory: "Fonts")
                    ?? bundle.url(forResource: stem, withExtension: ext)
                if let found, seen.insert(found).inserted {
                    urls.append(found)
                }
            }
        }
        return urls
    }

    private static func bundlesToSearch() -> [Bundle] {
        let bundles = [Bundle.main, Bundle(for: BundleToken.self)]
        var seen = Set<ObjectIdentifier>()
        return bundles.filter { seen.insert(ObjectIdentifier($0)).inserted }
    }

    private final class BundleToken {}

    /// Returns the first name that really resolves, not a Helvetica/Times fallback.
    static func firstAvailable(_ names: [String]) -> String? {
        let available = Set((CTFontManagerCopyAvailablePostScriptNames() as? [String]) ?? [])
        for name in names {
            if available.contains(name) { return name }
            let font = CTFontCreateWithName(name as CFString, 16, nil)
            let ps = CTFontCopyPostScriptName(font) as String
            let family = CTFontCopyFamilyName(font) as String
            if ps == name || family == name {
                return ps
            }
        }
        return nil
    }

    /// Resolved CTFont cache. Building a cascade list is too expensive to do
    /// for every visible node on every CADisplayLink frame. Keyed by
    /// (family, design, size); a miss for a new size is a cheap copy of a
    /// template already built for that family and design. The expensive
    /// cascade walk runs only when the family or node design is new.
    private struct FontCacheKey: Hashable {
        var familyID: String
        var nodeDesign: String
        var sizeTicks: Int
    }

    private final class ResolvedFontCache: @unchecked Sendable {
        let lock = NSLock()
        var fonts: [FontCacheKey: CTFont] = [:]
        var templates: [String: CTFont] = [:]
        var cascadeNames: [String: [String]] = [:]
    }

    private static let resolvedFonts = ResolvedFontCache()

    private static func sizeTicks(_ size: CGFloat) -> Int {
        Int((max(size, 1) * 64).rounded())
    }

    private static func pointSize(fromTicks ticks: Int) -> CGFloat {
        CGFloat(ticks) / 64
    }

    static func cascadePostScriptNames(kind: AppearanceFontKind) -> [String] {
        let cacheKey = kind.rawValue
        resolvedFonts.lock.lock()
        if let cached = resolvedFonts.cascadeNames[cacheKey] {
            resolvedFonts.lock.unlock()
            return cached
        }
        resolvedFonts.lock.unlock()

        let groups: [[String]]
        switch kind {
        case .serif:
            groups = [chineseSerifNames, japaneseSerifNames, koreanSerifNames]
        case .sans:
            groups = [chineseSansNames, japaneseSansNames, koreanSansNames]
        }
        var result: [String] = []
        var seen = Set<String>()
        for group in groups {
            if let name = firstAvailable(group), seen.insert(name).inserted {
                result.append(name)
            }
        }
        resolvedFonts.lock.lock()
        resolvedFonts.cascadeNames[cacheKey] = result
        resolvedFonts.lock.unlock()
        return result
    }

    static func ctFont(familyID: String, size: CGFloat) -> CTFont {
        cachedCTFont(familyID: familyID, nodeDesign: "default", size: size)
    }

    /// Returns a cached CTFont for the family, node design, and size.
    /// Rebuilds the cascade only when the family or design has not been seen.
    static func cachedCTFont(familyID: String, nodeDesign: String, size: CGFloat) -> CTFont {
        let ticks = sizeTicks(size)
        let key = FontCacheKey(familyID: familyID, nodeDesign: nodeDesign, sizeTicks: ticks)
        let templateKey = "\(familyID)\u{1f}\(nodeDesign)"

        resolvedFonts.lock.lock()
        if let hit = resolvedFonts.fonts[key] {
            resolvedFonts.lock.unlock()
            return hit
        }
        if let template = resolvedFonts.templates[templateKey] {
            let sized = CTFontCreateCopyWithAttributes(template, pointSize(fromTicks: ticks), nil, nil)
            resolvedFonts.fonts[key] = sized
            resolvedFonts.lock.unlock()
            return sized
        }
        resolvedFonts.lock.unlock()

        let built = makeCTFont(familyID: familyID, nodeDesign: nodeDesign, size: pointSize(fromTicks: ticks))

        resolvedFonts.lock.lock()
        if resolvedFonts.templates[templateKey] == nil {
            resolvedFonts.templates[templateKey] = built
        }
        resolvedFonts.fonts[key] = built
        resolvedFonts.lock.unlock()
        return built
    }

    private static func makeCTFont(familyID: String, nodeDesign: String, size: CGFloat) -> CTFont {
        switch nodeDesign {
        case "rounded":
            #if os(macOS)
            let base = NSFont.systemFont(ofSize: size)
            if let descriptor = base.fontDescriptor.withDesign(.rounded),
               let font = NSFont(descriptor: descriptor, size: size) {
                return font as CTFont
            }
            return base as CTFont
            #else
            let base = UIFont.systemFont(ofSize: size)
            if let descriptor = base.fontDescriptor.withDesign(.rounded) {
                return UIFont(descriptor: descriptor, size: size) as CTFont
            }
            return base as CTFont
            #endif
        case "monospaced":
            #if os(macOS)
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular) as CTFont
            #else
            return UIFont.monospacedSystemFont(ofSize: size, weight: .regular) as CTFont
            #endif
        default:
            registerBundledFonts()
            let family = AppearanceCatalog.family(id: familyID)
                ?? AppearanceCatalog.family(id: "system-serif")!
            let base = latinPrimary(for: family, size: size)
            // On iOS, the native New York UI font falls back to PingFang /
            // Apple SD Gothic for CJK — that would make Classic Chinese look
            // gothic. Keep the explicit Songti / Mincho / Myungjo cascade on
            // serif families. system-sans keeps the raw UI font so English is
            // SF and CJK stays gothic (PingFang / Apple SD Gothic).
            if family.id == "system-sans" {
                return base
            }
            return applyingCascade(base, kind: family.kind)
        }
    }

    static func swiftFont(familyID: String, nodeDesign: String, size: CGFloat) -> Font {
        let point = max(size, 1)
        switch nodeDesign {
        case "rounded":
            return .system(size: point, design: .rounded)
        case "monospaced":
            return .system(size: point, design: .monospaced)
        default:
            // Both default and serif follow the selected family, so Classic
            // can be switched to a sans face and the map text actually changes.
            // Use Font.system(design:) for the two system families so SwiftUI
            // Canvas sees a different Font identity than the previous mode.
            let family = AppearanceCatalog.family(id: familyID)
                ?? AppearanceCatalog.family(id: "system-serif")!
            if family.id == "system-sans" {
                return .system(size: point, design: .default)
            }
            if family.id == "system-serif" {
                return .system(size: point, design: .serif)
            }
            return font(from: ctFont(familyID: familyID, size: point))
        }
    }

    static func postScriptName(familyID: String) -> String {
        CTFontCopyPostScriptName(ctFont(familyID: familyID, size: 16)) as String
    }

    /// PostScript name of the typographic run used for `string`.
    static func postScriptName(familyID: String, for string: String) -> String {
        let font = ctFont(familyID: familyID, size: 24)
        let attr = NSAttributedString(
            string: string,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
        )
        let line = CTLineCreateWithAttributedString(attr)
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun], let run = runs.first else {
            return CTFontCopyPostScriptName(font) as String
        }
        let raw = CTRunGetAttributes(run) as NSDictionary
        if let fontObj = raw[kCTFontAttributeName] {
            let runFont: CTFont = fontObj as! CTFont
            return CTFontCopyPostScriptName(runFont) as String
        }
        return CTFontCopyPostScriptName(font) as String
    }

    private static func latinPrimary(for family: AppearanceFontFamily, size: CGFloat) -> CTFont {
        if family.id == "system-sans" {
            if let system = CTFontCreateUIFontForLanguage(.system, size, nil) {
                return system
            }
            return CTFontCreateWithName(".AppleSystemUIFont" as CFString, size, nil)
        }
        if family.id == "system-serif" {
            if let newYork = systemSerif(size: size) {
                return newYork
            }
            if let georgia = namedFont("Georgia", size: size) {
                return georgia
            }
            return CTFontCreateWithName("Georgia" as CFString, size, nil)
        }
        if let ps = family.postScriptName {
            let font = CTFontCreateWithName(ps as CFString, size, nil)
            if (CTFontCopyPostScriptName(font) as String) == ps {
                return font
            }
        }
        return CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    private static func applyingCascade(_ font: CTFont, kind: AppearanceFontKind) -> CTFont {
        let names = cascadePostScriptNames(kind: kind)
        guard !names.isEmpty else { return font }
        let fallbacks = names.map { CTFontDescriptorCreateWithNameAndSize($0 as CFString, CTFontGetSize(font)) }
        let attributes = CTFontDescriptorCreateWithAttributes(
            [kCTFontCascadeListAttribute: fallbacks] as CFDictionary
        )
        // Copy the live font rather than recreating it from a descriptor, so
        // the Latin primary face (Inter, EB Garamond, …) is preserved.
        return CTFontCreateCopyWithAttributes(font, CTFontGetSize(font), nil, attributes)
    }

    private static func systemSerif(size: CGFloat) -> CTFont? {
        #if os(macOS)
        let base = NSFont.systemFont(ofSize: size)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return nil }
        return NSFont(descriptor: descriptor, size: size).map { $0 as CTFont }
        #else
        let base = UIFont.systemFont(ofSize: size)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return nil }
        return UIFont(descriptor: descriptor, size: size) as CTFont
        #endif
    }

    private static func namedFont(_ name: String, size: CGFloat) -> CTFont? {
        #if os(macOS)
        return NSFont(name: name, size: size).map { $0 as CTFont }
        #else
        return UIFont(name: name, size: size).map { $0 as CTFont }
        #endif
    }


    #if os(macOS)
    static func platformFont(familyID: String, nodeDesign: String, size: CGFloat) -> NSFont {
        cachedCTFont(familyID: familyID, nodeDesign: nodeDesign, size: size) as NSFont
    }
    #else
    static func platformFont(familyID: String, nodeDesign: String, size: CGFloat) -> UIFont {
        cachedCTFont(familyID: familyID, nodeDesign: nodeDesign, size: size) as UIFont
    }
    #endif

    private static func font(from ctFont: CTFont) -> Font {
        #if os(macOS)
        Font(ctFont as NSFont)
        #else
        Font(ctFont as UIFont)
        #endif
    }
}
