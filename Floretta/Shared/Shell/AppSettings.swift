import Foundation
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

enum AppLanguage: String, CaseIterable, Equatable, Sendable {
    case system
    case simplifiedChinese
    case english
}

enum AppAppearance: String, CaseIterable, Equatable, Sendable {
    case system
    case light
    case dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Map shows the whole tree. Focus shows one subtree.
enum DocumentViewMode: String, CaseIterable, Equatable, Sendable {
    case map
    case focus
}

enum PNGScalePreference: String, CaseIterable, Equatable, Sendable {
    case one
    case two
    case three

    var exportScale: MapExportScale {
        switch self {
        case .one: return .one
        case .two: return .two
        case .three: return .three
        }
    }
}

enum PNGBackgroundPreference: String, CaseIterable, Equatable, Sendable {
    case white
    case transparent

    var exportBackground: MapExportBackground {
        switch self {
        case .white: return .white
        case .transparent: return .transparent
        }
    }
}

enum ShellTab: Hashable, Equatable, Sendable {
    case home
    case settings

    var title: String {
        switch self {
        case .home: "首页"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .settings: "gearshape"
        }
    }

    /// iPhone, iPad, and Mac share these two destinations. iOS draws them in the
    /// system tab bar. Mac lists them in the sidebar.
    static let destinations: [ShellTab] = [.home, .settings]

    /// Visible settings entry is the sidebar row (wide) or the Settings tab (narrow).
    /// The home toolbar must not add a second gear. ⌘, is a shortcut, not another row.
    static let homeOverflowTitles: [String] = []

    static var preferredColumnVisibility: NavigationSplitViewVisibility {
        #if os(macOS)
        .all
        #else
        .detailOnly
        #endif
    }
}

/// File types the library importer is allowed to offer. Nothing else.
enum FlorettaFileTypes {
    static let florettaIdentifier = "net.timhuang.floretta.document"
    static let mmIdentifier = "org.freemind.mm"
    static let opmlIdentifier = "org.opml.opml"
    static let markdownIdentifier = "net.daringfireball.markdown"

    static let allowedIdentifiers = [
        florettaIdentifier,
        mmIdentifier,
        opmlIdentifier,
        markdownIdentifier,
    ]

    static let allowedExtensions = ["floretta", "mm", "opml", "md"]

    static var allowedContentTypes: [UTType] {
        [
            UTType(exportedAs: florettaIdentifier, conformingTo: .data),
            UTType(importedAs: mmIdentifier, conformingTo: .xml),
            UTType(importedAs: opmlIdentifier, conformingTo: .xml),
            UTType(importedAs: markdownIdentifier, conformingTo: .plainText),
        ]
    }
}

extension MapExportOptions {
    /// Export options the PNG writer should use. Reads the settings store.
    @MainActor
    init(settings: AppSettings) {
        self.init(
            scale: settings.pngScale.exportScale,
            background: settings.pngBackground.exportBackground
        )
    }
}

extension MapExporter {
    @MainActor
    static func png(document: MindMapDocument, settings: AppSettings) -> MapExportResult {
        png(document: document, options: MapExportOptions(settings: settings))
    }
}

enum AppInfo {
    static func versionText(short: String?, build: String?) -> String {
        let version = (short?.isEmpty == false) ? short! : "1.0"
        if let build, !build.isEmpty {
            return "\(version) (\(build))"
        }
        return version
    }

    static var version: String {
        let bundle = Bundle.main
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return versionText(short: short, build: build)
    }

    static func noticeText(in bundle: Bundle) -> String {
        if let url = bundle.url(forResource: "NOTICE", withExtension: nil),
           let text = try? String(contentsOf: url, encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        return fallbackNotice
    }

    static var notice: String { noticeText(in: .main) }

    static let fallbackNotice = """
    Floretta
    Copyright (c) 2026 Super-Console

    This product includes third-party software. The full text ships as NOTICE.

    SwiftFlow 0.3.1 — MIT. Copyright (c) 2026 A.Aurelions.
    https://github.com/aaurelions/SwiftFlow
    """
}

/// UserDefaults-backed preferences. Views write these; export, appearance, and new documents read them.
@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Key.language) }
    }

    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    var defaultView: DocumentViewMode {
        didSet { defaults.set(defaultView.rawValue, forKey: Key.defaultView) }
    }

    var pngScale: PNGScalePreference {
        didSet { defaults.set(pngScale.rawValue, forKey: Key.pngScale) }
    }

    var pngBackground: PNGBackgroundPreference {
        didSet { defaults.set(pngBackground.rawValue, forKey: Key.pngBackground) }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        language = AppLanguage(rawValue: defaults.string(forKey: Key.language) ?? "") ?? .system
        appearance = AppAppearance(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        if let raw = defaults.string(forKey: Key.defaultView),
           let mode = DocumentViewMode(rawValue: raw) {
            defaultView = mode
        } else {
            defaultView = Self.platformDefaultView
        }
        pngScale = PNGScalePreference(rawValue: defaults.string(forKey: Key.pngScale) ?? "") ?? .two
        pngBackground = PNGBackgroundPreference(rawValue: defaults.string(forKey: Key.pngBackground) ?? "") ?? .white
    }

    static let shared = AppSettings(defaults: .standard)

    var resolvedLocale: Locale {
        switch language {
        case .system:
            return .autoupdatingCurrent
        case .simplifiedChinese:
            return Locale(identifier: "zh-Hans")
        case .english:
            return Locale(identifier: "en")
        }
    }

    static var platformDefaultView: DocumentViewMode {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone ? .focus : .map
        #else
        return .map
        #endif
    }

    private enum Key {
        static let language = "floretta.language"
        static let appearance = "floretta.appearance"
        static let defaultView = "floretta.defaultView"
        static let pngScale = "floretta.pngScale"
        static let pngBackground = "floretta.pngBackground"
    }
}
