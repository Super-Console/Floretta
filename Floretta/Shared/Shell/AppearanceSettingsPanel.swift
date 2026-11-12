import FlorettaCore
import SwiftUI

/// Shared appearance controls for Settings and the style inspector.
/// Both views bind the same `AppSettings` instance so a change in one place is
/// visible in the other. Typography rendering is not wired in this skeleton.
struct AppearanceSettingsPanel: View {
    @Bindable var settings: AppSettings
    /// `settings.appearance` or `inspector.appearance`.
    var identifierPrefix: String
    var density: Density = .settings

    enum Density {
        case settings
        case inspector
    }

    var body: some View {
        Section(text("外观模式")) {
            Picker(text("外观模式"), selection: $settings.appearanceMode) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(verbatim: text(mode.titleKey))
                        .tag(mode)
                        .accessibilityIdentifier("\(identifierPrefix).\(mode.rawValue)")
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("\(identifierPrefix).mode")

            Picker(text("字体族"), selection: fontFamilyID) {
                ForEach(AppearanceCatalog.families) { family in
                    Text(verbatim: text(family.nameKey)).tag(family.id)
                }
            }
            .accessibilityIdentifier("\(identifierPrefix).fontFamily")

            if density == .settings {
                stubRow("底色", identifier: "canvas")
                stubRow("文字色", identifier: "text")
                stubRow("次级文字色", identifier: "secondaryText")
                stubRow("节点底色", identifier: "nodeFill")
                stubRow("字号缩放", identifier: "fontSizeScale")
                stubRow("行高", identifier: "lineHeight")
                stubRow("圆角半径", identifier: "cornerRadius")
                Text(verbatim: "中英混排 Abc 衬线预览")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("\(identifierPrefix).preview")
            } else {
                stubRow("底色", identifier: "canvas")
            }

            Button(text("恢复该模式默认值")) {
                settings.restoreCurrentModeDefaults()
            }
            .accessibilityIdentifier("\(identifierPrefix).restore")
        }
    }

    private var fontFamilyID: Binding<String> {
        Binding(
            get: { settings.currentProfile.fontFamilyID },
            set: { id in
                settings.updateCurrentProfile { $0.fontFamilyID = id }
            }
        )
    }

    @ViewBuilder
    private func stubRow(_ key: String, identifier: String) -> some View {
        LabeledContent(text(key)) {
            Text(verbatim: stubValue(identifier))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityIdentifier("\(identifierPrefix).\(identifier)")
    }

    private func stubValue(_ identifier: String) -> String {
        let profile = settings.currentProfile
        let colors = profile.light
        switch identifier {
        case "canvas": return colors.canvasHex
        case "text": return colors.textHex
        case "secondaryText": return colors.secondaryTextHex
        case "nodeFill": return colors.nodeFillHex
        case "fontSizeScale": return String(format: "%.2f", profile.fontSizeScale)
        case "lineHeight": return String(format: "%.2f", profile.lineHeight)
        case "cornerRadius": return String(format: "%.0f", profile.cornerRadius)
        default: return ""
        }
    }

    private func text(_ key: String) -> String {
        FlorettaL10n.string(key, language: settings.language)
    }
}
