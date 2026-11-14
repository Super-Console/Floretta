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
