import FlorettaCore
import SwiftUI

/// Shared bottom status strip for iPhone, iPad, and macOS.
///
/// One Liquid Glass capsule on the trailing edge (TD-003), left to right: the
/// live topic count, the live zoom percent, the view mode, the outline switch,
/// and the full-screen switch. On the Mac, hovering the topic count opens the
/// 主题 / 字数 / 字符数 breakdown; iPad and iPhone open it with a tap. Those
/// three numbers used to sit in the ••• menu and now live here only; they still
/// come from the one `TopicTitleCensus` the editor already builds, so there is
/// no second counter. The presentation tab is deliberately absent.
///
/// The plate is `AppleGlassChrome`'s `bottomBarCapsule` role: no hand-written
/// gradient, no custom blur, no shadow.
struct EditorStatusStrip: View {
    @Bindable var session: EditorSession
    var camera: CanvasCamera
    var census: TopicTitleCensus
    var language: AppLanguage
    @Binding var showOutline: Bool

    /// Hover (macOS) and tap (iPad / iPhone) present the same breakdown.
    @State private var showsCensus = false
    /// Leaving the trigger for the popover itself must not close it. A short
    /// grace period covers the gap; entering the popover cancels it.
    @State private var censusDismissTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 8)
            capsule
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: EditorStatusBarChrome.controlMinHeight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("statusBar")
        .chromeTypography(language: language, role: .compact)
        .onDisappear {
            censusDismissTask?.cancel()
            censusDismissTask = nil
            showsCensus = false
        }
    }

    private var capsule: some View {
        HStack(spacing: 10) {
            censusTrigger
            separator
            zoomMenu
            separator
            viewModeMenu
            outlineToggle
            fullScreenToggle
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .appleGlassChrome(.bottomBarCapsule)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("statusBar.capsule")
    }

    /// A hairline, not a surface: the capsule stays the only glass on the row.
    private var separator: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 1, height: 16)
            .accessibilityHidden(true)
    }

    // MARK: counts

    private var censusTrigger: some View {
        Button(action: toggleCensus) {
            Text(verbatim: line("主题 %lld", census.topics))
                .monospacedDigit()
                .frame(minHeight: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover(perform: hoverCensus)
        .popover(isPresented: $showsCensus, arrowEdge: .bottom) {
            StatusCensusBreakdown(census: census, language: language) { hovering in
                if hovering {
                    censusDismissTask?.cancel()
                    censusDismissTask = nil
                } else {
                    scheduleCensusDismissal()
                }
            }
        }
        .help(Text(verbatim: censusLabel))
        .accessibilityLabel(censusLabel)
        .accessibilityIdentifier("status.topics")
    }

    private var censusLabel: String {
        [
            line("主题 %lld", census.topics),
            line("字数 %lld", census.words),
            line("字符数 %lld", census.characters),
        ].joined(separator: "\n")
    }

    private func toggleCensus() {
        censusDismissTask?.cancel()
        censusDismissTask = nil
        showsCensus.toggle()
    }

    private func hoverCensus(_ hovering: Bool) {
        censusDismissTask?.cancel()
        censusDismissTask = nil
        if hovering {
            showsCensus = true
        } else {
            scheduleCensusDismissal()
        }
    }

    /// Captures the binding, never `self`, so the task stays sendable.
    private func scheduleCensusDismissal() {
        let presented = $showsCensus
        censusDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            presented.wrappedValue = false
        }
    }

    // MARK: zoom

    private var zoomMenu: some View {
        Menu {
            ForEach(EditorStatusZoomChoice.menu, id: \.self) { choice in
                zoomRow(choice)
            }
        } label: {
            StatusZoomLabel(camera: camera)
        }
        .help(Text(verbatim: string("选择缩放比例，或让导图适应窗口")))
        .accessibilityLabel(Text(verbatim: "\(string("缩放")) \(camera.chrome.zoomPercent)%"))
        .accessibilityIdentifier("statusBar.zoom")
    }

    @ViewBuilder
    private func zoomRow(_ choice: EditorStatusZoomChoice) -> some View {
        switch choice {
        case .stop(let stop):
            Button {
                camera.zoom(to: stop)
            } label: {
                Text(verbatim: "\(stop.percent)%")
            }
            .help(Text(verbatim: FlorettaL10n.format("把画布缩放到 %lld%%", language: language, arguments: [Int64(stop.percent)])))
        case .fitWindow:
            Button {
                camera.fitToContent()
            } label: {
                Text(verbatim: string("适应窗口"))
            }
            .keyboardShortcut("0", modifiers: .command)
        }
    }

    // MARK: view mode, outline, full screen

    /// The first icon control of the XMind capsule (卡片视图). This app has no
    /// card view; the existing 查看模式 command is what the icon drives, so the
    /// slot ships a live control instead of a dead button.
    private var viewModeMenu: some View {
        Menu {
            ForEach(DocumentViewMode.allCases, id: \.self) { mode in
                Button {
                    session.viewMode = mode
                } label: {
                    Label(viewModeTitle(mode), systemImage: viewModeSymbol(mode))
                }
            }
        } label: {
            statusSymbol(viewModeSymbol(session.viewMode), on: session.viewMode == .focus)
        }
        .help(Text(verbatim: string("在地图模式和聚焦模式之间切换")))
        .accessibilityLabel(Text(verbatim: string("查看模式")))
        .accessibilityIdentifier("statusBar.views")
    }

    private var outlineToggle: some View {
        Button {
            showOutline.toggle()
        } label: {
            statusSymbol(EditorToolbarCatalog.command(.outline).symbol, on: showOutline)
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: string(EditorToolbarCatalog.command(.outline).help)))
        .accessibilityLabel(Text(verbatim: string(EditorToolbarCatalog.command(.outline).title)))
        .accessibilityIdentifier("status.outline")
    }

    private var fullScreenToggle: some View {
        Button {
            session.enterZen()
        } label: {
            statusSymbol(EditorToolbarCatalog.command(.immersive).symbol)
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: string(EditorToolbarCatalog.command(.immersive).help)))
        .accessibilityLabel(Text(verbatim: string(EditorToolbarCatalog.command(.immersive).title)))
        .accessibilityIdentifier("status.immersive")
    }

    private func viewModeSymbol(_ mode: DocumentViewMode) -> String {
        switch mode {
        case .map: return EditorToolbarCatalog.command(.mapMode).symbol
        case .focus: return EditorToolbarCatalog.command(.focusMode).symbol
        }
    }

    private func viewModeTitle(_ mode: DocumentViewMode) -> String {
        string(mode == .map ? "地图模式" : "聚焦模式")
    }

    private func statusSymbol(_ symbol: String, on: Bool = false) -> some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: 13, weight: .medium))
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
            .foregroundStyle(on ? Color.accentColor : Color.primary)
    }

    // MARK: text

    private func string(_ key: String) -> String {
        FlorettaL10n.string(key, language: language)
    }

    private func line(_ key: String, _ value: Int) -> String {
        FlorettaL10n.format(key, language: language, arguments: [Int64(value)])
    }
}

/// The three numbers the capsule reports. Same `TopicTitleCensus` the editor
/// already measures; this view counts nothing.
private struct StatusCensusBreakdown: View {
    var census: TopicTitleCensus
    var language: AppLanguage
    var onHoverChange: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            line("主题 %lld", census.topics, identifier: "status.popover.topics")
            line("字数 %lld", census.words, identifier: "status.popover.words")
            line("字符数 %lld", census.characters, identifier: "status.popover.characters")
        }
        .font(.callout)
        .monospacedDigit()
        .padding(6)
        .onHover(perform: onHoverChange)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("status.popover")
    }

    private func line(_ key: String, _ value: Int, identifier: String) -> some View {
        Text(verbatim: FlorettaL10n.format(key, language: language, arguments: [Int64(value)]))
            .accessibilityIdentifier(identifier)
    }
}

/// Live zoom face. Reads the percent in its own body, so a zoom step redraws
/// this label instead of the whole editor.
private struct StatusZoomLabel: View {
    var camera: CanvasCamera

    var body: some View {
        Text("\(camera.chrome.zoomPercent)%")
            .monospacedDigit()
    }
}
