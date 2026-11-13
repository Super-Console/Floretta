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
            EditorStatusControls(
                camera: camera,
                language: language
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: EditorStatusBarChrome.controlMinHeight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("statusBar")
    }
}

/// The single zoom control that remains in the editor's bottom bar.
/// Topic and word counts live in `EditorOverflowCensus`, which reads `TopicTitleCensus`.
struct EditorStatusControls: View {
    var camera: CanvasCamera
    var language: AppLanguage

    var body: some View {
        StatusZoomMenu(camera: camera, language: language)
            .appleGlassChrome(.toolbarFloatingButton)
        .frame(minHeight: EditorStatusBarChrome.controlMinHeight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("statusBar.controls")
    }
}

private struct StatusZoomMenu: View {
    var camera: CanvasCamera
    var language: AppLanguage

    var body: some View {
        Menu {
            ForEach(EditorStatusZoomChoice.menu, id: \.self) { choice in
                zoomButton(choice)
            }
        } label: {
            Text("\(camera.chrome.zoomPercent)%")
                .monospacedDigit()
                .frame(minHeight: EditorStatusBarChrome.controlMinHeight)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("\(camera.chrome.zoomPercent)%"))
        .accessibilityHint(Text(verbatim: text("选择缩放比例，或让导图适应窗口")))
        .accessibilityIdentifier("statusBar.zoom")
        .help(Text(verbatim: text("选择缩放比例，或让导图适应窗口")))
    }

    private func text(_ key: String) -> String {
        FlorettaL10n.string(key, language: language)
    }

    @ViewBuilder
    private func zoomButton(_ choice: EditorStatusZoomChoice) -> some View {
        switch choice {
        case .stop(let stop):
            Button(text("\(stop.percent)%")) { camera.zoom(to: stop) }
                .accessibilityHint(Text(verbatim: FlorettaL10n.format(
                    "把画布缩放到 %lld%%",
                    language: language,
                    arguments: [Int64(stop.percent)]
                )))
        case .fitWindow:
            Button(text("适应窗口")) { camera.fitToContent() }
                .keyboardShortcut("0", modifiers: .command)
                .accessibilityHint(Text(verbatim: text("让整张导图缩进窗口里")))
        }
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
