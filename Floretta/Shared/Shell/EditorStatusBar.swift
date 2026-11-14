import FlorettaCore
import SwiftUI

/// Shared bottom status strip for iPhone, iPad, and macOS.
/// Text floats on the canvas: no plate, no shadow, only a soft feathered edge.
struct EditorStatusStrip: View {
    @Bindable var session: EditorSession
    var camera: CanvasCamera
    var language: AppLanguage

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: EditorStatusBarChrome.controlMinHeight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("statusBar")
        .themeTypography(language: language)
    }
}

/// Flat, read-only topic / word / character counts for the top-right overflow.
/// Reuses `TopicTitleCensus`; does not invent a second counter.
struct EditorOverflowCensus: View {
    var census: TopicTitleCensus
    var locale: Locale

    var body: some View {
        item("主题 %lld", census.topics, identifier: "status.topics")
        item("字数 %lld", census.words, identifier: "status.words")
        item("字符数 %lld", census.characters, identifier: "status.characters")
    }

    var accessibilityLabel: String {
        [
            line("主题 %lld", census.topics),
            line("字数 %lld", census.words),
            line("字符数 %lld", census.characters),
        ].joined(separator: "\n")
    }

    private func item(_ key: String, _ value: Int, identifier: String) -> some View {
        Button(line(key, value)) {}
            .disabled(true)
            .accessibilityIdentifier(identifier)
    }

    private func line(_ key: String, _ value: Int) -> String {
        FlorettaL10n.format(key, locale: locale, arguments: [Int64(value)])
    }
}
