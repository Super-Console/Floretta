import FlorettaCore
import SwiftUI

/// Zoom menu and view switcher for the editor's existing bottom bar.
/// Topic and word counts stay in `TopicStatusBar`, which reads `TopicTitleCensus`.
struct EditorStatusControls: View {
    @Bindable var session: EditorSession
    var camera: CanvasCamera
    var language: AppLanguage

    var body: some View {
        HStack(spacing: 8) {
            StatusZoomMenu(camera: camera, language: language)
            StatusViewSwitcher(session: session, language: language)
        }
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

/// Map and focus only. The picker lists `DocumentViewMode.allCases`.
private struct StatusViewSwitcher: View {
    @Bindable var session: EditorSession
    var language: AppLanguage

    var body: some View {
        Picker(selection: $session.viewMode) {
            ForEach(DocumentViewMode.allCases, id: \.self) { mode in
                Text(verbatim: text(title(mode))).tag(mode)
            }
        } label: {
            Text(verbatim: text("查看模式"))
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 220)
        .accessibilityLabel(text("查看模式"))
        .accessibilityIdentifier("statusBar.views")
        .help(Text(verbatim: text("在地图模式和聚焦模式之间切换")))
    }

    private func text(_ key: String) -> String {
        FlorettaL10n.string(key, language: language)
    }

    private func title(_ mode: DocumentViewMode) -> String {
        switch mode {
        case .map:
            return "地图模式"
        case .focus:
            return "聚焦模式"
        }
    }
}
