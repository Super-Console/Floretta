import FlorettaCore
import SwiftUI

/// Shared bottom status strip for iPhone, iPad, and macOS.
///
/// One Liquid Glass capsule on the trailing edge (TD-003), left to right: the
/// live topic count, the live zoom percent, the pointer / hand tool (Mac only),
/// the view mode, the outline switch,
/// and the full-screen switch. On the Mac, hovering the topic count opens the
/// 主题 / 字数 / 字符数 breakdown; iPad and iPhone open it with a tap. Those
/// three numbers used to sit in the ••• menu and now live here only; they still
/// come from the one `TopicTitleCensus` the editor already builds, so there is
/// no second counter. The presentation tab is deliberately absent.
///
/// The plate is `AppleGlassChrome`'s `bottomBarCapsule` role: no hand-written
/// gradient, no custom blur, no shadow.
///
/// The editor's bottom row places this capsule beside the canvas sheet capsule
/// (TD-002). It draws at `EditorStatusBarChrome.controlMinHeight`, owns no spacer
/// and no window inset, and is never compressed: on a narrow window the sheet
/// name truncates first. Sharing the row and the plate height is what keeps the
/// two capsules' bottom edges on one line.
struct EditorStatusStrip: View {
    @Bindable var session: EditorSession
    var camera: CanvasCamera
    var census: TopicTitleCensus
    var language: AppLanguage
    @Binding var showOutline: Bool
    /// Pointer / hand. Written straight through to `AppSettings`, so the choice
    /// survives the next launch. Only the Mac draws the control.
    @Binding var pointerMode: CanvasPointerMode
    /// Native motion only: chrome glyph swaps animate, and 减少动态效果 turns
    /// that off. Canvas content is never animated here.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Hover (macOS) and tap (iPad / iPhone) present the same breakdown.
    @State private var showsCensus = false
    /// Leaving the trigger for the popover itself must not close it. A short
    /// grace period covers the gap; entering the popover cancels it.
    @State private var censusDismissTask: Task<Void, Never>?

    var body: some View {
        capsule
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("statusBar")
            .chromeTypography(language: language, role: .compact)
            .onDisappear {
                censusDismissTask?.cancel()
                censusDismissTask = nil
                showsCensus = false
            }
    }

    /// Three groups, separated by a hairline that owns the gap on both sides.
    /// The row itself keeps no spacing: `capsuleControlSpacing` is inside a
    /// group and `capsuleGroupSpacing` is across a divider, and mixing them in
    /// one `HStack(spacing:)` is what made the groups read as one undivided
    /// run of icons.
    private var capsule: some View {
        HStack(spacing: 0) {
            censusTrigger
            separator
            zoomMenu
            separator
            viewControls
        }
        .controlSize(.small)
        .padding(.horizontal, EditorStatusBarChrome.capsuleHorizontalPadding)
        .padding(.vertical, EditorStatusBarChrome.capsuleVerticalPadding)
        .frame(minHeight: EditorStatusBarChrome.controlMinHeight)
        .appleGlassChrome(.bottomBarCapsule)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("statusBar.capsule")
    }

    /// The three icon controls, `capsuleControlSpacing` apart.
    private var viewControls: some View {
        HStack(spacing: EditorStatusBarChrome.capsuleControlSpacing) {
            #if os(macOS)
            pointerModeToggle
            #endif
            viewModeToggle
            outlineToggle
            fullScreenToggle
        }
    }

    /// A hairline, not a surface: the capsule stays the only glass on the row.
    /// Its inset is the group gap, so the divider sits in the middle of it.
    private var separator: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(
                width: EditorStatusBarChrome.capsuleSeparatorWidth,
                height: EditorStatusBarChrome.capsuleSeparatorHeight
            )
            .padding(.horizontal, EditorStatusBarChrome.capsuleSeparatorInset)
            .accessibilityHidden(true)
    }

    // MARK: counts

    private var censusTrigger: some View {
        Button(action: toggleCensus) {
            Text(verbatim: line("主题 %lld", census.topics))
                .monospacedDigit()
                .frame(minHeight: EditorStatusBarChrome.iconButtonSize)
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

    // MARK: pointer mode

    /// 指针 / 手掌, the Mac tool in XMind's bottom-right corner. The glyph is the
    /// mode that is showing; one click flips it, so there is no ▾ menu. The
    /// preference lives in `AppSettings`, so the next document opens in it too.
    private var pointerModeToggle: some View {
        Button {
            pointerMode = pointerMode.toggled
        } label: {
            statusSymbol(pointerMode.symbolName)
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: pointerModeActionLabel))
        .accessibilityLabel(Text(verbatim: pointerModeActionLabel))
        .accessibilityHint(Text(verbatim: string("用指针框选主题，或用手掌拖动画布")))
        .accessibilityIdentifier("statusBar.pointer")
    }

    /// Current mode, then what a click does.
    private var pointerModeActionLabel: String {
        "\(pointerModeTitle(pointerMode)) · \(pointerModeTitle(pointerMode.toggled))"
    }

    private func pointerModeTitle(_ mode: CanvasPointerMode) -> String {
        string(mode == .pan ? "手掌模式" : "指针模式")
    }

    // MARK: view mode, outline, full screen

    /// The first icon control of the XMind capsule (卡片视图). This app has no
    /// card view; the existing 查看模式 command is what the icon drives, so the
    /// slot ships a live control. One click flips 地图模式 ⇄ 聚焦模式: the glyph
    /// is the mode that is showing (`map` / `scope`), and the tooltip and the
    /// accessibility label both say which mode the click lands in. No ▾ menu, so
    /// no second click.
    private var viewModeToggle: some View {
        Button {
            changeViewMode(session.viewMode == .map ? .focus : .map)
        } label: {
            statusSymbol(viewModeSymbol(session.viewMode), on: session.viewMode == .focus)
                // System symbol swap, so 地图 ⇄ 聚焦 does not hard-cut the glyph.
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: viewModeActionLabel))
        .accessibilityLabel(Text(verbatim: viewModeActionLabel))
        .accessibilityHint(Text(verbatim: string("在地图模式和聚焦模式之间切换")))
        .accessibilityIdentifier("statusBar.views")
    }

    /// The mode change is chrome state: the system spring drives it, and
    /// nothing moves when 减少动态效果 is on.
    private func changeViewMode(_ mode: DocumentViewMode) {
        #if os(iOS)
        if reduceMotion {
            session.viewMode = mode
        } else {
            withAnimation(.snappy) { session.viewMode = mode }
        }
        #else
        session.viewMode = mode
        #endif
    }

    /// Current mode, then what a click does. Both halves are existing keys.
    private var viewModeActionLabel: String {
        "\(viewModeTitle(session.viewMode)) · \(string("在地图模式和聚焦模式之间切换"))"
    }

    private var outlineToggle: some View {
        Button {
            toggleOutline()
        } label: {
            statusSymbol(EditorToolbarCatalog.command(.outline).symbol, on: showOutline)
                // Apple's symbol effect: one short bounce acknowledges the tap
                // while the panel itself slides in. Reduced motion removes it.
                .symbolEffect(.bounce, options: .nonRepeating, value: showOutline)
                .symbolEffectsRemoved(reduceMotion)
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: string(EditorToolbarCatalog.command(.outline).help)))
        .accessibilityLabel(Text(verbatim: string(EditorToolbarCatalog.command(.outline).title)))
        .accessibilityIdentifier("status.outline")
    }

    /// The panel's own transition is driven by the editor's `showOutline`
    /// animation; this keeps the toggle's state change in the same transaction.
    private func toggleOutline() {
        #if os(iOS)
        if reduceMotion {
            showOutline.toggle()
        } else {
            withAnimation(.snappy) { showOutline.toggle() }
        }
        #else
        showOutline.toggle()
        #endif
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
            .font(.system(size: EditorStatusBarChrome.chromeFontSize, weight: .regular))
            .frame(
                width: EditorStatusBarChrome.iconButtonSize,
                height: EditorStatusBarChrome.iconButtonSize
            )
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

/// The sheet-name slot of the bottom row: the child keeps its natural width
/// while it fits and truncates inside `maxWidth` once it does not.
///
/// A flexible frame cannot express that. `.frame(maxWidth:)` sizes itself to
/// the proposal up to its cap, so a short name sat in a wide box on the left
/// and the capsule was stretched to the cap. A `Layout` both proposes the cap
/// — which is what makes the text truncate — and reports the child's own
/// width, so the capsule hugs a short name and a long one stays inside the cap.
struct CappedWidthLayout: Layout {
    var maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let width = min(proposal.width ?? maxWidth, maxWidth)
        let size = subview.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
        return CGSize(width: min(size.width, maxWidth), height: size.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        let width = min(bounds.width, maxWidth)
        subview.place(
            at: CGPoint(x: bounds.midX - width / 2, y: bounds.minY),
            proposal: ProposedViewSize(width: width, height: bounds.height)
        )
    }
}
