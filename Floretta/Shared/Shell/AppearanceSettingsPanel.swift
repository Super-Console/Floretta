import FlorettaCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Stable accessibility identifiers for the Settings and inspector entries.
enum AppearanceIdentifier {
    static let settingsPrefix = "settings.appearance"
    static let inspectorPrefix = "inspector.appearance"
    static let keys = [
        "mode", "classic", "modern", "custom", "fontFamily",
        "canvas", "text", "secondaryText", "nodeFill",
        "fontSizeScale", "lineHeight", "cornerRadius", "restore", "preview",
    ]

    static func id(_ prefix: String, _ key: String) -> String {
        "\(prefix).\(key)"
    }
}

/// Shared appearance controls for Settings and the style inspector.
/// Both views bind the same `AppSettings` instance so a change in one place is
/// visible in the other immediately. Chrome (this form) stays on the system font.
struct AppearanceSettingsPanel: View {
    @Bindable var settings: AppSettings
    /// `settings.appearance` or `inspector.appearance`.
    var identifierPrefix: String
    var density: Density = .settings
    @Environment(\.colorScheme) private var colorScheme

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
                        .accessibilityIdentifier(AppearanceIdentifier.id(identifierPrefix, mode.rawValue))
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(AppearanceIdentifier.id(identifierPrefix, "mode"))

            Picker(text("字体族"), selection: fontFamilyID) {
                ForEach(AppearanceCatalog.families) { family in
                    Text(verbatim: text(family.nameKey)).tag(family.id)
                }
            }
            .accessibilityIdentifier(AppearanceIdentifier.id(identifierPrefix, "fontFamily"))

            colorPicker("底色", key: "canvas", hex: colorHex(\.canvasHex) { $0.canvasHex = $1 })
            colorPicker("文字色", key: "text", hex: colorHex(\.textHex) { $0.textHex = $1 })
            colorPicker("次级文字色", key: "secondaryText", hex: colorHex(\.secondaryTextHex) { $0.secondaryTextHex = $1 })
            colorPicker("节点底色", key: "nodeFill", hex: colorHex(\.nodeFillHex) { $0.nodeFillHex = $1 })

            sliderRow("字号缩放", key: "fontSizeScale", value: scaleBinding, range: 0.5...2.0, step: 0.05)
            sliderRow("行高", key: "lineHeight", value: lineHeightBinding, range: 1.0...2.0, step: 0.05)
            sliderRow("圆角半径", key: "cornerRadius", value: cornerBinding, range: 0...24, step: 1)

            preview
                .accessibilityIdentifier(AppearanceIdentifier.id(identifierPrefix, "preview"))

            Button(text("恢复该模式默认值")) {
                settings.restoreCurrentModeDefaults()
            }
            .accessibilityIdentifier(AppearanceIdentifier.id(identifierPrefix, "restore"))
        }
        // Controls stay on the system UI font even when the map uses a serif family.
        .font(.body)
    }

    private var preview: some View {
        let colors = settings.currentProfile.colors(for: activeScheme)
        let radius = settings.currentProfile.cornerRadius
        let size = 17 * settings.currentProfile.clampedFontSizeScale
        return Text(verbatim: "中英混排 Abc 汉字 日本語 한국어")
            .font(FlorettaTitleFont.font(design: "default", size: size, familyID: settings.currentProfile.fontFamilyID))
            .foregroundStyle(ink(colors.textHex))
            .lineSpacing(max(0, (settings.currentProfile.lineHeight - 1) * size))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ink(colors.canvasHex), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    private var activeScheme: MapColorScheme {
        colorScheme == .dark ? .dark : .light
    }

    private var fontFamilyID: Binding<String> {
        Binding(
            get: { settings.currentProfile.fontFamilyID },
            set: { id in
                settings.updateCurrentProfile { $0.fontFamilyID = id }
            }
        )
    }

    private var scaleBinding: Binding<Double> {
        Binding(
            get: { settings.currentProfile.fontSizeScale },
            set: { value in
                settings.updateCurrentProfile { $0.fontSizeScale = min(max(value, 0.5), 2.0) }
            }
        )
    }

    private var lineHeightBinding: Binding<Double> {
        Binding(
            get: { settings.currentProfile.lineHeight },
            set: { value in
                settings.updateCurrentProfile { $0.lineHeight = min(max(value, 1.0), 2.0) }
            }
        )
    }

    private var cornerBinding: Binding<Double> {
        Binding(
            get: { settings.currentProfile.cornerRadius },
            set: { value in
                settings.updateCurrentProfile { $0.cornerRadius = min(max(value, 0), 24) }
            }
        )
    }

    private func colorHex(
        _ keyPath: KeyPath<AppearanceColorSet, String>,
        set: @escaping (inout AppearanceColorSet, String) -> Void
    ) -> Binding<String> {
        Binding(
            get: { settings.currentProfile.colors(for: activeScheme)[keyPath: keyPath] },
            set: { hex in
                settings.updateCurrentProfile { profile in
                    if activeScheme == .dark {
                        set(&profile.dark, hex)
                    } else {
                        set(&profile.light, hex)
                    }
                }
            }
        )
    }

    private func colorPicker(_ key: String, key id: String, hex: Binding<String>) -> some View {
        ColorPicker(selection: colorBinding(hex), supportsOpacity: false) {
            Text(verbatim: text(key))
        }
        .accessibilityIdentifier(AppearanceIdentifier.id(identifierPrefix, id))
    }

    private func colorBinding(_ hex: Binding<String>) -> Binding<Color> {
        Binding(
            get: { ink(hex.wrappedValue) },
            set: { hex.wrappedValue = rgbHex($0) }
        )
    }

    private func sliderRow(_ key: String, key id: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: text(key))
                Spacer()
                Text(verbatim: id == "cornerRadius" ? String(format: "%.0f", value.wrappedValue) : String(format: "%.2f", value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
        .accessibilityIdentifier(AppearanceIdentifier.id(identifierPrefix, id))
    }

    private func ink(_ hex: String) -> Color {
        guard let parsed = BranchColor(hex: hex) else { return .primary }
        return Color(red: parsed.red, green: parsed.green, blue: parsed.blue)
    }

    private func rgbHex(_ color: Color) -> String {
        #if os(macOS)
        let converted = NSColor(color).usingColorSpace(.sRGB)
        let r = converted?.redComponent ?? 0
        let g = converted?.greenComponent ?? 0
        let b = converted?.blueComponent ?? 0
        #else
        let converted = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 1
        converted.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    private func text(_ key: String) -> String {
        FlorettaL10n.string(key, language: settings.language)
    }
}
