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
    /// (family, design, size quantized to log-spaced ~2% buckets); a miss
    /// for a new bucket is a cheap copy of a template already built for
    /// that family and design. The expensive cascade walk runs only when
    /// the family or node design is new. A capacity cap and LRU keep
    /// back-and-forth pinch-zoom from growing the sized-font table
    /// without bound.
    ///
    /// The hot path must not take a lock per lookup. `beginFrame()` captures
    /// an immutable snapshot; draw then only reads that snapshot. A miss
    /// (pinch to a new ~2% size bucket) copies the template without holding
    /// the lock, then publishes a new snapshot.
    private struct FontCacheKey: Hashable {
        var familyID: String
        var nodeDesign: String
        var sizeTicks: Int
    }

    private struct FontTables {
        var fonts: [FontCacheKey: CTFont] = [:]
        var templates: [String: CTFont] = [:]
        var cascadeNames: [String: [String]] = [:]
    }

    private final class ResolvedFontCache: @unchecked Sendable {
        static let defaultCapacity = 256

        private let lock = NSLock()
        /// Published tables. Dictionaries are treated as immutable after publish.
        private var published = FontTables()
        /// Frame-local snapshot for lock-free hits. Updated by `beginFrame()`
        /// and again after a miss so later nodes in the same frame see the
        /// newly sized font without taking the lock.
        private var frame = FontTables()
        /// Oldest sized-font key at the front. Recency is updated on publish
        /// and once per frame in `prepareCanvasFonts`, never on the lock-free
        /// per-node hit path.
        private var lru: [FontCacheKey] = []
        private var capacity = defaultCapacity

        func beginFrame() {
            lock.lock()
            let snap = published
            lock.unlock()
            frame = snap
        }

        func font(for key: FontCacheKey) -> CTFont? {
            frame.fonts[key]
        }

        func template(for templateKey: String) -> CTFont? {
            frame.templates[templateKey]
        }

        func cascadeNames(for kind: String) -> [String]? {
            frame.cascadeNames[kind]
        }

        /// Locked read of the published tables, used when the frame snapshot
        /// missed but another thread may already have published the entry.
        func publishedFont(for key: FontCacheKey) -> CTFont? {
            lock.lock()
            let hit = published.fonts[key]
            let snap = published
            lock.unlock()
            if hit != nil { frame = snap }
            return hit
        }

        func publishedTemplate(for templateKey: String) -> CTFont? {
            lock.lock()
            let hit = published.templates[templateKey]
            lock.unlock()
            return hit
        }

        func publishFont(_ font: CTFont, key: FontCacheKey, template: CTFont? = nil, templateKey: String? = nil) {
            lock.lock()
            if published.fonts[key] == nil {
                published.fonts[key] = font
            }
            if let template, let templateKey, published.templates[templateKey] == nil {
                published.templates[templateKey] = template
            }
            moveToRecent(key)
            // Never evict the key just published. In-flight draws already
            // hold CTFont refs, so older buckets can leave the table.
            evictIfNeeded(protecting: [key])
            let snap = published
            lock.unlock()
            frame = snap
        }

        func publishCascadeNames(_ names: [String], for kind: String) {
            lock.lock()
            if published.cascadeNames[kind] == nil {
                published.cascadeNames[kind] = names
            }
            let snap = published
            lock.unlock()
            frame = snap
        }

        /// Promote keys used in this frame. One locked pass, not per node.
        func touchKeys(_ keys: Set<FontCacheKey>) {
            guard !keys.isEmpty else { return }
            lock.lock()
            for key in keys where published.fonts[key] != nil {
                moveToRecent(key)
            }
            lock.unlock()
        }

        func resetForTests() {
            lock.lock()
            published = FontTables()
            lru = []
            capacity = Self.defaultCapacity
            lock.unlock()
            frame = FontTables()
        }

        func setCapacityForTests(_ newCapacity: Int) {
            lock.lock()
            capacity = max(newCapacity, 1)
            evictIfNeeded()
            let snap = published
            lock.unlock()
            frame = snap
        }

        var fontCountForTests: Int {
            lock.lock()
            let count = published.fonts.count
            lock.unlock()
            return count
        }

        var capacityForTests: Int {
            lock.lock()
            let value = capacity
            lock.unlock()
            return value
        }

        /// Must be called while `lock` is held.
        private func moveToRecent(_ key: FontCacheKey) {
            if let idx = lru.firstIndex(of: key) {
                lru.remove(at: idx)
            }
            lru.append(key)
        }

        /// Must be called while `lock` is held.
        private func evictIfNeeded(protecting protected: Set<FontCacheKey> = []) {
            var index = 0
            while published.fonts.count > capacity, index < lru.count {
                let oldest = lru[index]
                if protected.contains(oldest) {
                    index += 1
                    continue
                }
                lru.remove(at: index)
                published.fonts.removeValue(forKey: oldest)
            }
        }
    }

    private static let resolvedFonts = ResolvedFontCache()

    /// Capture a lock-free snapshot for this display-link frame.
    static func beginFrame() {
        resolvedFonts.beginFrame()
    }

    /// Resolve typography for the unique (design, size) pairs in this frame
    /// so later per-node draws only read immutable CTFont references.
    static func prepareCanvasFonts(familyID: String, designsAndSizes: [(String, CGFloat)]) {
        var seen = Set<FontCacheKey>()
        for (design, size) in designsAndSizes {
            let key = FontCacheKey(familyID: familyID, nodeDesign: design, sizeTicks: sizeTicks(size))
            if seen.insert(key).inserted {
                _ = cachedCTFont(familyID: familyID, nodeDesign: design, size: size)
            }
        }
        resolvedFonts.touchKeys(seen)
    }

    /// Log-spaced size buckets, about 2% apart, before the size enters the
    /// cache key. A 1/64-pt key missed every pinch-zoom frame. Fixed 0.5pt
    /// buckets were 2.5% at 20pt and 12.5% at 4pt, a visible step on the
    /// shrink end. Adjacent log buckets differ by at most 2% at any size,
    /// so a pinch-zoom glyph jump stays ≤2%.
    private static let sizeTickRatio: CGFloat = 1.02
    private static let minPointSize: CGFloat = 1

    private static func sizeTicks(_ size: CGFloat) -> Int {
        let clamped = max(size, minPointSize)
        return Int((log(Double(clamped)) / log(Double(sizeTickRatio))).rounded())
    }

    private static func pointSize(fromTicks ticks: Int) -> CGFloat {
        CGFloat(pow(Double(sizeTickRatio), Double(max(ticks, 0))))
    }

    static func cascadePostScriptNames(kind: AppearanceFontKind) -> [String] {
        let cacheKey = kind.rawValue
        if let cached = resolvedFonts.cascadeNames(for: cacheKey) {
            return cached
        }

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
        resolvedFonts.publishCascadeNames(result, for: cacheKey)
        return result
    }

    static func ctFont(familyID: String, size: CGFloat) -> CTFont {
        cachedCTFont(familyID: familyID, nodeDesign: "default", size: size)
    }

    /// Returns a cached CTFont for the family, node design, and size.
    /// Rebuilds the cascade only when the family or design has not been seen.
    /// Hits read the frame snapshot with no lock. A new ~2% size bucket
    /// copies the template outside the lock, then publishes.
    static func cachedCTFont(familyID: String, nodeDesign: String, size: CGFloat) -> CTFont {
        let ticks = sizeTicks(size)
        let key = FontCacheKey(familyID: familyID, nodeDesign: nodeDesign, sizeTicks: ticks)
        let templateKey = "\(familyID)\u{1f}\(nodeDesign)"
        let point = pointSize(fromTicks: ticks)

        if let hit = resolvedFonts.font(for: key) {
            return hit
        }
        if let template = resolvedFonts.template(for: templateKey) {
            let sized = CTFontCreateCopyWithAttributes(template, point, nil, nil)
            resolvedFonts.publishFont(sized, key: key)
            return sized
        }
        if let hit = resolvedFonts.publishedFont(for: key) {
            return hit
        }
        if let template = resolvedFonts.publishedTemplate(for: templateKey) {
            let sized = CTFontCreateCopyWithAttributes(template, point, nil, nil)
            resolvedFonts.publishFont(sized, key: key)
            return sized
        }

        let built = makeCTFont(familyID: familyID, nodeDesign: nodeDesign, size: point)
        resolvedFonts.publishFont(built, key: key, template: built, templateKey: templateKey)
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


    /// Log-spaced ~2% bucket stored in the cache key, and used as the
    /// CTFont point size. Adjacent buckets jump by at most 2%.
    static func quantizedPointSize(_ size: CGFloat) -> CGFloat {
        pointSize(fromTicks: sizeTicks(size))
    }

    static func resetResolvedFontCacheForTests() {
        resolvedFonts.resetForTests()
    }

    static func resolvedFontCacheCountForTests() -> Int {
        resolvedFonts.fontCountForTests
    }

    static func resolvedFontCacheCapacityForTests() -> Int {
        resolvedFonts.capacityForTests
    }

    static func setResolvedFontCacheCapacityForTests(_ capacity: Int) {
        resolvedFonts.setCapacityForTests(capacity)
    }

    static func touchResolvedFontCacheForTests(familyID: String, nodeDesign: String, sizes: [CGFloat]) {
        let keys = Set(sizes.map {
            FontCacheKey(familyID: familyID, nodeDesign: nodeDesign, sizeTicks: sizeTicks($0))
        })
        resolvedFonts.touchKeys(keys)
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
