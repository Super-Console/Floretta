import Foundation

/// Result of reading the settings the app used to persist.
public struct MigratedAppearance: Equatable, Sendable {
    public var homeBackground: HomeBackground
    public var profile: AppearanceProfile
    /// True when a stored classic / modern / custom value was found and mapped.
    public var readLegacyMode: Bool

    public init(homeBackground: HomeBackground, profile: AppearanceProfile, readLegacyMode: Bool) {
        self.homeBackground = homeBackground
        self.profile = profile
        self.readLegacyMode = readLegacyMode
    }
}

/// One-time move from the three appearance modes to 「首页背景」 plus a single
/// content profile. Old values are read once, mapped to one of the two new
/// backgrounds, and then removed so nothing unreadable is left behind.
///
/// Mapping: classic → 纸质米白, modern → 纯白, custom → 纸质米白 (custom was
/// seeded from classic). An unknown or missing value is 纸质米白.
///
/// The profile that belonged to the selected legacy mode is kept, so an existing
/// picture does not change font or spacing under the user's feet. Only a fresh
/// install starts on the sans default.
public enum AppearanceMigration {
    public static let legacyModeKey = "floretta.appearanceMode"
    public static let legacyProfilesKey = "floretta.appearanceProfiles"
    public static let legacyThemeModeKey = "floretta.theme.mode"
    public static let legacySerifOverrideKey = "floretta.theme.serifOverride"

    public static let homeBackgroundKey = "floretta.homeBackground"
    public static let profileKey = "floretta.appearanceProfile"
    /// Mirror of `profile.fontFamilyID`. The typography view modifier reads one
    /// string instead of decoding the profile on every body evaluation.
    public static let contentFontFamilyKey = "floretta.contentFontFamily"

    public enum LegacyMode: String, CaseIterable, Sendable {
        case classic
        case modern
        case custom

        public var homeBackground: HomeBackground {
            switch self {
            case .classic, .custom: .paper
            case .modern: .white
            }
        }
    }

    public static func homeBackground(forLegacyMode raw: String?) -> HomeBackground {
        guard let raw, let mode = LegacyMode(rawValue: raw) else { return .default }
        return mode.homeBackground
    }

    public static func resolve(
        legacyMode: String?,
        legacyProfiles: Data?,
        legacyThemeMode: String? = nil
    ) -> MigratedAppearance {
        let modeRaw = legacyMode ?? legacyThemeMode
        let background = homeBackground(forLegacyMode: modeRaw)
        let stored = AppearanceCatalog.legacyProfiles(from: legacyProfiles)
        let profile = modeRaw.flatMap { stored[$0] }
            ?? AppearanceCatalog.defaultProfile(homeBackground: background)
        return MigratedAppearance(
            homeBackground: background,
            profile: profile,
            readLegacyMode: modeRaw != nil
        )
    }

    /// Writes the new keys and removes the old ones. No-op when the new key
    /// already exists, so it can run on every launch.
    @discardableResult
    public static func migrateIfNeeded(defaults: UserDefaults) -> MigratedAppearance? {
        guard defaults.object(forKey: homeBackgroundKey) == nil else { return nil }
        let resolved = resolve(
            legacyMode: defaults.string(forKey: legacyModeKey),
            legacyProfiles: defaults.data(forKey: legacyProfilesKey),
            legacyThemeMode: defaults.string(forKey: legacyThemeModeKey)
        )
        persist(resolved, defaults: defaults)
        removeLegacyKeys(defaults: defaults)
        return resolved
    }

    /// Writes a resolved appearance without touching the legacy keys.
    public static func persist(_ appearance: MigratedAppearance, defaults: UserDefaults) {
        defaults.set(appearance.homeBackground.rawValue, forKey: homeBackgroundKey)
        if let data = try? AppearanceCatalog.encodeProfile(appearance.profile) {
            defaults.set(data, forKey: profileKey)
        }
        defaults.set(appearance.profile.fontFamilyID, forKey: contentFontFamilyKey)
    }

    public static func removeLegacyKeys(defaults: UserDefaults) {
        for key in [legacyModeKey, legacyProfilesKey, legacyThemeModeKey, legacySerifOverrideKey] {
            defaults.removeObject(forKey: key)
        }
    }
}
