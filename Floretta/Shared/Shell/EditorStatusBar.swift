import FlorettaCore
import SwiftUI

extension View {
    /// Bottom status bar. iOS and iPad use the system bottom bar. macOS uses a
    /// bottom inset, with the zoom menu and view switcher on the trailing side.
    func editorStatusBar(
        visible: Bool,
        session: EditorSession,
        camera: CanvasCamera,
        language: AppLanguage
    ) -> some View {
        modifier(EditorStatusBarModifier(
            visible: visible,
            session: session,
            camera: camera,
            language: language
        ))
    }
}

@MainActor
private struct EditorStatusBarModifier: ViewModifier {
    var visible: Bool
    var session: EditorSession
    var camera: CanvasCamera
    var language: AppLanguage

    func body(content: Content) -> some View {
        if visible {
            placed(content)
        } else {
            content
        }
    }

    @ViewBuilder
    private func placed(_ content: Content) -> some View {
        let bar = EditorStatusBar(
            session: session,
            camera: camera,
            language: language
        )
        #if os(iOS)
        content.toolbar {
            ToolbarItem(placement: .bottomBar) {
                bar
            }
        }
        #else
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            bar
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(.bar)
                .overlay(alignment: .top) { Divider() }
        }
        #endif
    }
}

/// Topic capsule, zoom menu, and the real view switch. Each child reads only
/// the state it displays, so a zoom gesture does not walk the topic tree.
private struct EditorStatusBar: View {
    @Bindable var session: EditorSession
    var camera: CanvasCamera
    var language: AppLanguage

    var body: some View {
        HStack(spacing: 8) {
            TopicCountCapsuleView(
                model: TopicCountCapsuleModel(
                    document: session.document,
                    titles: TitleCountSupplyReader.supply(for: session.document)
                ),
                language: language
            )
            Spacer(minLength: 8)
            StatusZoomMenu(camera: camera, language: language)
                .layoutPriority(1)
            StatusViewSwitcher(session: session, language: language)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("statusBar")
    }
}

private struct TopicCountCapsuleView: View {
    var model: TopicCountCapsuleModel
    var language: AppLanguage
    @State private var showBreakdown = false

    var body: some View {
        if let breakdown = model.breakdown {
            Button {
                showBreakdown = true
            } label: {
                capsuleLabel(capsuleLine)
            }
            .buttonStyle(.plain)
            .help(Text(verbatim: breakdownLines(breakdown).joined(separator: "\n")))
            .popover(isPresented: $showBreakdown, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(breakdownLines(breakdown), id: \.self) { line in
                        Text(verbatim: line)
                            .monospacedDigit()
                    }
                }
                .padding(12)
                .accessibilityIdentifier("statusBar.topics.breakdown")
            }
            .accessibilityValue(Text(verbatim: breakdownLines(breakdown).joined(separator: ", ")))
        } else {
            capsuleLabel(capsuleLine)
        }
    }

    private var capsuleLine: String {
        let topics = format("%lld 个主题", model.topicCount)
        guard let titles = model.titles else { return topics }
        let words = format("字数 %lld", titles.wordCount)
        return "\(topics) · \(words)"
    }

    private func breakdownLines(_ breakdown: TopicCountBreakdown) -> [String] {
        [
            format("主题数 %lld", breakdown.topicCount),
            format("字数 %lld", breakdown.wordCount),
            format("字符数 %lld", breakdown.characterCount),
        ]
    }

    private func format(_ key: String, _ count: Int) -> String {
        FlorettaL10n.format(key, language: language, arguments: [Int64(count)])
    }

    private func capsuleLabel(_ line: String) -> some View {
        Text(verbatim: line)
            .font(.callout)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
            .accessibilityLabel(Text(verbatim: line))
            .accessibilityIdentifier("statusBar.topics")
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

/// Map and focus only. The picker lists `DocumentViewMode.allCases`, which is
/// the view mode the editor already stores.
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
