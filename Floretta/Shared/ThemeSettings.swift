import FlorettaCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Resolves the content face from the family the user picked in the font list.
/// There is no mode: serif is one entry in `AppearanceCatalog.families`.
struct ThemeTypographyModifier: ViewModifier {
    var language: AppLanguage = .system
    @Environment(\.locale) private var locale
    @AppStorage(AppearanceMigration.contentFontFamilyKey) private var storedFamilyID = AppearanceCatalog.defaultFontFamilyID
    @AppStorage("floretta.language") private var storedLanguage = AppLanguage.system.rawValue

    func body(content: Content) -> some View {
        let selectedLanguage = language == .system
            ? (AppLanguage(rawValue: storedLanguage) ?? .system)
            : language
        let script: ThemeScript = usesChinese(language: selectedLanguage, locale: locale) ? .cjk : .latin
        let spec = ThemeFontResolver.spec(script: script, familyID: storedFamilyID)
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
    static func font(familyID: String, language: AppLanguage, locale: Locale = .current, size: CGFloat) -> Font? {
        let isChinese: Bool
        switch language {
        case .simplifiedChinese: isChinese = true
        case .english: isChinese = false
        case .system: isChinese = locale.language.languageCode?.identifier == "zh"
        }
        let script: ThemeScript = isChinese ? .cjk : .latin
        let spec = ThemeFontResolver.spec(script: script, familyID: familyID)
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
