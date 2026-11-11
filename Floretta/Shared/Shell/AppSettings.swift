import CoreGraphics
import FlorettaCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

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

/// Width the home shell should follow. Compact is the iPhone (and a narrow iPad).
enum HomeWidthClass: Equatable, Sendable {
    case compact
    case regular
    case unspecified
}

/// Compact width shows the recent stack itself. A split view there shows the
/// sidebar, which is outside the `NavigationStack` that owns 「最近」.
enum HomeLibraryChrome: Equatable, Sendable {
    case stack
    case split
}

enum HomeLibrary {
    static let navigationTitle = "最近"

    /// Documents the UI-test launch writes into a temporary library, so the
    /// home list does not depend on anyone's personal files.
    static let smokeFixtureTitles = ["甲图", "乙图"]

    static func chrome(width: HomeWidthClass, phoneWhenUnspecified: Bool) -> HomeLibraryChrome {
        switch width {
        case .compact:
            return .stack
        case .regular:
            return .split
        case .unspecified:
            return phoneWhenUnspecified ? .stack : .split
        }
    }
}

/// iPad sidebar rows. There is no 「最近」 row: that button only assigned
/// `HomePage.recent`, which is already showing, so the tap changed nothing.
enum HomeSidebarRow: String, Hashable, Identifiable, Sendable {
    case newMap
    case openFiles
    case openICloud
    case browseLocal

    var id: String { rawValue }

    static let leading: [HomeSidebarRow] = [.newMap]
    static let local: [HomeSidebarRow] = [.openFiles, .openICloud, .browseLocal]
    static let all: [HomeSidebarRow] = leading + local

    /// Page this row selects. Creating a document or presenting the file panel
    /// does not change `HomePage`.
    var destinationPage: HomePage? {
        switch self {
        case .newMap, .openFiles:
            return nil
        case .openICloud, .browseLocal:
            return .browse
        }
    }

    var accessibilityIdentifier: String { "home.sidebar.\(rawValue)" }

    func title(device: LocalDeviceLabel) -> String {
        switch self {
        case .newMap: "新建导图"
        case .openFiles: "从文件应用打开"
        case .openICloud: "从iCloud云盘打开"
        case .browseLocal: device.title
        }
    }

    func systemImage(device: LocalDeviceLabel) -> String {
        switch self {
        case .newMap: "plus"
        case .openFiles: "folder"
        case .openICloud: "cloud"
        case .browseLocal: device.systemImage
        }
    }

    /// True when activating the row changes what the user sees from `page`.
    /// Selecting the page that is already current does not.
    static func hasVisibleEffect(_ row: HomeSidebarRow, from page: HomePage) -> Bool {
        switch row {
        case .newMap, .openFiles:
            return true
        case .openICloud, .browseLocal:
            return page != .browse
        }
    }

    static func selectingPageHasVisibleEffect(_ page: HomePage, from current: HomePage) -> Bool {
        page != current
    }
}

/// File types the open panel may offer: the four map formats, plus XML and
/// plain text so a file the panel labels as text can still be chosen.
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

    static let exportKinds = ["png", "pdf", "md", "opml", "mm", "floretta", "xmind", "textbundle"]

    /// Types the open panel may offer. Extension-backed types come first so the
    /// panel does not collapse every text file into Markdown. `.mm` is also
    /// Objective-C++ source on macOS; that system type is included so those
    /// files can be chosen. XML and plain text stay in the list because the
    /// panel often labels a FreeMind or OPML file as text. `DocumentOpener`
    /// still decides from the bytes.
    static var allowedContentTypes: [UTType] {
        var types: [UTType] = []
        func append(_ type: UTType?) {
            guard let type, !types.contains(type) else { return }
            types.append(type)
        }
        append(UTType(florettaIdentifier))
        append(UTType(filenameExtension: "floretta"))
        append(UTType(mmIdentifier))
        append(UTType(filenameExtension: "mm"))
        append(UTType(opmlIdentifier))
        append(UTType(filenameExtension: "opml"))
        append(UTType(markdownIdentifier))
        append(UTType(filenameExtension: "md"))
        append(UTType(filenameExtension: "markdown"))
        append(UTType(filenameExtension: "xmind"))
        append(.xml)
        append(.plainText)
        return types
    }

    /// Stable type for one share-menu export. Never an index into
    /// `allowedContentTypes`: that array also contains extension aliases, so
    /// index 2 is not OPML once `.mm` resolves to two types.
    static func contentType(forExport kind: String) -> UTType {
        switch kind {
        case "png":
            return .png
        case "pdf":
            return .pdf
        case "md":
            return UTType(markdownIdentifier)
                ?? UTType(filenameExtension: "md")
                ?? UTType(filenameExtension: "markdown")
                ?? .plainText
        case "opml":
            return UTType(opmlIdentifier)
                ?? UTType(filenameExtension: "opml")
                ?? .xml
        case "mm":
            return UTType(mmIdentifier)
                ?? UTType(filenameExtension: "mm")
                ?? .xml
        case "floretta":
            return UTType(florettaIdentifier)
                ?? UTType(filenameExtension: "floretta")
                ?? .data
        case "xmind":
            return UTType(filenameExtension: "xmind") ?? .data
        case "textbundle":
            #if os(macOS)
            return UTType(filenameExtension: "textbundle", conformingTo: .package) ?? .package
            #else
            return UTType(filenameExtension: "textpack", conformingTo: .archive) ?? .archive
            #endif
        default:
            return .data
        }
    }

    /// Every type `contentType(forExport:)` can return. `fileExporter` refuses
    /// a content type that is missing from the document's readable list.
    static var exportableContentTypes: [UTType] {
        var types: [UTType] = [.data]
        for kind in exportKinds {
            let type = contentType(forExport: kind)
            if !types.contains(type) {
                types.append(type)
            }
        }
        return types
    }
}

extension MapExportOptions {
    /// Export options the PNG writer should use. Reads the settings store.
    @MainActor
    init(settings: AppSettings) {
        self.init(
            scale: settings.pngScale.exportScale,
            background: settings.pngBackground.exportBackground,
            includeStickies: settings.exportIncludesStickies
        )
    }
}

extension MapExporter {
    @MainActor
    static func png(
        document: MindMapDocument,
        settings: AppSettings,
        images: [String: CGImage] = [:],
        scheme: MapColorScheme = .light
    ) -> MapExportResult {
        png(document: document, options: MapExportOptions(settings: settings), images: images, scheme: scheme)
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

    /// PNG and PDF. On unless the user turns it off. The cards stay in the document either way.
    var exportIncludesStickies: Bool {
        didSet { defaults.set(exportIncludesStickies, forKey: Key.exportIncludesStickies) }
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
        if defaults.object(forKey: Key.exportIncludesStickies) == nil {
            exportIncludesStickies = true
        } else {
            exportIncludesStickies = defaults.bool(forKey: Key.exportIncludesStickies)
        }
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
        static let exportIncludesStickies = "floretta.exportIncludesStickies"
    }
}
