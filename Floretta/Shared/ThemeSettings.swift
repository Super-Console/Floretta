import FlorettaCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The single persisted source of truth for the app-wide theme selection.
/// `@AppStorage` uses the same key wherever this dynamic property is installed.
struct ThemeSettings: DynamicProperty {
    @AppStorage("floretta.theme.mode") private var storedMode = ThemeMode.default.rawValue
    @AppStorage("floretta.theme.serifOverride") private var storedSerifOverride: Bool = true

    var mode: ThemeMode {
        get { ThemeMode(rawValue: storedMode) ?? .default }
        nonmutating set { storedMode = newValue.rawValue }
    }

    var serifOverride: Bool? {
        get { mode == .custom ? storedSerifOverride : nil }
        nonmutating set { storedSerifOverride = newValue ?? ThemeFontResolver.spec(for: mode, script: .latin).isSerif }
    }
}

struct ThemeTypographyModifier: ViewModifier {
    var language: AppLanguage = .system
    @Environment(\.locale) private var locale
    @AppStorage("floretta.theme.mode") private var storedMode = ThemeMode.default.rawValue
    @AppStorage("floretta.theme.serifOverride") private var storedSerifOverride = true
    @AppStorage("floretta.language") private var storedLanguage = AppLanguage.system.rawValue

    func body(content: Content) -> some View {
        let mode = ThemeMode(rawValue: storedMode) ?? .default
        let selectedLanguage = language == .system
            ? (AppLanguage(rawValue: storedLanguage) ?? .system)
            : language
        let script: ThemeScript = usesChinese(language: selectedLanguage, locale: locale) ? .cjk : .latin
        let override = mode == .custom ? storedSerifOverride : nil
        let spec = ThemeFontResolver.spec(for: mode, script: script, serifOverride: override)
        let name = spec.familyCandidates.first(where: isFontAvailable)
        if let name {
            content.font(.custom(name, size: 17, relativeTo: .body))
        } else {
            content
        }
    }

    private func usesChinese(language: AppLanguage, locale: Locale) -> Bool {
        switch language {
        case .simplifiedChinese: true
        case .english: false
        case .system: locale.language.languageCode?.identifier == "zh"
        }
    }

    private func isFontAvailable(_ name: String) -> Bool {
        #if os(macOS)
        NSFont(name: name, size: 17) != nil
        #else
        UIFont(name: name, size: 17) != nil
        #endif
    }
}

extension View {
    func themeTypography(language: AppLanguage = .system) -> some View {
        modifier(ThemeTypographyModifier(language: language))
    }
}

/// How large the system face runs on a chrome surface.
enum ChromeTextRole {
    /// Toolbars, sidebars, forms, menus, inspector labels: the platform's own
    /// interface text (`body`), 13 pt on macOS and 17 pt on iOS.
    case body
    /// Chrome that rides a capsule or a status strip, where the system's own
    /// compact size (`callout`) is what the bar was drawn for.
    case compact

    var font: Font {
        switch self {
        case .body: .body
        case .compact: .callout
        }
    }
}

/// Chrome typography. Toolbars, the status capsule, sidebars, settings and
/// inspector forms, menus, empty states and notices never take the theme
/// family: they stay on the platform's own sans — SF for Latin, PingFang for
/// Chinese — which is the split Apple draws in Books, Pages and Notes (serif
/// body, system chrome). Only content may be serif.
///
/// Deliberately no `ThemeFontResolver` call lives here. `themeTypography` stays
/// for canvas nodes and Markdown body; see `docs/THEME-MODES.md`.
struct ChromeTypographyModifier: ViewModifier {
    /// Mirrors `themeTypography(language:)` so a call site reads the same either
    /// way. The system face already carries both scripts at one optical size, so
    /// no per-script size adjustment is needed.
    var language: AppLanguage = .system
    var role: ChromeTextRole = .body

    func body(content: Content) -> some View {
        content.font(role.font)
    }
}

extension View {
    /// Chrome-only typography: always the system face, never the theme family.
    func chromeTypography(language: AppLanguage = .system, role: ChromeTextRole = .body) -> some View {
        modifier(ChromeTypographyModifier(language: language, role: role))
    }
}

enum ThemeTypography {
    static func font(mode: ThemeMode, language: AppLanguage, locale: Locale = .current, size: CGFloat) -> Font? {
        let isChinese: Bool
        switch language {
        case .simplifiedChinese: isChinese = true
        case .english: isChinese = false
        case .system: isChinese = locale.language.languageCode?.identifier == "zh"
        }
        let script: ThemeScript = isChinese ? .cjk : .latin
        let spec = ThemeFontResolver.spec(for: mode, script: script)
        guard let name = spec.familyCandidates.first(where: { name in
            #if os(macOS)
            NSFont(name: name, size: size) != nil
            #else
            UIFont(name: name, size: size) != nil
            #endif
        }) else { return nil }
        return .custom(name, size: size)
    }
}
