import FlorettaCore
import SwiftUI

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
