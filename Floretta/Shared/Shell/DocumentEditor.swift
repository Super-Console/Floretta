import CoreTransferable
import FlorettaCore
import SwiftUI
import UniformTypeIdentifiers
import AVKit
#if os(macOS)
import AppKit
import PDFKit
#else
import UIKit
#endif

private enum RegionMetric: Hashable {
    case width
    case height
    case stroke
}

struct DocumentEditor: View {
    @Bindable var session: EditorSession
    @Bindable var settings: AppSettings
    var pasteboard: any PasteboardPort = ApplePlatformPorts.current().pasteboard
    var clock: any ClockPort = ApplePlatformPorts.current().clock
    var fontMetrics: any FontMetricsPort = ApplePlatformPorts.current().fonts
    var onClose: () -> Void
    var onEdit: (MindMapDocument) -> Void
    var onImport: () -> Void
    var onSavedCopy: (URL) -> Void = { _ in }
    var onMarkdownUpgrade: (URL, MarkdownUpgradeChoice) -> Void = { _, _ in }
    var thumbnailCache: ThumbnailFileCache? = nil

    @State private var showExport = false
    @State private var exportKind = ""
    @State private var exportFile = ExportFile(data: Data())
    @State private var exportType: UTType = .png
    @State private var exportName = "Floretta"
    @State private var exportError: String?
    @State private var showOutline = false
    @State private var outlineWide = false
    @State private var showInspector = false
    /// One shot. A later dismissal must stay dismissed; appearing again must not force the sheet back open.
    @State private var didAutoOpenInspector = false
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showCanvasRename = false
    @State private var canvasRenameText = ""
    @State private var canvasRenameIndex = 0
    @State private var showFind = false
    @State private var findQuery = ""
    @State private var showTagFilter = false
    @State private var inspectorTab = InspectorTab.style
    @State private var showAbout = false
    @State private var showShortcutHelp = false
    @State private var showThemes = false
    @State private var showHistory = false
    @Environment(\.colorScheme) private var colorScheme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var camera = CanvasCamera()
    @State private var showAttachmentImporter = false
    @State private var showImageImporter = false
    @State private var insertProposal: AttachmentInsertProposal?
    @State private var insertSource: URL?
    @State private var insertSourceIsCopy = false
    @State private var insertAccepted = false
    @State private var insertStoredName: String?
    @State private var previewPhase = FilePreviewPhase.idle
    @State private var mediaPlayer: AVPlayer?
    @State private var mediaPlayerURL: URL?
    @State private var mediaPlayerKind: NodeMediaKind = .other
    @State private var mediaPlaybackLease: UUID?
    @State private var audioNodeID: UUID?
    @State private var previewToken = 0
    @State private var thumbnails = AttachmentThumbnailMemory()
    @State private var showUpgrade = false
    @State private var upgradeFile = ExportFile(data: Data())
    @State private var upgradeName = "Floretta"
    @State private var askOpenUpgrade = false
    @State private var upgradedURL: URL?
    @State private var regionWidthDraft = ""
    @State private var regionHeightDraft = ""
    @State private var regionStrokeDraft = ""
    @FocusState private var regionMetric: RegionMetric?
    @State private var topicCensus = TopicCensusModel()
    @State private var isExitAffordanceRevealed = false
    @State private var exitAffordanceTask: Task<Void, Never>?
    /// Measured widths for the bottom row. The status capsule is measured, not
    /// guessed, so the sheet capsule's divider only goes when the row genuinely
    /// cannot afford it.
    @State private var bottomRowWidth: CGFloat = 0
    @State private var statusCapsuleWidth: CGFloat = 0

    #if os(macOS)
    @ToolbarContentBuilder
    private var macToolbarItemsLeading: some CustomizableToolbarContent {
        ToolbarItem(id: "document.navigation", placement: .navigation) {
            HStack(spacing: 8) {
                Button(action: onClose) {
                    Image(systemName: "chevron.backward")
                }
                .accessibilityLabel(text("返回"))
                .accessibilityIdentifier("basicChain.back")
                .help(Text(verbatim: text("返回导图列表")))

                Button(action: beginRename) {
                    Text(verbatim: documentTitle)
                        .lineLimit(1)
                }
                .buttonStyle(.borderless)
                .help(Text(verbatim: text("为这份导图重新命名")))
                .accessibilityLabel(documentTitle)
                .accessibilityHint(text("为这份导图重新命名"))
                .accessibilityIdentifier("document.title")
            }
        }
    }

    /// Group 1 (TD-006): the two commands everyone reaches for, plus delete.
    @ToolbarContentBuilder
    private var macToolbarItemsPrimary: some CustomizableToolbarContent {
        macItem(.undo)
        macItem(.redo)
        macItem(.delete)
    }

    /// Group 2 (TD-006): one ＋ 插入 pulldown. 子节点 / 同级 / 自由节点 / 便签 /
    /// 专区 / 图片 / 附件 / 语音输入 are rows of that menu, not bar items; they
    /// stay declared here so the customization palette can still surface them.
    @ToolbarContentBuilder
    private var macToolbarItemsInsert: some CustomizableToolbarContent {
        macItem(.insert)
        macItem(.child)
        macItem(.sibling)
        macItem(.dictation)
        macItem(.freeNode)
        macItem(.sticky)
        macItem(.region)
        macItem(.image)
        macItem(.attachment)
        macItem(.importFile)
    }

    /// Group 3 (TD-006): the commands that act on the current selection —
    /// 关系线 / 概要 / 边界 / 标签.
    @ToolbarContentBuilder
    private var macToolbarItemsRelations: some CustomizableToolbarContent {
        macItem(.link)
        macItem(.summary)
        macItem(.boundary)
        macItem(.tagFilter)
    }

    /// The ••• overflow. It stays a normal toolbar item, so a narrow window lets
    /// the system toolbar push it into its own overflow instead of this file
    /// inventing a "collapse to •••" rule.
    @ToolbarContentBuilder
    private var macToolbarItemsOverflow: some CustomizableToolbarContent {
        macItem(.more)
    }

    /// Low-frequency commands (import/export, full screen, history, theme, find,
    /// paste, outline, style). Off the bar by default, reachable from ••• and
    /// addable again from the toolbar customization palette.
    @ToolbarContentBuilder
    private var macToolbarItemsLowFrequency: some CustomizableToolbarContent {
        macItem(.share)
        macItem(.immersive)
        macItem(.outline)
        macItem(.style)
        macItem(.theme)
        macItem(.find)
        macItem(.history)
        macItem(.paste)
    }

    /// Trailing pair: 适应窗口 (addable) and the inspector capsule, which stays
    /// at the far right like the XMind sidebar switch.
    @ToolbarContentBuilder
    private var macToolbarItemsView: some CustomizableToolbarContent {
        macItem(.fit)
        macInspectorToggle
    }

    /// Right-top inspector switch (TD-007). One system toolbar item: the
    /// system paints its glass capsule and its pressed state, and
    /// `toolbarFloatingButton` draws nothing on top of it, so the item carries
    /// exactly one platter. Nothing here paints a gradient, a blur, or a
    /// shadow. The 34x28 label frame is the hit target the road map requires
    /// (>= 28x28) and keeps the glyph on the same baseline as the other bar
    /// items. It reuses the 样式 command for title and help, so no new strings
    /// or menu entries appear.
    private var macInspectorToggle: some CustomizableToolbarContent {
        ToolbarItem(id: "inspector.toggle", placement: .primaryAction) {
            Button {
                showInspector.toggle()
            } label: {
                Image(systemName: "sidebar.trailing")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 34, height: 28)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .appleGlassChrome(.toolbarFloatingButton)
            .accessibilityLabel(text(EditorToolbarCatalog.command(.style).title))
            .accessibilityHint(text(EditorToolbarCatalog.command(.style).help))
            .accessibilityIdentifier("inspector.toggle")
            .help(Text(verbatim: text(EditorToolbarCatalog.command(.style).help)))
        }
        .defaultCustomization(.visible)
    }
    #endif

    var body: some View {
        let _ = KeyLatencyProbe.shared.countEditorBody()
        KeyLatencyProbe.shared.timeBuild("editor") {
            editorPresentations
                .chromeTypography(language: settings.language)
        }
    }

    private var editorCore: some View {
        canvasStack
        .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        .navigationTitle("")
        #if os(macOS)
        .focusedSceneValue(\.florettaEditorCommands, editorMenuActions)
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .modifier(MacEditorWindowTitle(title: ""))
        .zenChrome(session.zen.chrome)
        .overlay(alignment: .topTrailing) {
            if session.zen.isActive && isExitAffordanceRevealed {
                Button {
                    hideZenExitAffordance()
                    session.exitZen()
                } label: {
                    Label("退出全屏沉浸", systemImage: "xmark")
                }
                .appleGlassChrome(.canvasFloatingButton)
                .accessibilityIdentifier("zen.exit")
                .padding(.top, 8)
                .padding(.trailing, 12)
            }
        }
        .onChange(of: session.zen.isActive) { _, isActive in
            if !isActive {
                hideZenExitAffordance()
            }
        }
        .onChange(of: regionDraftToken) { _, _ in
            syncRegionDrafts()
        }
        .onChange(of: regionMetric) { previous, _ in
            if let previous { commitRegionMetric(previous) }
        }
    }

    private var editorToolbar: some View {
        editorCore
            .inspector(isPresented: inspectorPresented) {
                inspectorBody
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 440)
            }
            .onAppear(perform: openInspectorForUITest)
            .toolbar {
                if session.zen.chrome.showsToolbar {
                    // A system toolbar item is already Liquid Glass: the bar
                    // paints the circular platter and owns the hit testing, and
                    // the 44pt frame keeps the target comfortable. The
                    // `.appleGlassChrome(.iconButton)` plate that used to sit
                    // inside this item was a second capsule on top of the bar's
                    // own — the double-glass bug the user reported on this
                    // button. Nothing is painted here any more; the system
                    // capsule is the only plate.
                    #if os(iOS)
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: onClose) {
                            Image(systemName: "chevron.backward")
                        }
                        .accessibilityLabel(text("返回"))
                        .accessibilityIdentifier("basicChain.back")
                        .help(Text(verbatim: text("返回导图列表")))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                    }
                    ToolbarSpacer(.fixed, placement: .cancellationAction)
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: beginRename) {
                            Text(verbatim: documentTitle)
                                .lineLimit(1)
                        }
                        .buttonStyle(.borderless)
                        .help(Text(verbatim: text("为这份导图重新命名")))
                        .accessibilityLabel(documentTitle)
                        .accessibilityHint(text("为这份导图重新命名"))
                        .accessibilityIdentifier("document.title")
                    }
                    .sharedBackgroundVisibility(.hidden)
                    #endif
                    #if !os(macOS)
                    ToolbarItemGroup(placement: .principal) {
                        if toolbarVisibleItems.contains(.undo) {
                            toolbarControl(.undo)
                                .appleGlassChrome(.toolbarFloatingButton)
                        }
                        if toolbarVisibleItems.contains(.redo) {
                            toolbarControl(.redo)
                                .appleGlassChrome(.toolbarFloatingButton)
                        }
                        if toolbarVisibleItems.contains(.delete) {
                            toolbarControl(.delete)
                                .appleGlassChrome(.toolbarFloatingButton)
                        }
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        if toolbarVisibleItems.contains(.insert) {
                            toolbarControl(.insert)
                                .appleGlassChrome(.toolbarFloatingButton)
                        }
                        #if os(iOS)
                        // Keep the inspector entry and the overflow as trailing
                        // siblings in this group so `editor.more` stays rightmost.
                        // A compact inspector is a sheet; after it is dismissed
                        // the user still needs a one-tap way back in.
                        Button {
                            // Toggle, same as the macOS 样式 command. Assigning
                            // true only left iPad regular-width with no way to
                            // close the trailing inspector (the dismiss handle
                            // is compact-sheet-only).
                            showInspector.toggle()
                        } label: {
                            Image(systemName: "paintbrush")
                        }
                        .accessibilityLabel(text("样式"))
                        .help(Text(verbatim: text("打开样式检查器，修改选中节点的外观")))
                        .accessibilityIdentifier("inspector.open")
                        #endif
                        toolbarControl(.more)
                    }
                    #endif
                }
            }
            #if os(macOS)
            .toolbar(id: "floretta.editor") {
                // Navigation identity must not follow selection/focus chrome.
                macToolbarItemsLeading
                if session.zen.chrome.showsToolbar {
                    macToolbarItemsPrimary
                    macToolbarItemsInsert
                    macToolbarItemsRelations
                    macToolbarItemsOverflow
                    macToolbarItemsLowFrequency
                    macToolbarItemsView
                }
            }
            #endif
            #if os(macOS)
            .toolbarBackground(.hidden, for: .windowToolbar)
            #else
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
    }

    private var editorEvents: some View {
        editorToolbar
            .onChange(of: session.viewMode) { _, mode in
                guard mode == .focus else { return }
                if session.focusNodeID == nil {
                    session.focusNodeID = session.keyboard.selectedNodeID ?? session.editingDocument.roots.first?.id
                }
            }
            .onChange(of: session.document) { _, _ in
                session.flushLiveViewport()
                onEdit(session.document)
            }
            .onAppear {
                camera.restore(session.document.viewport(forCanvas: session.document.clampedCanvasIndex))
            }
            .onChange(of: session.document.activeCanvasIndex) { _, _ in
                camera.restore(session.document.viewport(forCanvas: session.document.clampedCanvasIndex))
            }
            .onChange(of: session.canvasCameraToken) { _, _ in
                camera.restore(session.document.viewport(forCanvas: session.document.clampedCanvasIndex))
            }
            .background {
                CanvasViewportRelay(camera: camera) { viewport in
                    session.noteViewport(viewport.persisted)
                }
            }
        .onChange(of: session.zen.isActive) { _, active in
            syncFullScreen(active)
        }
        .onAppear {
            if session.zen.isActive { syncFullScreen(true) }
        }
            .onKeyPress(.escape) {
                session.handleEscape() ? .handled : .ignored
            }
            .contextMenu {
                ForEach(CanvasMenus.text, id: \.self) { item in
                    textContextMenuItem(item)
                }
            }
    }

    @ViewBuilder
    private func textContextMenuItem(_ item: String) -> some View {
        let symbol = switch item {
        case "剪切": "scissors"
        case "拷贝": "doc.on.doc"
        case "粘贴": "doc.on.clipboard"
        case "全选": "text.alignleft"
        case "拷贝样式": "paintbrush.pointed"
        default: "ellipsis"
        }
        let button = Button { runTextCommand(item) } label: {
            Label(text(item), systemImage: symbol)
        }
        .explained(textHelp(item))
        .disabled(CanvasMenus.textDisabled.contains(item) || (session.isMarkdownDocument && item == "拷贝样式"))
        switch item {
        case "剪切": button.keyboardShortcut("x", modifiers: .command)
        case "拷贝": button.keyboardShortcut("c", modifiers: .command)
        case "粘贴": button.keyboardShortcut("v", modifiers: .command)
        case "全选": button.keyboardShortcut("a", modifiers: .command)
        default: button
        }
    }

    private var editorExportActions: some View {
        editorEvents
            .fileExporter(
                isPresented: $showExport,
                document: exportFile,
                contentType: exportType,
                defaultFilename: exportName
            ) { result in
                switch result {
                case .success(let url):
                    if exportKind == "floretta" {
                        onSavedCopy(url)
                    }
                case .failure(let error):
                    exportError = error.localizedDescription
                }
            }
            .fileExporter(
                isPresented: $showUpgrade,
                document: upgradeFile,
                contentType: MarkdownUpgrade.contentType,
                defaultFilename: upgradeName
            ) { result in
                switch result {
                case .success(let url):
                    if let current = session.url,
                       MarkdownUpgrade.replacesOriginal(destination: url, original: current) {
                        exportError = "不能覆盖原来的 Markdown 文件。"
                        return
                    }
                    upgradedURL = url
                    onMarkdownUpgrade(url, .keepMarkdown)
                    askOpenUpgrade = true
                case .failure(let error):
                    exportError = error.localizedDescription
                }
            }
            .confirmationDialog(
                Text(verbatim: text("要打开新的 Floretta 文件吗？")),
                isPresented: $askOpenUpgrade,
                titleVisibility: .visible
            ) {
                Button(text("保持当前 Markdown"), role: .cancel) {}
                Button(text("打开新的 Floretta 文件")) {
                    if let upgradedURL {
                        onMarkdownUpgrade(upgradedURL, .openFloretta)
                    }
                }
            } message: {
                Text(verbatim: text("升级后的文件已保存。当前 Markdown 仍打开着。"))
            }
            .alert(Text(verbatim: text("无法导出")), isPresented: exportErrorPresented) {
                Button(text("好"), role: .cancel) {}
            } message: {
                Text(verbatim: FlorettaL10n.present(exportError ?? "", locale: settings.resolvedLocale))
            }
            .alert(Text(verbatim: text("重新命名")), isPresented: $showRename) {
                TextField(text("名称"), text: $renameText)
                Button(text("确定")) {
                    let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !title.isEmpty { session.document.title = title }
                }
                Button(text("取消"), role: .cancel) {}
            }
    }

    private var editorPresentations: some View {
        editorExportActions
        .sheet(isPresented: $showAbout) {
            AboutSheet()
        }
        .sheet(isPresented: $showShortcutHelp) {
            ShortcutsHelpSheet()
        }
            .sheet(isPresented: $showThemes) {
                BranchThemeSheet(themeID: session.document.themeID, language: settings.language) { id in
                    session.setBranchTheme(id)
                }
            }
            .fileImporter(
                isPresented: $showImageImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                importAttachment(result)
            }
            .fileImporter(
                isPresented: $showAttachmentImporter,
                allowedContentTypes: AppleFileTypes.importableContentTypes,
                allowsMultipleSelection: false
            ) { result in
                importAttachment(result)
            }
            .dropDestination(for: DroppedImage.self) { items, _ in
                guard session.acceptsAttachmentDrop else {
                    session.revealBlocked(MarkdownModePolicy.reason(.insertAttachment))
                    return false
                }
                guard let item = items.first else { return false }
                stageAttachment(item.url, ownsCopy: item.ownsCopy)
                return true
            }
            .confirmationDialog(text("放入附件？"), isPresented: insertDialogPresented, titleVisibility: .visible) {
                Button(text("放入")) { beginInsert() }
                Button(text("取消"), role: .cancel) { cancelInsert() }
            } message: {
                Text(verbatim: insertProposal.map { FlorettaL10n.attachmentConfirmation($0, locale: settings.resolvedLocale) } ?? "")
            }
            .alert(Text(verbatim: text("无法预览")), isPresented: previewAlertPresented) {
                Button(text("好"), role: .cancel) {}
            } message: {
                Text(verbatim: FlorettaL10n.present(previewPhase.alertMessage ?? "", locale: settings.resolvedLocale))
            }
            .sheet(isPresented: Binding(
                get: { mediaPlayer != nil && mediaPlayerKind == .video },
                set: { if !$0 { closeMediaPlayer() } }
            )) {
                if let mediaPlayer {
                    Group {
                        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                            if mediaPlayer.currentItem?.status == .failed {
                                ContentUnavailableView("视频无法播放", systemImage: "exclamationmark.triangle")
                                    .frame(minWidth: 320, minHeight: 180)
                            } else {
                                MediaVideoPlayer(player: mediaPlayer)
                                    .frame(minWidth: 320, minHeight: 180)
                            }
                        }
                    }
                    .padding()
                }
            }
            .background {
                #if os(macOS)
                MacQuickLookBridge(
                    url: previewURL,
                    title: previewPhase.ticket?.filename ?? "",
                    onMissing: { previewPhase = FilePreviewSession.fileDisappeared(previewPhase) },
                    onClose: { previewPhase = FilePreviewSession.userClosed(previewPhase) },
                    onUnavailable: { previewPhase = FilePreviewSession.unavailable() }
                )
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                #endif
            }
            #if os(iOS)
            .sheet(isPresented: previewSheetPresented) {
                if let previewURL {
                    IOSQuickLook(
                        url: previewURL,
                        title: previewPhase.ticket?.filename ?? "",
                        onMissing: { previewPhase = FilePreviewSession.fileDisappeared(previewPhase) },
                        onClose: { previewPhase = FilePreviewSession.userClosed(previewPhase) }
                    )
                }
            }
            #endif
            .sheet(isPresented: $showTagFilter) {
                TagFilterSheet(session: session, text: { self.text($0) }, locale: settings.resolvedLocale)
                    .accessibilityIdentifier("tagFilter.sheet")
            }
            .sheet(isPresented: $showHistory) {
                if let url = session.url {
                    SnapshotHistorySheet(session: session, url: url, text: { self.text($0) }, locale: settings.resolvedLocale)
                        .accessibilityIdentifier("snapshotHistory.sheet")
                }
            }
            .alert(Text(verbatim: text("查找")), isPresented: $showFind) {
                TextField(text("文字"), text: $findQuery)
                Button(text("查找")) {
                    if let id = CanvasEditCommands.find(in: session.editingDocument, query: findQuery) {
                        session.keyboard.selectedNodeID = id
                    } else {
                        exportError = "没有找到。"
                    }
                }
                Button(text("取消"), role: .cancel) {}
            }
    }

    private var canvasStack: some View {
        ZStack(alignment: .leading) {
            InfiniteCanvas(
                document: session.activeCanvasDocument,
                keyboard: $session.keyboard,
                camera: camera,
                clock: clock,
                fontMetrics: fontMetrics,
                focusNodeID: session.viewMode == .focus ? session.focusNodeID : nil,
                zenActive: session.zen.isActive,
                pointerMode: settings.pointerMode,
                onEscape: { session.handleEscape() },
                onConsumeBlankDoubleTap: { session.consumeBlankDoubleTap() },
                thumbnails: thumbnails,
                thumbnailCache: thumbnailCache,
                attachmentArchive: session.url,
                spillDirectory: thumbnailCache?.directory
                    .deletingLastPathComponent()
                    .appendingPathComponent("spill", isDirectory: true),
                attachmentEntries: session.attachmentCatalog.attachments,
                onPreviewFile: { nodeID, badge in
                    previewFile(nodeID: nodeID, badge: badge)
                },
                audioPlayer: mediaPlayerKind == .audio ? mediaPlayer : nil,
                audioNodeID: audioNodeID,
                onDismissAudio: closeMediaPlayer,
                tagFilter: session.tagFilter,
                persistsPlacement: !session.isMarkdownDocument,
                dictationToken: session.dictationToken,
                dictationReplacesPlaceholder: session.dictationReplacesPlaceholder,
                onChromeCommand: handleChromeCommand
            )
            .ignoresSafeArea(edges: .all)
            .simultaneousGesture(
                TapGesture().onEnded {
                    guard session.zen.isActive else { return }
                    revealZenExitAffordance()
                }
            )
            // The outline is a panel, not a column of the window: it sits in
            // this ZStack above `InfiniteCanvas`, so what it covers is canvas
            // pixels. `sidebarColumn` samples window content (`.withinWindow`)
            // for exactly that reason; sampling the window backdrop here is
            // what made it read as a solid grey plate. One plate only: this
            // modifier, plus `OutlineView` hiding its list's scroll
            // background, so no second material is stacked on the glass.
            if showOutline, session.zen.chrome.showsSidebar {
                outlinePanel
                    .frame(width: outlineWide ? nil : 300)
                    .frame(maxWidth: outlineWide ? .infinity : 300, maxHeight: .infinity)
                    .appleGlassChrome(.sidebarColumn)
            }
        }
        .overlay(alignment: .top) {
            if !session.zen.isActive {
                VStack(spacing: 8) {
                    if session.markdownBannerVisible {
                        markdownBanner
                    }
                    if let warning = session.visibleMarkdownWarning {
                        markdownNotice(warning, identifier: "markdown.warning") {
                            session.dismissMarkdownWarning()
                        }
                    }
                    if let blocked = session.blockedNotice {
                        markdownNotice(blocked, identifier: "markdown.blocked") {
                            session.dismissBlockedNotice()
                        }
                    }
                    if session.tagFilter.isActive {
                        tagFilterBanner
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            bottomBarRow
        }
    }

    /// The two bottom capsules on one line: the sheet capsule (TD-002) on the
    /// leading edge, the status capsule (TD-003) on the trailing edge. Both
    /// plates draw at `EditorStatusBarChrome.controlMinHeight` and hang from the
    /// one `bottomInset` applied here, so `alignment: .bottom` is the whole
    /// alignment: neither side carries a compensating padding.
    ///
    /// The status capsule is fixed to its content and keeps a higher layout
    /// priority, so it is never squeezed or pushed off screen. What gives way
    /// first is the sheet name (truncated with an ellipsis), then the sheet
    /// capsule's divider.
    private var bottomBarRow: some View {
        HStack(alignment: .bottom, spacing: EditorStatusBarChrome.capsuleGap) {
            if showsCanvasTabs {
                canvasTabBar
            }
            if session.zen.chrome.showsStatusBar {
                Spacer(minLength: EditorStatusBarChrome.capsuleGap)
                EditorStatusStrip(
                    session: session,
                    camera: camera,
                    census: statusCensus,
                    language: settings.language,
                    showOutline: $showOutline,
                    pointerMode: $settings.pointerMode
                )
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { width in
                    statusCapsuleWidth = width
                }
                .layoutPriority(1)
            }
        }
        .padding(.horizontal, EditorStatusBarChrome.horizontalInset)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            bottomRowWidth = width
        }
        .padding(.bottom, EditorStatusBarChrome.bottomInset)
        .safeAreaPadding(.bottom)
        .accessibilityIdentifier("editor.bottomBar")
        // Renaming a sheet hangs off the row, not the capsule: the alert is one
        // more modifier on the smallest enclosing view, and the capsule stays a
        // single short type. Behaviour is unchanged — the menu still raises the
        // same alert with the same field and buttons.
        .alert(Text(verbatim: text("重新命名")), isPresented: $showCanvasRename) {
            TextField(text("名称"), text: $canvasRenameText)
            Button(text("确定")) {
                session.renameCanvas(at: canvasRenameIndex, to: canvasRenameText)
            }
            Button(text("取消"), role: .cancel) {}
        }
    }

    private func revealZenExitAffordance() {
        exitAffordanceTask?.cancel()
        isExitAffordanceRevealed = true
        exitAffordanceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            isExitAffordanceRevealed = false
            exitAffordanceTask = nil
        }
    }

    private func hideZenExitAffordance() {
        exitAffordanceTask?.cancel()
        exitAffordanceTask = nil
        isExitAffordanceRevealed = false
    }

    /// The sheet capsule stays visible with a single sheet, so 新建画布 always has a
    /// permanent entry point. Markdown documents and Zen hide the bottom chrome.
    private var showsCanvasTabs: Bool {
        !session.isMarkdownDocument && !session.zen.isActive
    }

    /// Divider policy for the sheet capsule, from measured widths only.
    private var showsSheetDivider: Bool {
        EditorBottomBarLayout.showsSheetDivider(
            rowWidth: bottomRowWidth,
            statusWidth: statusCapsuleWidth
        )
    }

    /// Width the sheet name may claim on this window. Comes from the measured
    /// bottom row, so the cap follows the window and no second number is kept
    /// here.
    private var canvasTitleWidthLimit: CGFloat {
        EditorBottomBarLayout.canvasTitleWidthLimit(rowWidth: bottomRowWidth)
    }

    /// XMind's sheet capsule: the current sheet name behind a `▾` menu, then `＋`.
    ///
    /// One capsule instead of a row of tabs. Switching sheets, rename, copy, paste,
    /// duplicate, delete, new sheet, and 画布另存为 all live in the menu, which is
    /// where XMind puts them too. The capsule is only as wide as its content and
    /// shares the bottom row with the status capsule.
    ///
    /// The name is centred, truncates in the middle so the `.floretta` extension
    /// survives, and is capped at `EditorBottomBarLayout.canvasTitleWidthLimit`
    /// — a share of the measured row, not a fixed 240 pt box. A flexible frame
    /// could not do this: `.frame(maxWidth:)` fills its cap, which stretched the
    /// capsule even for a short name. `CappedWidthLayout` proposes the cap and
    /// still reports the name's own width, so the capsule hugs short names and
    /// a 60-character name stays inside the cap instead of pushing the row out.
    private var canvasTabBar: some View {
        CanvasSheetCapsule(
            title: currentCanvasTitle,
            titleWidthLimit: canvasTitleWidthLimit,
            showsSheetDivider: showsSheetDivider,
            sheetTitles: (0..<session.document.canvasCount).map { sheetTitle(at: $0) },
            currentIndex: currentCanvasIndex,
            canPaste: session.hasStagedCanvas,
            canDelete: session.document.canvasCount > 1,
            canUndoDelete: session.restorableCanvasRemoval != nil,
            language: settings.language,
            onActivate: { index in
                session.activateCanvas(index, viewport: camera.viewport.persisted)
            },
            onRename: beginCanvasRename,
            onCopy: {
                session.copyActiveCanvas(viewport: camera.viewport.persisted)
            },
            onPaste: {
                session.pasteCanvas(
                    viewport: camera.viewport.persisted,
                    title: copyCanvasTitle(suffix: text("副本"))
                )
            },
            onDuplicate: {
                session.duplicateCanvas(
                    viewport: camera.viewport.persisted,
                    title: copyCanvasTitle(suffix: text("副本"))
                )
            },
            onDelete: {
                session.removeCanvas(at: currentCanvasIndex, viewport: camera.viewport.persisted)
            },
            onUndoDelete: {
                session.restoreRemovedCanvas()
            },
            onAdd: {
                session.addCanvas(viewport: camera.viewport.persisted)
            },
            onSaveAs: saveActiveCanvasAs
        )
    }

    /// The sheet capsule as one named type.
    ///
    /// It lives outside `DocumentEditor` so the capsule is a single name in the
    /// type of `canvasTabBar`, of `bottomBarRow`, and of `editorCore`, instead of
    /// the whole `Menu` + `ForEach` + `alert` chain being nested into each of
    /// them. That nesting is what the Release runtime could not demangle:
    /// `__swift_instantiateConcreteTypeFromMangledNameV2` recursed through
    /// `decodeMangledType` until the thread stack overflowed ("Thread stack size
    /// exceeded", EXC_BAD_ACCESS) while laying out `canvasTabBar`. Release
    /// mangled names carry more of the chain than Debug ones, which is why only
    /// the shipped build crashed.
    ///
    /// Only data and closures cross the boundary — never a `@ViewBuilder`
    /// parameter, which would nest the caller's view type back into this one.
    /// The rename alert is not here: it hangs off `bottomBarRow`, one level up.
    private struct CanvasSheetCapsule: View {
        var title: String
        var titleWidthLimit: CGFloat
        var showsSheetDivider: Bool
        var sheetTitles: [String]
        var currentIndex: Int
        var canPaste: Bool
        var canDelete: Bool
        var canUndoDelete: Bool
        var language: AppLanguage
        var onActivate: (Int) -> Void
        var onRename: () -> Void
        var onCopy: () -> Void
        var onPaste: () -> Void
        var onDuplicate: () -> Void
        var onDelete: () -> Void
        var onUndoDelete: () -> Void
        var onAdd: () -> Void
        var onSaveAs: () -> Void

        var body: some View {
            HStack(spacing: 2) {
                Menu {
                    sheetMenu
                } label: {
                    CanvasSheetNameLabel(title: title, titleWidthLimit: titleWidthLimit)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .help(Text(verbatim: text("切换、重命名或删除画布")))
                .accessibilityLabel(Text(verbatim: title))
                .accessibilityHint(text("切换、重命名或删除画布"))
                .accessibilityIdentifier("canvas.menu")

                if showsSheetDivider {
                    Divider()
                        .frame(height: 18)
                }

                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: EditorStatusBarChrome.chromeFontSize, weight: .regular))
                        .frame(width: 34, height: EditorStatusBarChrome.controlMinHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Text(verbatim: text("新建画布")))
                .accessibilityLabel(text("新建画布"))
                .accessibilityIdentifier("canvas.add")
            }
            .controlSize(.small)
            .padding(.horizontal, 4)
            .frame(minHeight: EditorStatusBarChrome.controlMinHeight)
            .appleGlassChrome(.bottomBarCapsule)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("canvas.tabs")
        }

        /// The `▾` menu. A capability that does not exist is not drawn as a dead
        /// row: 删除 needs a second sheet, 粘贴 needs a copied one.
        @ViewBuilder
        private var sheetMenu: some View {
            ForEach(sheetTitles.indices, id: \.self) { index in
                Button {
                    onActivate(index)
                } label: {
                    if index == currentIndex {
                        Label(sheetTitles[index], systemImage: "checkmark")
                    } else {
                        Text(verbatim: sheetTitles[index])
                    }
                }
                .accessibilityIdentifier("canvas.tab.\(index)")
            }

            Divider()

            Button(action: onRename) {
                Label(text("重新命名画布"), systemImage: "pencil")
            }
            .accessibilityIdentifier("canvas.menu.rename")

            Button(action: onCopy) {
                Label(text("拷贝画布"), systemImage: "doc.on.doc")
            }
            .accessibilityIdentifier("canvas.menu.copy")

            if canPaste {
                Button(action: onPaste) {
                    Label(text("粘贴画布"), systemImage: "doc.on.clipboard")
                }
                .accessibilityIdentifier("canvas.menu.paste")
            }

            Button(action: onDuplicate) {
                Label(text("复制画布"), systemImage: "plus.square.on.square")
            }
            .accessibilityIdentifier("canvas.menu.duplicate")

            if canDelete {
                Button(role: .destructive, action: onDelete) {
                    Label(text("删除画布"), systemImage: "trash")
                }
                .accessibilityIdentifier("canvas.menu.delete")
            }

            if canUndoDelete {
                Button(action: onUndoDelete) {
                    Label(text("撤销删除画布"), systemImage: "arrow.uturn.backward")
                }
                .accessibilityIdentifier("canvas.menu.undoDelete")
            }

            Button(action: onAdd) {
                Label(text("新建画布"), systemImage: "plus.rectangle.on.rectangle")
            }
            .accessibilityIdentifier("canvas.menu.add")

            Button(action: onSaveAs) {
                Label(text("画布另存为…"), systemImage: "square.and.arrow.down.on.square")
            }
            .accessibilityIdentifier("canvas.menu.saveAs")
        }

        private func text(_ key: String) -> String {
            FlorettaL10n.string(key, language: language)
        }
    }

    /// The `▾` label: the sheet name in a capped slot, then the chevron.
    ///
    /// Its own type for the same reason as `CanvasSheetCapsule`: the name text,
    /// the capped slot, and the glyph stay one short name in the capsule's type.
    /// The name is centred and truncates in the middle so the `.floretta`
    /// extension survives. `CappedWidthLayout` proposes the cap and still
    /// reports the name's own width, so the capsule hugs a short name and a
    /// 60-character name stays inside the cap instead of widening the row.
    private struct CanvasSheetNameLabel: View {
        var title: String
        var titleWidthLimit: CGFloat

        var body: some View {
            HStack(spacing: 4) {
                CappedWidthLayout(maxWidth: titleWidthLimit) {
                    Text(verbatim: title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.center)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .frame(minHeight: EditorStatusBarChrome.controlMinHeight)
            .contentShape(Rectangle())
        }
    }

    private var currentCanvasIndex: Int { session.document.clampedCanvasIndex }

    /// Sheet names are user text, so they never go through the string table.
    private func sheetTitle(at index: Int) -> String {
        let title = session.document.canvasTitle(at: index)
        return title.isEmpty ? "未命名" : title
    }

    private var currentCanvasTitle: String { sheetTitle(at: currentCanvasIndex) }

    /// 「<当前画布> 副本」, numbered when that name is taken.
    private func copyCanvasTitle(suffix: String) -> String {
        session.document.uniqueCanvasTitle(basedOn: currentCanvasTitle, suffix: suffix)
    }

    private func beginCanvasRename() {
        canvasRenameIndex = currentCanvasIndex
        canvasRenameText = session.document.canvasTitle(at: currentCanvasIndex)
        showCanvasRename = true
    }

    /// 画布另存为…: writes this sheet alone as a new `.floretta` file.
    /// The open document keeps its own URL — this is a copy, not 另存为 for the map,
    /// so the export kind is not "floretta" and the save callback is not run.
    private func saveActiveCanvasAs() {
        session.prepareToSave()
        let index = currentCanvasIndex
        let title = currentCanvasTitle
        var canvas = session.document.isolatedCanvas(at: index)
        canvas.title = title
        do {
            exportKind = "canvas"
            exportType = FlorettaFileTypes.contentType(forExport: "floretta")
            exportName = exportFilename(title: title, kind: "floretta")
            if !AttachmentReferences.hashes(in: canvas).isEmpty, let archive = session.url {
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(UUID().uuidString).floretta")
                _ = try FlorettaStreamingDocument.save(
                    document: canvas,
                    to: destination,
                    files: FoundationStreamingFiles(),
                    copyingAssetsFrom: archive
                )
                exportFile = ExportFile(data: Data(), fileURL: destination)
            } else {
                exportFile = ExportFile(data: try SharePayload.bytes(for: "floretta", document: canvas))
            }
            presentPreparedExport()
        } catch {
            exportError = error.localizedDescription
        }
    }


    private var tagFilterBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "tag.fill")
            Text(verbatim: tagFilterCaption)
                .lineLimit(1)
            Button {
                session.tagFilter.choice = nil
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel(text("清除筛选"))
            .accessibilityIdentifier("tagFilter.clear")
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .appleGlassChrome(.bottomBarCapsule)
        .padding(.top, session.zen.isActive ? 56 : 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tagFilter.banner")
    }

    private var tagFilterCaption: String {
        switch session.tagFilter.choice {
        case .label(let label):
            return FlorettaL10n.format("正在筛选「%@」", locale: settings.resolvedLocale, arguments: [label])
        case .marker(let markerId):
            return FlorettaL10n.format(
                "正在筛选「%@」",
                locale: settings.resolvedLocale,
                arguments: [TagMarkerTitle.text(markerId, text: { self.text($0) }, locale: settings.resolvedLocale)]
            )
        case nil:
            return ""
        }
    }

    private var outlinePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(verbatim: text("大纲")).font(.headline)
                Spacer()
                Button {
                    outlineWide.toggle()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .explained("让大纲占满或恢复原来的宽度")
                .appleGlassChrome(.iconButton)
                Button {
                    showOutline = false
                } label: {
                    Image(systemName: "xmark")
                }
                .explained("关闭大纲")
                .appleGlassChrome(.iconButton)
            }
            .padding(12)
            if session.isMarkdownDocument {
                Text(verbatim: text(MarkdownModePolicy.reason(.collapse)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .accessibilityHint(text(MarkdownModePolicy.reason(.collapse)))
            }
            OutlineView(
                document: session.activeCanvasDocument,
                keyboard: $session.keyboard,
                tagFilter: session.tagFilter,
                locksCollapse: session.isMarkdownDocument,
                onChromeCommand: handleChromeCommand
            )
        }
        .accessibilityIdentifier("editor.outline")
    }

    private var markdownBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: text(MarkdownModeCopy.title))
                .font(.headline)
            Text(verbatim: text(MarkdownModeCopy.explanation))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .appleGlassChrome(.floatingPanel)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("markdown.mode.banner")
        .padding(.top, session.zen.isActive ? 56 : 0)
    }

    private func markdownNotice(_ message: String, identifier: String, dismiss: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(verbatim: FlorettaL10n.present(message, locale: settings.resolvedLocale))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(text("关闭提示"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .appleGlassChrome(.floatingPanel)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
        .padding(.horizontal, 12)
    }

    private var documentTitle: String {
        session.document.title.isEmpty ? "未命名" : session.document.title
    }

    private func text(_ key: String) -> String {
        FlorettaL10n.string(key, language: settings.language)
    }

    private var branchScheme: MapColorScheme {
        colorScheme == .dark ? .dark : .light
    }

    private func beginRename() {
        renameText = session.document.title
        showRename = true
    }

    private var toolbarContext: EditorToolbarContext {
        EditorToolbarContext(
            isMarkdownDocument: session.isMarkdownDocument,
            isComposing: session.keyboard.isComposing,
            hasSelectedTopic: session.keyboard.selectedNodeID != nil,
            canEncloseSelection: session.editingDocument.canEnclose(session.keyboard.selectedNodeID),
            canOpenSnapshotHistory: session.canOpenSnapshotHistory
        )
    }

    #if os(macOS)
    private var editorMenuActions: FlorettaEditorMenuActions {
        let eligible = Set(EditorToolbarCommandID.allCases.filter {
            MacMenuShortcutCatalog.isEnabled($0, in: toolbarContext)
        })
        let selectedID = session.keyboard.selectedNodeID
        let hasSelection = selectedID != nil
        let ids: [EditorToolbarCommandID] = [
            .child, .sibling, .freeNode, .sticky, .image, .attachment,
            .summary, .boundary, .region, .outline, .fit, .mapMode, .focusMode,
            .immersive, .style, .theme, .about, .find, .png, .pdf, .markdownExport, .textBundle, .saveFloretta, .xmind
        ]
        var actions = FlorettaEditorMenuActions(
            perform: Dictionary(uniqueKeysWithValues: ids.map { id in (id, { perform(id) }) }),
            enabled: eligible
        )
        actions.hasSelectedTopic = hasSelection
        actions.hasEditableSelection = hasSelection && !session.isMarkdownDocument
        actions.showShortcutHelp = { showShortcutHelp = true }
        actions.performShortcut = { command in
            handleChromeCommand(command)
            session.performShortcut(command)
        }
        let allowsAppearanceWrites = !session.isMarkdownDocument
        actions.linkTargets = session.editingDocument.linkTargets(excluding: selectedID).map { target in
            .init(title: target.text.isEmpty ? "未命名" : target.text) {
                session.linkSelectedTopic(to: target.id)
            }
        }
        actions.setFont = { font in
            guard let selectedID else { return }
            session.editActive { document in
                _ = InspectorStyle.apply(.fontDesign(font), nodeID: selectedID, document: &document, allowsAppearanceWrites: allowsAppearanceWrites)
            }
        }
        actions.setFontSize = { size in
            guard let selectedID else { return }
            session.editActive { document in
                _ = InspectorStyle.apply(.fontSize(size), nodeID: selectedID, document: &document, allowsAppearanceWrites: allowsAppearanceWrites)
            }
        }
        actions.toggleTextFlag = { flag in
            guard let selectedID else { return }
            let current = InspectorStyle.isOn(flag, style: session.editingDocument.node(selectedID)?.style)
            session.editActive { document in
                _ = InspectorStyle.apply(.flag(flag, !current), nodeID: selectedID, document: &document, allowsAppearanceWrites: allowsAppearanceWrites)
            }
        }
        actions.shortcuts = [
            .fit: KeyboardShortcut("0", modifiers: .command),
            .find: KeyboardShortcut("f", modifiers: .command)
        ]
        actions.zoomIn = { camera.stepZoom(1) }
        actions.zoomOut = { camera.stepZoom(-1) }
        actions.zoomActual = { camera.resetZoom() }
        actions.isZenActive = session.zen.isActive
        actions.exitZen = { session.exitZen() }
        return actions
    }
    #endif

    private var toolbarWidthClass: EditorToolbarWidthClass {
        #if os(macOS)
        return .regular
        #else
        return horizontalSizeClass == .compact ? .compact : .regular
        #endif
    }

    private var toolbarVisibleItems: [EditorToolbarCommandID] {
        EditorToolbarLayout.visibleItems(for: toolbarWidthClass)
    }

    /// One census read for the status capsule. Same cache as before; the editor
    /// still counts topics, words, and characters in exactly one place.
    private var statusCensus: TopicTitleCensus {
        KeyLatencyProbe.shared.timeCensus {
            topicCensus.census(of: session.editingDocument)
        }
    }

    private func commandLabel(
        _ id: EditorToolbarCommandID,
        surface: EditorCommandSurface,
        accessibilityIdentifier: String? = nil
    ) -> EditorCommandLabel {
        let command = EditorToolbarCatalog.command(id)
        return EditorCommandLabel(
            title: text(command.title),
            symbol: command.symbol,
            display: EditorToolbarCatalog.display(on: surface),
            accessibilityIdentifier: accessibilityIdentifier
        )
    }

    private func commandHelp(_ id: EditorToolbarCommandID) -> String {
        if id == .history {
            return snapshotHistoryHelp
        }
        if session.isMarkdownDocument, let control = markdownBlockedControl(id) {
            return MarkdownModePolicy.reason(control)
        }
        return EditorToolbarCatalog.command(id).help
    }

    private func markdownBlockedControl(_ id: EditorToolbarCommandID) -> MarkdownBlockedControl? {
        switch id {
        case .freeNode: return .freeNode
        case .sticky: return .sticky
        case .link: return .relationship
        case .summary: return .summary
        case .boundary: return .boundary
        case .region: return .region
        case .image: return .insertImage
        case .attachment: return .insertAttachment
        case .style: return .nodeColor
        case .theme: return .themeColor
        case .tagFilter: return .tags
        default: return nil
        }
    }

    private func accessibilityIdentifier(for id: EditorToolbarCommandID) -> String? {
        switch id {
        case .undo: return "smoke.undo"
        case .redo: return "smoke.redo"
        case .delete: return "smoke.delete"
        case .share: return "share.menu"
        case .child: return "smoke.insert.child"
        case .sibling: return "smoke.insert.sibling"
        case .immersive: return "smoke.zen.enter"
        case .saveFloretta: return "smoke.save.floretta"
        case .png: return "smoke.export.png"
        case .pdf: return "smoke.export.pdf"
        case .markdownExport: return "smoke.export.markdown"
        case .importFile: return "smoke.import.file"
        case .mm: return "smoke.export.mm"
        case .opml: return "smoke.export.opml"
        case .dictation: return "insert.dictation"
        case .region: return "insert.region"
        case .mapMode: return "view.mode.map"
        case .focusMode: return "view.mode.focus"
        case .newCanvas: return "canvas.tab.add"
        case .style: return "inspector.open"
        case .theme: return "theme.menu"
        case .tagFilter: return "tagFilter.open"
        case .insert: return "editor.insert"
        case .attachment: return "insert.attachment"
        case .outline: return "outline.open"
        case .summary: return "insert.summary"
        case .boundary: return "insert.boundary"
        case .history: return "snapshotHistory.menu"
        case .upgrade: return "markdown.upgrade"
        case .more: return "editor.more"
        default: return nil
        }
    }

    private func commandMenuButton(_ id: EditorToolbarCommandID, action: @escaping () -> Void) -> some View {
        let helpText = commandHelp(id)
        let identifier = accessibilityIdentifier(for: id)
        return Button(action: action) {
            commandLabel(id, surface: .expandedMenu, accessibilityIdentifier: identifier)
        }
        .disabled(!EditorToolbarCatalog.isEnabled(id, in: toolbarContext))
        .help(Text(verbatim: text(helpText)))
        .accessibilityHint(text(helpText))
        .modifier(CommandAccessibilityIdentifier(identifier: identifier))
    }

    private func commandToolbarButton(_ id: EditorToolbarCommandID, action: @escaping () -> Void) -> some View {
        let helpText = commandHelp(id)
        return Button(action: action) {
            commandLabel(id, surface: .toolbar)
        }
        .disabled(!EditorToolbarCatalog.isEnabled(id, in: toolbarContext))
        .help(Text(verbatim: text(helpText)))
        .accessibilityLabel(text(EditorToolbarCatalog.command(id).title))
        .modifier(CommandAccessibilityIdentifier(identifier: accessibilityIdentifier(for: id)))
    }

    @ViewBuilder
    private func toolbarControl(_ id: EditorToolbarCommandID) -> some View {
        switch EditorToolbarCatalog.command(id).kind {
        case .pulldown:
            switch id {
            case .insert: insertMenu
            case .share: shareMenu
            case .more: moreMenu
            default: EmptyView()
            }
        case .submenu:
            switch id {
            case .link: linkCommandMenu(surface: .toolbar)
            case .viewMode: EmptyView()
            default: EmptyView()
            }
        case .button:
            commandToolbarButton(id) { perform(id) }
        }
    }

    #if os(macOS)
    private func macItem(_ id: EditorToolbarCommandID) -> some CustomizableToolbarContent {
        let command = EditorToolbarCatalog.command(id)
        let placement: ToolbarItemPlacement = command.placement == EditorToolbarPlacement.principal ? .principal : .primaryAction
        let visibility: Visibility = command.customization == EditorCommandCustomization.visible ? .visible : .hidden
        return ToolbarItem(id: id.rawValue, placement: placement) {
            // Pulldowns already wear one plate. A second GlassEffectContainer
            // inside the item publishes another toolbar preference during
            // layout, and that measurement does not converge.
            Group {
                switch command.kind {
                case .button:
                    toolbarControl(id)
                        .appleGlassChrome(.toolbarFloatingButton)
                case .pulldown, .submenu:
                    toolbarControl(id)
                }
            }
            .accessibilityLabel(text(command.title))
        }
        .defaultCustomization(visibility)
    }
    #endif

    private var insertMenu: some View {
        Menu {
            ForEach(EditorToolbarCatalog.menu(.insert), id: \.self) { id in
                insertRow(id)
            }
        } label: {
            commandLabel(.insert, surface: .toolbar)
        }
        .accessibilityLabel(text(EditorToolbarCatalog.command(.insert).title))
        .accessibilityIdentifier("editor.insert")
        .help(Text(verbatim: text(EditorToolbarCatalog.command(.insert).help)))
        .appleGlassChrome(.toolbarFloatingButton)
    }

    @ViewBuilder
    private func insertRow(_ id: EditorToolbarCommandID) -> some View {
        if id == .link {
            linkCommandMenu(surface: .expandedMenu)
        } else {
            commandMenuButton(id) { perform(id) }
        }
    }

    private func linkCommandMenu(surface: EditorCommandSurface) -> some View {
        Menu {
            let source = session.keyboard.selectedNodeID
            let targets = session.editingDocument.linkTargets(excluding: source)
            if targets.isEmpty {
                Button(text("没有其他节点")) {}
                    .disabled(true)
            }
            ForEach(targets) { target in
                Button {
                    session.linkSelectedTopic(to: target.id)
                } label: {
                    Label(target.text.isEmpty ? "未命名" : target.text, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
            }
        } label: {
            commandLabel(.link, surface: surface)
        }
        .disabled(!EditorToolbarCatalog.isEnabled(.link, in: toolbarContext))
        .help(Text(verbatim: text(commandHelp(.link))))
        .accessibilityHint(text(commandHelp(.link)))
    }

    @ViewBuilder
    private var shareMenu: some View {
        #if os(iOS)
        IdentifiedSystemMenuButton(
            symbol: EditorToolbarCatalog.command(.share).symbol,
            accessibilityIdentifier: "share.menu",
            accessibilityLabel: text(EditorToolbarCatalog.command(.share).title),
            help: text(EditorToolbarCatalog.command(.share).help),
            makeMenu: { makeShareUIMenu() }
        )
        .help(Text(verbatim: text(EditorToolbarCatalog.command(.share).help)))
        .appleGlassChrome(.toolbarFloatingButton)
        #else
        Menu {
            ForEach(EditorToolbarCatalog.menu(.share), id: \.self) { id in
                shareRow(id)
            }
        } label: {
            commandLabel(.share, surface: .toolbar)
        }
        .accessibilityLabel(text(EditorToolbarCatalog.command(.share).title))
        .accessibilityIdentifier("share.menu")
        .help(Text(verbatim: text(EditorToolbarCatalog.command(.share).help)))
        .appleGlassChrome(.toolbarFloatingButton)
        #endif
    }

    @ViewBuilder
    private func shareRow(_ id: EditorToolbarCommandID) -> some View {
        switch id {
        case .upgrade:
            if session.isMarkdownDocument {
                commandMenuButton(id) { perform(id) }
            }
        case .saveFloretta:
            if !session.isMarkdownDocument {
                commandMenuButton(id) { perform(id) }
            }
        case .printMap:
            #if os(macOS)
            commandMenuButton(id) { perform(id) }
            #else
            EmptyView()
            #endif
        default:
            commandMenuButton(id) { perform(id) }
        }
    }

    @ViewBuilder
    private var moreMenu: some View {
        #if os(iOS)
        IdentifiedSystemMenuButton(
            symbol: EditorToolbarCatalog.command(.more).symbol,
            accessibilityIdentifier: "editor.more",
            accessibilityLabel: text(EditorToolbarCatalog.command(.more).title),
            help: text(EditorToolbarCatalog.command(.more).help),
            makeMenu: { makeOverflowUIMenu() }
        )
        .help(Text(verbatim: text(EditorToolbarCatalog.command(.more).help)))
        .appleGlassChrome(.toolbarFloatingButton)
        #else
        Menu {
            // TD-006: the ••• menu never repeats a command the bar already
            // shows. Every row below falls back into this menu exactly when
            // `EditorToolbarLayout` keeps that command off the bar, so compact
            // widths still reach everything.
            if !toolbarVisibleItems.contains(.insert) {
                insertOverflowSubmenu
            }
            if !toolbarVisibleItems.contains(.share) {
                shareOverflowSubmenu
            }
            if !toolbarVisibleItems.contains(.undo) {
                commandMenuButton(.undo) { perform(.undo) }
            }
            if !toolbarVisibleItems.contains(.redo) {
                commandMenuButton(.redo) { perform(.redo) }
            }
            if !toolbarVisibleItems.contains(.delete) {
                commandMenuButton(.delete) { perform(.delete) }
            }
            if !toolbarVisibleItems.contains(.immersive) {
                commandMenuButton(.immersive) { perform(.immersive) }
            }
            overflowAlwaysCommandButton(.mapMode)
            overflowAlwaysCommandButton(.focusMode)
            overflowAlwaysCommandButton(.newCanvas)
            ForEach(overflowMenuCommands, id: \.self) { id in
                moreRow(id)
            }
        } label: {
            commandLabel(.more, surface: .toolbar)
                .accessibilityIdentifier("editor.more")
        }
        .accessibilityLabel(text(EditorToolbarCatalog.command(.more).title))
        .accessibilityIdentifier("editor.more")
        .help(Text(verbatim: text(EditorToolbarCatalog.command(.more).help)))
        .appleGlassChrome(.toolbarFloatingButton)
        #endif
    }

    /// `menu(.more)` minus whatever the bar already shows. This is the whole
    /// de-duplication rule; no platform-specific list is kept here.
    private var overflowMenuCommands: [EditorToolbarCommandID] {
        let onBar = Set(toolbarVisibleItems)
        return EditorToolbarCatalog.menu(.more).filter { !onBar.contains($0) }
    }

    private var insertOverflowSubmenu: some View {
        Menu {
            ForEach(EditorToolbarCatalog.menu(.insert), id: \.self) { id in
                insertRow(id)
            }
        } label: {
            commandLabel(.insert, surface: .expandedMenu)
        }
        .accessibilityIdentifier("editor.insert")
        .help(Text(verbatim: text(EditorToolbarCatalog.command(.insert).help)))
    }

    private var shareOverflowSubmenu: some View {
        Menu {
            ForEach(EditorToolbarCatalog.menu(.share), id: \.self) { id in
                shareRow(id)
            }
        } label: {
            commandLabel(.share, surface: .expandedMenu, accessibilityIdentifier: "share.menu")
        }
        .accessibilityIdentifier("share.menu")
        .help(Text(verbatim: text(EditorToolbarCatalog.command(.share).help)))
    }

    @ViewBuilder
    private func moreRow(_ id: EditorToolbarCommandID) -> some View {
        commandMenuButton(id) { perform(id) }
    }

    private func overflowAlwaysCommandButton(_ id: EditorToolbarCommandID) -> some View {
        Button { perform(id) } label: {
            commandLabel(id, surface: .expandedMenu, accessibilityIdentifier: accessibilityIdentifier(for: id))
        }
        .help(Text(verbatim: text(commandHelp(id))))
        .accessibilityHint(text(commandHelp(id)))
        .disabled(!EditorToolbarCatalog.isEnabled(id, in: toolbarContext))
        .modifier(CommandAccessibilityIdentifier(identifier: accessibilityIdentifier(for: id)))
    }


    #if os(iOS)
    private func makeOverflowUIMenu() -> UIMenu {
        var children: [UIMenuElement] = []
        if !toolbarVisibleItems.contains(.insert) {
            children.append(makeInsertUIMenu())
        }
        if !toolbarVisibleItems.contains(.share) {
            children.append(makeShareUIMenu())
        }
        for id in [EditorToolbarCommandID.undo, .redo, .delete, .immersive] where !toolbarVisibleItems.contains(id) {
            children.append(commandUIAction(id))
        }
        children.append(overflowAlwaysCommandUIAction(.mapMode))
        children.append(overflowAlwaysCommandUIAction(.focusMode))
        children.append(overflowAlwaysCommandUIAction(.newCanvas))
        for id in overflowMenuCommands {
            children.append(commandUIAction(id))
        }
        return UIMenu(children: children)
    }

    private func makeShareUIMenu() -> UIMenu {
        let command = EditorToolbarCatalog.command(.share)
        let children = EditorToolbarCatalog.menu(.share).compactMap { id -> UIAction? in
            switch id {
            case .upgrade:
                guard session.isMarkdownDocument else { return nil }
            case .saveFloretta:
                guard !session.isMarkdownDocument else { return nil }
            case .printMap:
                return nil
            default:
                break
            }
            return commandUIAction(id)
        }
        let menu = UIMenu(
            title: text(command.title),
            image: UIImage(systemName: command.symbol),
            identifier: UIMenu.Identifier("share.menu"),
            children: children
        )
        menu.accessibilityIdentifier = "share.menu"
        return menu
    }

    private func makeInsertUIMenu() -> UIMenu {
        let command = EditorToolbarCatalog.command(.insert)
        let children: [UIMenuElement] = EditorToolbarCatalog.menu(.insert).map { id in
            id == .link ? makeLinkUIMenu() : commandUIAction(id)
        }
        let menu = UIMenu(
            title: text(command.title),
            image: UIImage(systemName: command.symbol),
            identifier: UIMenu.Identifier("editor.insert"),
            children: children
        )
        menu.accessibilityIdentifier = "editor.insert"
        return menu
    }

    private func makeLinkUIMenu() -> UIMenu {
        let command = EditorToolbarCatalog.command(.link)
        let source = session.keyboard.selectedNodeID
        let targets = session.editingDocument.linkTargets(excluding: source)
        let disabled = !EditorToolbarCatalog.isEnabled(.link, in: toolbarContext)
        let children: [UIMenuElement]
        if targets.isEmpty {
            let empty = UIAction(
                title: text("没有其他节点"),
                attributes: [.disabled],
                handler: { _ in }
            )
            children = [empty]
        } else {
            children = targets.map { target in
                UIAction(
                    title: target.text.isEmpty ? "未命名" : target.text,
                    attributes: disabled ? [.disabled] : [],
                    handler: { _ in session.linkSelectedTopic(to: target.id) }
                )
            }
        }
        return UIMenu(
            title: text(command.title),
            image: UIImage(systemName: command.symbol),
            children: children
        )
    }

    private func commandUIAction(_ id: EditorToolbarCommandID) -> UIAction {
        let command = EditorToolbarCatalog.command(id)
        let identifier = accessibilityIdentifier(for: id)
        let action = UIAction(
            title: text(command.title),
            image: UIImage(systemName: command.symbol),
            identifier: identifier.map { UIAction.Identifier($0) },
            discoverabilityTitle: text(commandHelp(id)),
            attributes: EditorToolbarCatalog.isEnabled(id, in: toolbarContext) ? [] : [.disabled],
            handler: { _ in self.perform(id) }
        )
        if let identifier {
            action.accessibilityIdentifier = identifier
        }
        return action
    }

    private func overflowAlwaysCommandUIAction(_ id: EditorToolbarCommandID) -> UIAction {
        let command = EditorToolbarCatalog.command(id)
        let identifier = accessibilityIdentifier(for: id)
        let action = UIAction(
            title: text(command.title),
            image: UIImage(systemName: command.symbol),
            identifier: identifier.map { UIAction.Identifier($0) },
            discoverabilityTitle: text(commandHelp(id)),
            handler: { _ in self.perform(id) }
        )
        if !EditorToolbarCatalog.isEnabled(id, in: toolbarContext) {
            action.attributes.insert(.disabled)
        }
        if let identifier { action.accessibilityIdentifier = identifier }
        return action
    }
    #endif

    private func perform(_ id: EditorToolbarCommandID) {
        switch id {
        case .undo:
            session.undo()
        case .redo:
            session.redo()
        case .delete:
            session.deleteSelection()
        case .immersive:
            session.enterZen()
        case .child:
            session.addChildFromToolbar()
        case .sibling:
            session.addSiblingFromToolbar()
        case .dictation:
            session.beginDictation()
        case .freeNode:
            session.addFreeNodeFromToolbar()
        case .sticky:
            session.addStickyFromToolbar()
        case .summary:
            session.addSummaryFromToolbar()
        case .boundary:
            session.addBoundaryFromToolbar()
        case .region:
            session.addRegionFromToolbar()
        case .image:
            showImageImporter = true
        case .attachment:
            showAttachmentImporter = true
        case .importFile:
            onImport()
        case .outline:
            showOutline.toggle()
        case .style:
            showInspector.toggle()
        case .theme:
            showThemes = true
        case .mapMode:
            session.viewMode = .map
        case .focusMode:
            session.viewMode = .focus
        case .newCanvas:
            session.addCanvas(viewport: camera.viewport.persisted)
        case .find:
            findQuery = ""
            showFind = true
        case .tagFilter:
            showTagFilter = true
        case .history:
            showHistory = true
        case .paste:
            pasteFromClipboard()
        case .about:
            showAbout = true
        case .fit:
            camera.fitToContent()
        case .pdf:
            export("pdf")
        case .png:
            export("png")
        case .markdownExport:
            export("md")
        case .textBundle:
            export("textbundle")
        case .saveFloretta:
            export("floretta")
        case .upgrade:
            beginUpgrade()
        case .mm:
            export("mm")
        case .opml:
            export("opml")
        case .xmind:
            export("xmind")
        case .printMap:
            printMap()
        case .insert, .share, .zoom, .more, .link, .viewMode:
            break
        }
    }

    private var snapshotHistoryHelp: String {
        if session.isMarkdownDocument {
            return "Markdown 文件不保留版本快照。"
        }
        if !session.canOpenSnapshotHistory {
            return "先把导图存成文件。"
        }
        return "查看已保存的历史版本，回滚或对比两份内容。"
    }

    private func handleChromeCommand(_ command: MindMapCommand) {
        switch command {
        case .openProperties:
            inspectorTab = .style
            showInspector = true
        case .showShortcutHelp:
            showShortcutHelp = true
        default:
            break
        }
    }

    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { showInspector && !session.zen.isActive },
            set: { showInspector = $0 }
        )
    }

    /// Compact width shows `.inspector` as a sheet. That sheet does not present
    /// when the binding is already true on the editor's first appearance, which
    /// is how a new map arrives. Flip it after this turn so the sheet runs.
    /// Only once: dismissing the sheet must not open it again.
    private func openInspectorForUITest() {
        guard AppLaunch.opensInspector, !didAutoOpenInspector else { return }
        didAutoOpenInspector = true
        Task { @MainActor in
            await Task.yield()
            showInspector = true
        }
    }

    private var inspectorBody: some View {
        // The header is an inset, not a sibling of the page. Switching between
        // 样式 / 导图 rebuilds pages with different intrinsic heights. If
        // that height drives the inspector host, AppKit can recenter its shared
        // toolbar controls over the canvas. Keep the native Picker in a stable,
        // top-anchored inset; only the page below is flexible and scrollable.
        inspectorTabPage
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .safeAreaInset(edge: .top, spacing: 12) {
                inspectorHeader
            }
            .appleGlassChrome(.inspectorPanel)
            // Fill the inspector column with the proposed height. A
            // containerRelativeFrame that returns the container length as
            // its own height can re-enter AppKit's constraint update cycle
            // when the column is dismissed or its page height changes.
            // Escape / a blank-canvas click on 24aa462 crashed with
            // EXC_BREAKPOINT in NSWindow._postWindowNeedsUpdateConstraints.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var inspectorHeader: some View {
        VStack(spacing: 8) {
            if showsSheetDismissHandle {
                // Taller than the segmented control, so the header's center is this
                // handle. A downward drag here dismisses the compact sheet. The same
                // drag on the segments selects 导图 instead, because that control
                // takes the touch on contact. A tap also dismisses, because a UI
                // test swipeDown often misses the DragGesture.
                Button {
                    showInspector = false
                } label: {
                    Capsule()
                        .fill(.secondary)
                        .frame(width: 36, height: 5)
                        .frame(maxWidth: .infinity)
                        .frame(height: 96)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭检查器")
                .accessibilityIdentifier("inspector.dismiss")
                .highPriorityGesture(sheetDismissDrag)
            }
            inspectorTabPicker
                .padding(.horizontal)
        }
        .padding(.top, 12)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: 64)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inspector.header")
    }

    private var showsSheetDismissHandle: Bool {
        #if os(iOS)
        horizontalSizeClass != .regular
        #else
        false
        #endif
    }

    private var sheetDismissDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onEnded { value in
                guard value.translation.height > 24, abs(value.translation.height) > abs(value.translation.width) else { return }
                showInspector = false
            }
    }

    private var inspectorTabPicker: some View {
        Picker(text("检查器"), selection: $inspectorTab) {
            ForEach(InspectorTab.allCases) { tab in
                Text(verbatim: text(tab.titleKey)).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .appleGlassChrome(.segmentedContainer)
        .labelsHidden()
        .accessibilityLabel(text("检查器"))
        .accessibilityIdentifier("inspector.tabs")
    }

    @ViewBuilder
    private var inspectorTabPage: some View {
        switch inspectorTab {
        case .style:
            stylePage
        case .map:
            documentInfo
        }
    }

    /// The open document's paper. The inspector edits this value, so a background
    /// changed here belongs to the file and never follows the home preference.
    private var documentBackground: Binding<String?> {
        Binding(
            get: { session.document.canvasBackgroundHex },
            set: { session.document.canvasBackgroundHex = HomeBackground.canonicalHex($0) }
        )
    }

    @ViewBuilder
    private var stylePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                // Document-scope XMind groups. They stay readable with nothing
                // selected, because a structure, a color scheme and a branch are
                // map-wide.
                inspectorStructureSection
                inspectorColorSchemeSection
                inspectorBranchSection
                AppearanceSettingsPanel(
                    settings: settings,
                    identifierPrefix: "inspector.appearance",
                    density: .inspector,
                    fields: .mapScope,
                    documentBackground: documentBackground
                )
            }
            .formStyle(.grouped)
            .appleGlassInspectorFormPlate()
            inspectorDocumentStyle
        }
    }

    /// 结构. Seven structures, one document field. The canvas, the PNG/PDF export
    /// and a reopened file all read `document.layoutKind`, so this row is the whole
    /// entry point for the layout engine.
    private var inspectorStructureSection: some View {
        Section(text(InspectorStyleSection.structure.titleKey)) {
            Group {
                Picker(text("结构"), selection: structureSelection) {
                    ForEach(LayoutKind.allCases, id: \.self) { kind in
                        Text(verbatim: text(kind.displayNameKey)).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel(text("结构"))
                .accessibilityIdentifier("inspector.style.structure")
            }
            .inspectorRowBlock()
        }
        // A Markdown projection owns its own order; a structure written here
        // would be a field the file cannot show.
        .disabled(session.isMarkdownDocument)
    }

    private var structureSelection: Binding<LayoutKind> {
        Binding(
            get: { session.editingDocument.layoutKind },
            set: { kind in
                guard !session.isMarkdownDocument else { return }
                session.setLayoutKind(kind)
            }
        )
    }

    /// 配色方案. Writes the same `themeID` the 配色 sheet writes, so both entries
    /// show one selected scheme.
    private var inspectorColorSchemeSection: some View {
        Section(text(InspectorStyleSection.colorScheme.titleKey)) {
            Group {
                Picker(text("配色方案"), selection: colorSchemeSelection) {
                    ForEach(InspectorStyle.colorSchemeChoiceIDs, id: \.self) { id in
                        Text(verbatim: colorSchemeTitle(id)).tag(id)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel(text("配色方案"))
                .accessibilityIdentifier("inspector.style.colorScheme")
            }
            .inspectorRowBlock()
        }
        // A Markdown projection owns its colors; the write would be refused anyway.
        .disabled(session.isMarkdownDocument)
    }

    /// 分支 · 线条 / 终点. One token each, stored on the document.
    private var inspectorBranchSection: some View {
        Section(text(InspectorStyleSection.branch.titleKey)) {
            Group {
                Picker(text("线条"), selection: branchLineSelection) {
                    ForEach(BranchLineStyle.allCases) { line in
                        Text(verbatim: text(line.titleKey)).tag(line)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(text("线条"))
                .accessibilityIdentifier("inspector.style.branchLine")

                Picker(text("终点"), selection: branchEndSelection) {
                    ForEach(BranchEndMarker.allCases) { marker in
                        Text(verbatim: text(marker.titleKey)).tag(marker)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel(text("终点"))
                .accessibilityIdentifier("inspector.style.branchEnd")
            }
            .inspectorRowBlock()
        }
        .disabled(session.isMarkdownDocument)
    }

    private var colorSchemeSelection: Binding<String> {
        Binding(
            get: { InspectorStyle.colorSchemeValue(of: session.editingDocument) },
            set: { id in
                guard !session.isMarkdownDocument else { return }
                session.setBranchTheme(id)
            }
        )
    }

    private func colorSchemeTitle(_ id: String) -> String {
        guard let key = InspectorStyle.colorSchemeNameKey(id) else { return id }
        return text(key)
    }

    private var branchLineSelection: Binding<BranchLineStyle> {
        Binding(
            get: { InspectorStyle.branchLineValue(of: session.editingDocument) },
            set: { line in
                _ = session.editActive { document in
                    InspectorStyle.applyDocument(
                        .branchLine(line),
                        document: &document,
                        allowsAppearanceWrites: !session.isMarkdownDocument
                    )
                }
            }
        )
    }

    private var branchEndSelection: Binding<BranchEndMarker> {
        Binding(
            get: { InspectorStyle.branchEndValue(of: session.editingDocument) },
            set: { marker in
                _ = session.editActive { document in
                    InspectorStyle.applyDocument(
                        .branchEnd(marker),
                        document: &document,
                        allowsAppearanceWrites: !session.isMarkdownDocument
                    )
                }
            }
        )
    }

    @ViewBuilder
    private var inspectorDocumentStyle: some View {
        if session.keyboard.selectedRelationshipID != nil {
            relationshipLabelForm
        } else if session.keyboard.selectedSummaryID != nil {
            summaryTextForm
        } else if session.keyboard.selectedBoundaryID != nil {
            boundaryTitleForm
        } else if session.keyboard.selectedRegionID != nil {
            regionStyleForm
        } else {
            StyleInspector(
                document: session.activeCanvasDocument,
                nodeID: session.keyboard.selectedNodeID,
                locksAppearance: session.isMarkdownDocument,
                onSelectRelationship: { id in
                    session.editActive { document in
                        InspectorStyle.selectLink(id, document: &document, keyboard: &session.keyboard)
                    }
                }
            )
        }
    }

    private var documentInfo: some View {
        let facts = InspectorStyle.mapFacts(
            document: session.editingDocument,
            storedAttachmentBytes: session.attachmentCatalog.storedAttachmentBytes,
            archiveByteCount: session.archiveByteCount
        )
        return Form {
            Section {
                Group {
                    ForEach(InspectorStyle.mapRowTitleKeys, id: \.self) { key in
                        LabeledContent(text(key)) {
                            Text(verbatim: InspectorStyle.mapValue(key, facts: facts))
                                .monospacedDigit()
                        }
                    }
                    LabeledContent(text("专区")) {
                        Text(verbatim: "\(session.editingDocument.regions.count)").monospacedDigit()
                    }
                }
                .inspectorRowBlock()
            }
        }
        .formStyle(.grouped)
        .appleGlassInspectorFormPlate()
        .accessibilityIdentifier("inspector.map")
    }

    private var relationshipLabelForm: some View {
        Form {
            Section(text("标签")) {
                Group {
                    TextField(text("标签"), text: relationshipTitle)
                        .onSubmit { commitRelationshipTitle() }
                        .help(Text(verbatim: text("编辑这条关系的标签")))
                        .accessibilityIdentifier("relationship.label")
                }
                .inspectorRowBlock()
            }
        }
        .formStyle(.grouped)
        .appleGlassInspectorFormPlate()
    }

    private var relationshipTitle: Binding<String> {
        Binding(
            get: {
                InspectorMarkField.text(
                    .relationship,
                    id: session.keyboard.selectedRelationshipID,
                    document: session.editingDocument,
                    keyboard: session.keyboard
                )
            },
            set: { newValue in
                session.editActive { document in
                    InspectorMarkField.replace(
                        newValue,
                        kind: .relationship,
                        id: session.keyboard.selectedRelationshipID,
                        document: &document,
                        keyboard: &session.keyboard
                    )
                }

            }
        )
    }

    private var summaryTextForm: some View {
        Form {
            Section(text("概要")) {
                Group {
                    TextField(text("概要"), text: summaryText)
                        .onSubmit { commitMarkText() }
                        .help(Text(verbatim: text("编辑概要文字")))
                        .accessibilityIdentifier("summary.text")
                }
                .inspectorRowBlock()
            }
        }
        .formStyle(.grouped)
        .appleGlassInspectorFormPlate()
    }

    private var summaryText: Binding<String> {
        Binding(
            get: {
                InspectorMarkField.text(
                    .summary,
                    id: session.keyboard.selectedSummaryID,
                    document: session.editingDocument,
                    keyboard: session.keyboard
                )
            },
            set: { newValue in
                session.editActive { document in
                    InspectorMarkField.replace(
                        newValue,
                        kind: .summary,
                        id: session.keyboard.selectedSummaryID,
                        document: &document,
                        keyboard: &session.keyboard
                    )
                }

            }
        )
    }

    private var boundaryTitleForm: some View {
        Form {
            Section(text("边界")) {
                Group {
                    TextField(text("标题"), text: boundaryTitle)
                        .onSubmit { commitMarkText() }
                        .help(Text(verbatim: text("编辑边界标题")))
                        .accessibilityIdentifier("boundary.title")
                }
                .inspectorRowBlock()
            }
        }
        .formStyle(.grouped)
        .appleGlassInspectorFormPlate()
    }

    private var boundaryTitle: Binding<String> {
        Binding(
            get: {
                InspectorMarkField.text(
                    .boundary,
                    id: session.keyboard.selectedBoundaryID,
                    document: session.editingDocument,
                    keyboard: session.keyboard
                )
            },
            set: { newValue in
                session.editActive { document in
                    InspectorMarkField.replace(
                        newValue,
                        kind: .boundary,
                        id: session.keyboard.selectedBoundaryID,
                        document: &document,
                        keyboard: &session.keyboard
                    )
                }
            }
        )
    }

    private var regionStyleForm: some View {
        Form {
            Section(text("专区")) {
                Group {
                    TextField(text("标题"), text: regionLabel)
                        .onSubmit { commitMarkText() }
                        .help(Text(verbatim: text("编辑专区标题")))
                        .accessibilityIdentifier("region.label")
                    HStack {
                        TextField(text("宽度"), text: $regionWidthDraft)
                            .focused($regionMetric, equals: .width)
                            .onSubmit { commitRegionMetric(.width, includingFocused: true) }
                            .accessibilityIdentifier("region.width")
                        Text("px")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        TextField(text("高度"), text: $regionHeightDraft)
                            .focused($regionMetric, equals: .height)
                            .onSubmit { commitRegionMetric(.height, includingFocused: true) }
                            .accessibilityIdentifier("region.height")
                        Text("px")
                            .foregroundStyle(.secondary)
                    }
                    Toggle(text("锁定"), isOn: regionAspectLocked)
                        .accessibilityIdentifier("region.lockInspector")
                    HStack {
                        TextField(text("描边"), text: $regionStrokeDraft)
                            .focused($regionMetric, equals: .stroke)
                            .onSubmit { commitRegionMetric(.stroke, includingFocused: true) }
                            .accessibilityIdentifier("region.stroke")
                        Text("px")
                            .foregroundStyle(.secondary)
                    }
                    ColorPicker(selection: regionFill, supportsOpacity: false) {
                        Text(verbatim: text("填充颜色"))
                    }
                    .accessibilityIdentifier("region.fill")
                    ColorPicker(selection: regionBorder, supportsOpacity: false) {
                        Text(verbatim: text("颜色"))
                    }
                    .accessibilityIdentifier("region.border")
                }
                .inspectorRowBlock()
            }
        }
        .formStyle(.grouped)
        .appleGlassInspectorFormPlate()
    }

    private var regionDraftToken: String {
        guard let id = session.keyboard.selectedRegionID, let region = session.editingDocument.region(id) else { return "" }
        return "\(id.uuidString)|\(region.width)|\(region.height)|\(region.strokeWidth)"
    }

    private func syncRegionDrafts(includingFocused: Bool = false) {
        guard let id = session.keyboard.selectedRegionID, let region = session.editingDocument.region(id) else { return }
        if includingFocused || regionMetric != .width {
            regionWidthDraft = formatRegionPx(region.width)
        }
        if includingFocused || regionMetric != .height {
            regionHeightDraft = formatRegionPx(region.height)
        }
        if includingFocused || regionMetric != .stroke {
            regionStrokeDraft = formatRegionPx(region.strokeWidth)
        }
    }

    private func formatRegionPx(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }

    private func commitRegionMetric(_ metric: RegionMetric, includingFocused: Bool = false) {
        guard let id = session.keyboard.selectedRegionID else { return }
        let raw: String
        switch metric {
        case .width: raw = regionWidthDraft
        case .height: raw = regionHeightDraft
        case .stroke: raw = regionStrokeDraft
        }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed) else {
            syncRegionDrafts(includingFocused: true)
            return
        }
        if session.keyboard.mode == .edit, !session.keyboard.isComposing {
            session.editActive { document in session.keyboard.apply(.commitEdit, document: &document, frames: []) }
        }
        switch metric {
        case .width:
            session.editActive { document in _ = session.keyboard.setRegionLength(value, axis: .width, id: id, document: &document) }
        case .height:
            session.editActive { document in _ = session.keyboard.setRegionLength(value, axis: .height, id: id, document: &document) }
        case .stroke:
            session.editActive { document in _ = session.keyboard.setRegionStroke(value, id: id, document: &document) }
        }
        syncRegionDrafts(includingFocused: includingFocused)
    }

    private var regionLabel: Binding<String> {
        Binding(
            get: {
                guard let id = session.keyboard.selectedRegionID else { return "" }
                if session.keyboard.editingRegionID == id {
                    return session.keyboard.editingText
                }
                return session.editingDocument.region(id)?.label ?? ""
            },
            set: { newValue in
                guard let id = session.keyboard.selectedRegionID else { return }
                if session.keyboard.editingRegionID != id {
                    session.editActive { document in session.keyboard.apply(.beginEdit, document: &document, frames: []) }                }
            }
        )
    }

    private var regionAspectLocked: Binding<Bool> {
        Binding(
            get: {
                guard let id = session.keyboard.selectedRegionID else { return false }
                return session.editingDocument.region(id)?.aspectLocked ?? false
            },
            set: { locked in
                guard let id = session.keyboard.selectedRegionID else { return }
                if session.keyboard.mode == .edit, !session.keyboard.isComposing {
                    session.editActive { document in session.keyboard.apply(.commitEdit, document: &document, frames: []) }
                }
                session.editActive { document in _ = session.keyboard.setRegionAspectLocked(locked, id: id, document: &document) }
            }
        )
    }

    private var regionFill: Binding<Color> {
        Binding(
            get: {
                guard let id = session.keyboard.selectedRegionID, let region = session.editingDocument.region(id) else {
                    return StyleColor.color(hex: CanvasRegionLimits.defaultFill.hexRGB)
                }
                return StyleColor.color(hex: region.fill.hexRGB)
            },
            set: { color in
                guard let id = session.keyboard.selectedRegionID, let parsed = BranchColor(hex: StyleColor.hex(color)) else {
                    return
                }
                session.editActive { document in _ = document.setRegionFill(id, parsed) }
            }
        )
    }

    private var regionBorder: Binding<Color> {
        Binding(
            get: {
                guard let id = session.keyboard.selectedRegionID, let region = session.editingDocument.region(id) else {
                    return StyleColor.color(hex: CanvasRegionLimits.defaultBorder.hexRGB)
                }
                return StyleColor.color(hex: region.border.hexRGB)
            },
            set: { color in
                guard let id = session.keyboard.selectedRegionID, let parsed = BranchColor(hex: StyleColor.hex(color)) else {
                    return
                }
                session.editActive { document in _ = document.setRegionBorder(id, parsed) }
            }
        )
    }

    private func commitMarkText() {
        session.editActive { document in
            InspectorMarkField.commit(document: &document, keyboard: &session.keyboard)
        }
    }

    private func commitRelationshipTitle() {
        session.editActive { document in
            InspectorMarkField.commit(document: &document, keyboard: &session.keyboard)
        }
    }

    private var insertDialogPresented: Binding<Bool> {
        Binding(
            get: { insertProposal != nil },
            set: { presented in
                if !presented, insertProposal != nil, !insertAccepted {
                    cancelInsert()
                }
            }
        )
    }

    private func importAttachment(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first { stageAttachment(url) }
        case .failure(let error):
            exportError = error.localizedDescription
        }
    }

    private func stageAttachment(_ url: URL, ownsCopy: Bool = false) {
        if session.isMarkdownDocument {
            if ownsCopy { try? FileManager.default.removeItem(at: url) }
            session.revealBlocked(MarkdownModePolicy.reason(.insertAttachment))
            return
        }
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey, .isDirectoryKey])
            let directory = values.isDirectory == true
            guard FileAttachmentRoute.accepts(filename: url.lastPathComponent, isDirectory: directory) else {
                if ownsCopy { try? FileManager.default.removeItem(at: url) }
                exportError = directory ? "不能放入文件夹。" : "没有可以放入的文件。"
                return
            }
            let fact = AppleFileTypes.recognize(
                filename: url.lastPathComponent,
                declaredTypeIdentifier: values.contentType?.identifier
            )
            let fileSize = Int64(values.fileSize ?? 0)
            let current = session.archiveByteCount
            guard let proposal = FileAttachmentRoute.proposal(
                filename: url.lastPathComponent,
                byteCount: fileSize,
                currentDocumentByteCount: current
            ) else { return }
            insertAccepted = false
            insertSource = url
            insertSourceIsCopy = ownsCopy
            insertStoredName = FileAttachmentName.storedFilename(
                original: url.lastPathComponent,
                recognizedExtension: fact.fileExtension
            )
            insertProposal = proposal
            if started { _ = url.startAccessingSecurityScopedResource() }
        } catch {
            if ownsCopy { try? FileManager.default.removeItem(at: url) }
            exportError = error.localizedDescription
        }
    }

    private var previewURL: URL? {
        previewPhase.previewPath.map { URL(fileURLWithPath: $0) }
    }

    private var previewAlertPresented: Binding<Bool> {
        Binding(
            get: { previewPhase.alertMessage != nil },
            set: { presented in
                if !presented { previewPhase = FilePreviewSession.dismissAlert(previewPhase) }
            }
        )
    }

    #if os(iOS)
    private var previewSheetPresented: Binding<Bool> {
        Binding(
            get: { previewPhase.previewPath != nil },
            set: { presented in
                if !presented { previewPhase = FilePreviewSession.userClosed(previewPhase) }
            }
        )
    }
    #endif

    private func previewFile(nodeID: UUID, badge: FileBadge) {
        guard let archive = session.url else {
            exportError = "先把导图存成文件。"
            return
        }
        guard let entry = session.attachmentCatalog.attachments.first(where: { $0.sha256 == badge.sha256 }) else {
            let ticket = FilePreviewTicket(
                nodeID: nodeID,
                sha256: badge.sha256,
                filename: badge.filename,
                previewPath: badge.filename
            )
            previewPhase = FilePreviewSession.begin(ticket, fileExists: false)
            return
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FlorettaPreview", isDirectory: true)
        let destination = folder.appendingPathComponent("\(UUID().uuidString).\(badge.fileExtension)")
        let filename = badge.filename
        let sha = badge.sha256
        previewToken += 1
        let token = previewToken
        Task {
            let outcome = await Task.detached {
                Result {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try FilePreviewSpill.write(
                        entry: entry,
                        archiveURL: archive,
                        to: destination,
                        files: FoundationStreamingFiles()
                    )
                    return destination
                }
            }.value
            guard token == previewToken else {
                if case .success(let url) = outcome {
                    try? FileManager.default.removeItem(at: url)
                }
                return
            }
            switch outcome {
            case .success(let url):
                if NodeMediaInsertRoute.accepts(filename: filename) {
                    closeMediaPlayer()
                    mediaPlayerURL = url
                    mediaPlayerKind = NodeMediaKind.classify(filename: filename)
                    audioNodeID = mediaPlayerKind == .audio ? nodeID : nil
                    let item = AVPlayerItem(url: url)
                    guard MediaFileAvailability.state(
                        fileExists: FileManager.default.fileExists(atPath: url.path),
                        isReadable: FileManager.default.isReadableFile(atPath: url.path)
                    ) == .available else {
                        try? FileManager.default.removeItem(at: url)
                        mediaPlayerURL = nil
                        exportError = "媒体文件缺失或无法读取。"
                        return
                    }
                    let player = AVPlayer(playerItem: item)
                    mediaPlaybackLease = MediaPlaybackRegistry.shared.acquire { [weak player] in
                        player?.pause()
                        player?.replaceCurrentItem(with: nil)
                    }
                    mediaPlayer = player
                    player.play()
                    return
                }
                let ticket = FilePreviewTicket(
                    nodeID: nodeID,
                    sha256: sha,
                    filename: filename,
                    previewPath: url.path
                )
                let phase = FilePreviewSession.begin(
                    ticket,
                    fileExists: FileManager.default.fileExists(atPath: url.path)
                )
                if case .alert = phase {
                    try? FileManager.default.removeItem(at: url)
                }
                previewPhase = phase
            case .failure:
                let ticket = FilePreviewTicket(
                    nodeID: nodeID,
                    sha256: sha,
                    filename: filename,
                    previewPath: destination.path
                )
                try? FileManager.default.removeItem(at: destination)
                previewPhase = FilePreviewSession.begin(ticket, fileExists: false)
            }
        }
    }

    private func closeMediaPlayer() {
        mediaPlayer?.pause()
        mediaPlayer?.replaceCurrentItem(with: nil)
        if MediaPlaybackRegistry.shared.hasActivePlayer {
            // Releasing the registry lease stops the current AVPlayer and clears ownership.
            // The callback is idempotent with the explicit teardown above.
            mediaPlaybackLease.map { MediaPlaybackRegistry.shared.release($0) }
        }
        mediaPlayer = nil
        if let mediaPlayerURL { try? FileManager.default.removeItem(at: mediaPlayerURL) }
        mediaPlayerURL = nil
        mediaPlaybackLease = nil
        audioNodeID = nil
    }

    private func cancelInsert() {
        releaseInsertSource()
        insertProposal = nil
        insertAccepted = false
        insertStoredName = nil
    }

    private func releaseInsertSource() {
        if let url = insertSource {
            url.stopAccessingSecurityScopedResource()
            if insertSourceIsCopy {
                try? FileManager.default.removeItem(at: url)
            }
        }
        insertSource = nil
        insertSourceIsCopy = false
    }

    private func beginUpgrade() {
        do {
            upgradeFile = ExportFile(data: try MarkdownUpgrade.fileData(for: session.document))
            let title = session.document.title.isEmpty ? "Floretta" : session.document.title
            upgradeName = title + "." + MarkdownUpgrade.filenameExtension
            showUpgrade = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func beginInsert() {
        guard session.acceptsAttachmentDrop else {
            session.revealBlocked(MarkdownModePolicy.reason(.insertAttachment))
            cancelInsert()
            return
        }
        insertAccepted = true
        let source = insertSource
        let ownsCopy = insertSourceIsCopy
        let storedName = insertStoredName
        insertProposal = nil
        insertSource = nil
        insertSourceIsCopy = false
        insertStoredName = nil
        guard let source else { return }
        guard let archive = session.url else {
            source.stopAccessingSecurityScopedResource()
            if ownsCopy { try? FileManager.default.removeItem(at: source) }
            exportError = "先把导图存成文件。"
            return
        }
        let nodeID = session.keyboard.selectedNodeID ?? session.editingDocument.roots.first?.id
        guard let nodeID else {
            source.stopAccessingSecurityScopedResource()
            if ownsCopy { try? FileManager.default.removeItem(at: source) }
            exportError = "没有可以放入附件的节点。"
            return
        }
        let document = session.document
        Task {
            let outcome = await Task.detached {
                Result {
                    try AttachmentInserter.insert(
                        source: source,
                        nodeID: nodeID,
                        document: document,
                        archive: archive,
                        storedFilename: storedName
                    )
                }
            }.value
            source.stopAccessingSecurityScopedResource()
            if ownsCopy { try? FileManager.default.removeItem(at: source) }
            switch outcome {
            case .success(let saved):
                session.document = saved.document
                session.notePackage(catalog: saved.catalog, bytes: saved.archiveByteCount)
            case .failure(let error):
                exportError = error.localizedDescription
            }
        }
    }


    /// UI tests set `FLORETTA_UITEST_DIR` so this writes the already-prepared
    /// export to disk for readback, instead of only presenting the system panel.
    @discardableResult
    private func presentPreparedExport() -> Bool {
        if let directory = AppLaunch.uiTestExportDirectory {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let destination = directory.appendingPathComponent(exportName)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                if let fileURL = exportFile.fileURL {
                    try FileManager.default.copyItem(at: fileURL, to: destination)
                } else {
                    try exportFile.data.write(to: destination, options: .atomic)
                }
                if exportKind == "floretta" {
                    onSavedCopy(destination)
                }
            } catch {
                exportError = error.localizedDescription
            }
            return true
        }
        showExport = true
        return false
    }

    private func exportFlorettaCopy() throws {
        guard let archive = session.url else {
            exportFile = ExportFile(data: try SharePayload.bytes(for: "floretta", document: session.document))
            exportType = FlorettaFileTypes.contentType(forExport: "floretta")
            exportName = exportFilename(title: session.document.title, kind: "floretta")
            exportKind = "floretta"
            presentPreparedExport()
            return
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).floretta")
        _ = try FlorettaStreamingDocument.save(
            document: session.document,
            to: destination,
            files: FoundationStreamingFiles(),
            copyingAssetsFrom: archive
        )
        exportFile = ExportFile(data: Data(), fileURL: destination)
        exportType = FlorettaFileTypes.contentType(forExport: "floretta")
        exportName = exportFilename(title: session.document.title.isEmpty ? "Floretta" : session.document.title, kind: "floretta")
        exportKind = "floretta"
        presentPreparedExport()
    }

    private var exportErrorPresented: Binding<Bool> {
        Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )
    }

    /// PNG keeps the scale and background from settings. PDF keeps its own page setup.
    /// Both follow the sticky switch.
    private func pictureOptions(kind: String) -> MapExportOptions {
        if kind == "png" {
            return MapExportOptions(settings: settings)
        }
        var options = MapExportOptions()
        options.includeStickies = settings.exportIncludesStickies
        return options
    }

    private func export(_ kind: String) {
        session.prepareToSave()
        let title = session.document.title.isEmpty ? "Floretta" : session.document.title
        let type = FlorettaFileTypes.contentType(forExport: kind)
        do {
            let data: Data
            switch kind {
            case "png", "pdf":
                if ImageAttachments.contains(session.document) {
                    exportPicture(kind, title: title, type: type)
                    return
                }
                if kind == "png" {
                    let result = MapExporter.png(document: session.document, settings: settings, scheme: branchScheme)
                    guard let png = result.png, !png.isEmpty else {
                        exportError = result.notice ?? "没有导出图片。"
                        return
                    }
                    data = png
                } else {
                    let result = MapExporter.pdf(document: session.document, options: pictureOptions(kind: "pdf"), scheme: branchScheme)
                    guard let pdf = result.pdf, !pdf.isEmpty else {
                        exportError = result.notice ?? "没有导出 PDF。"
                        return
                    }
                    data = pdf
                }
            case "floretta":
                if session.documentHasAttachments {
                    try exportFlorettaCopy()
                    return
                }
                data = try SharePayload.bytes(for: kind, document: session.document)
            case "md", "opml", "mm", "xmind":
                data = try SharePayload.bytes(for: kind, document: session.document)
            case "textbundle":
                let assets = try textBundleAssets()
                let package = FlorettaTextBundleCodec.export(session.document, assets: assets)
                #if os(macOS)
                let root = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".textbundle", isDirectory: true)
                try package.writeDirectory(to: root)
                exportFile = ExportFile(data: Data(), fileURL: root)
                exportKind = kind
                exportType = type
                exportName = exportFilename(title: title, kind: kind)
                presentPreparedExport()
                return
                #else
                data = package.textpack()
                #endif
            default:
                return
            }
            exportKind = kind
            exportFile = ExportFile(data: data)
            exportType = type
            exportName = exportFilename(title: title, kind: kind)
            presentPreparedExport()
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func exportFilename(title: String, kind: String) -> String {
        let ext: String
        switch kind {
        case "png": ext = "png"
        case "pdf": ext = "pdf"
        case "md": ext = "md"
        case "opml": ext = "opml"
        case "mm": ext = "mm"
        case "xmind": ext = "xmind"
        case "textbundle":
            #if os(macOS)
            ext = "textbundle"
            #else
            ext = "textpack"
            #endif
        case "floretta": ext = "floretta"
        default: ext = "dat"
        }
        return title + "." + ext
    }

    private func textBundleAssets() throws -> [FlorettaAsset] {
        guard !session.attachmentCatalog.attachments.isEmpty else { return [] }
        guard let archive = session.url else {
            throw DocumentContainerError.corrupt("无法读取尚未保存文档中的附件。")
        }
        let archiveData = try Data(contentsOf: archive)
        let entries = try ZipArchive.read(archiveData, limits: .standard)
        let wanted = Set(AttachmentReferences.hashes(in: session.document))
        return entries.compactMap { entry in
            guard let parsed = AttachmentNames.parseAsset(entry.name), wanted.contains(parsed.sha256) else { return nil }
            return FlorettaAsset(sha256: parsed.sha256, fileExtension: parsed.fileExtension, data: entry.data)
        }
    }

    private func exportPicture(_ kind: String, title: String, type: UTType) {
        let document = session.document
        let archive = session.url
        let entries = session.attachmentCatalog.attachments
        let cacheDirectory = thumbnailCache?.directory
        let options = pictureOptions(kind: kind)
        let scale = Double(options.scale.rawValue)
        let scheme = branchScheme
        Task {
            let spill = ImageExportLoader.spillDirectory(cacheDirectory: cacheDirectory)
            let bitmaps = await Task.detached(priority: .userInitiated) {
                ImageExportLoader.bitmaps(
                    document: document,
                    archive: archive,
                    entries: entries,
                    spillDirectory: spill,
                    scale: scale
                )
            }.value
            var images: [String: CGImage] = [:]
            for bitmap in bitmaps {
                images[bitmap.hash] = bitmap.image
            }
            let result = kind == "png"
                ? MapExporter.png(document: document, options: options, images: images, scheme: scheme)
                : MapExporter.pdf(document: document, options: options, images: images, scheme: scheme)
            let data = kind == "png" ? result.png : result.pdf
            guard let data, !data.isEmpty else {
                exportError = result.notice ?? (kind == "png" ? "没有导出图片。" : "没有导出 PDF。")
                return
            }
            exportKind = kind
            exportFile = ExportFile(data: data)
            exportType = type
            exportName = exportFilename(title: title, kind: kind)
            presentPreparedExport()
        }
    }

    private func pasteFromClipboard() {
        if let pasted = ImageClipboard.fileURL(using: pasteboard) {
            stageAttachment(pasted.url, ownsCopy: pasted.ownsCopy)
            return
        }
        let text = pasteboard.readText() ?? ""
        session.pasteClipboard(text)
    }

    private func textHelp(_ item: String) -> String {
        switch item {
        case "剪切": return "剪下选中节点的文字"
        case "拷贝": return "复制选中节点的文字"
        case "粘贴": return "把剪贴板里的图片放进节点；没有图片时粘贴文字"
        case "全选": return "选中当前画布上的全部主题。编辑文字时由系统全选文本。"
        case "拷贝样式":
            return session.isMarkdownDocument
                ? MarkdownModePolicy.reason(.copyStyle)
                : "复制选中节点的填充颜色"
        default: return item
        }
    }

    private func runTextCommand(_ item: String) {
        switch item {
        case "剪切":
            if let text = session.cutSelection() { writePasteboard(text) }
        case "拷贝":
            if let text = session.copySelection() { writePasteboard(text) }
        case "粘贴":
            pasteFromClipboard()
        case "全选", "选择":
            session.selectCurrent()
        case "拷贝样式":
            if let id = session.keyboard.selectedNodeID,
               let style = session.editingDocument.node(id)?.style {
                writePasteboard(style.fillHex ?? style.colorHex)
            }
        default:
            break
        }
    }

    private func writePasteboard(_ text: String) {
        pasteboard.writeText(text)
    }

    private func printMap() {
        #if os(macOS)
        let result = MapExporter.pdf(document: session.document, options: pictureOptions(kind: "pdf"), scheme: branchScheme)
        guard let data = result.pdf, let document = PDFDocument(data: data) else {
            exportError = result.notice ?? "没有可打印的内容。"
            return
        }
        document.printOperation(for: .shared, scalingMode: .pageScaleNone, autoRotate: true)?.run()
        #endif
    }

    private func syncFullScreen(_ active: Bool) {
        #if os(macOS)
        guard session.zenFullScreenApplied != active else { return }
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        session.zenFullScreenApplied = active
        let full = window.styleMask.contains(.fullScreen)
        if active, !full {
            session.zenEnteredFullScreen = true
            window.toggleFullScreen(nil)
        } else if !active, full, session.zenEnteredFullScreen {
            session.zenEnteredFullScreen = false
            window.toggleFullScreen(nil)
        }
        #endif
    }
}

private struct StyleInspector: View {
    @Binding var document: MindMapDocument
    var nodeID: UUID?
    var locksAppearance = false
    var onSelectRelationship: (UUID) -> Void = { _ in }
    @Environment(\.locale) private var locale

    var body: some View {
        if let nodeID, document.node(nodeID) != nil {
            VStack(alignment: .leading, spacing: 0) {
                if locksAppearance {
                    Text(verbatim: text(MarkdownModePolicy.reason(.nodeColor)))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                        .accessibilityHint(text(MarkdownModePolicy.reason(.nodeColor)))
                }
                appearanceForm
            }
        } else {
            ContentUnavailableView {
                Label {
                    Text(verbatim: text("选择一个主题"))
                } icon: {
                    Image(systemName: "paintbrush")
                        .appleGlassChrome(.iconButton)
                        .accessibilityIdentifier("inspector.empty.brush")
                }
            } description: {
                Text(verbatim: text(locksAppearance ? MarkdownModePolicy.reason(.nodeColor) : "样式会写进导图文件。"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("inspector.empty")
        }
    }

    private var appearanceForm: some View {
        Form {
            Section(text(InspectorStyleSection.shape.titleKey)) {
                Group {
                    Picker(text("形状"), selection: shape) {
                        ForEach(InspectorTopicShape.allCases) { item in
                            Text(verbatim: text(item.titleKey)).tag(item)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("inspector.style.shape")
                }
                .inspectorRowBlock()
            }
            Section(text(InspectorStyleSection.fill.titleKey)) {
                Group {
                    Picker(text("填充样式"), selection: fillStyle) {
                        ForEach(fillStyleTags, id: \.self) { tag in
                            Text(verbatim: fillStyleTitle(tag)).tag(tag)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("inspector.style.fillStyle")
                    ColorPicker(selection: fillColor, supportsOpacity: false) {
                        Text(verbatim: text("填充颜色"))
                    }
                    .accessibilityIdentifier("inspector.style.fillColor")
                }
                .inspectorRowBlock()
            }
            Section(text(InspectorStyleSection.border.titleKey)) {
                Group {
                    Picker(text("样式"), selection: borderStyle) {
                        ForEach(borderStyleTags, id: \.self) { tag in
                            Text(verbatim: borderStyleTitle(tag)).tag(tag)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("inspector.style.borderStyle")
                    LabeledContent(text("宽度")) {
                        Text(verbatim: borderWidthText)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: borderWidth, in: InspectorStyle.borderWidthRange)
                        .accessibilityLabel(text("宽度"))
                        .accessibilityIdentifier("inspector.style.borderWidth")
                    ColorPicker(selection: borderColor, supportsOpacity: false) {
                        Text(verbatim: text("颜色"))
                    }
                    .accessibilityIdentifier("inspector.style.borderColor")
                }
                .inspectorRowBlock()
            }
            Section(text(InspectorStyleSection.width.titleKey)) {
                Group {
                    Picker(text("宽度模式"), selection: widthMode) {
                        ForEach(InspectorWidthMode.allCases) { mode in
                            Text(verbatim: text(mode.titleKey)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel(text("宽度模式"))
                    .accessibilityIdentifier("inspector.style.widthMode")
                    LabeledContent(text("长度")) {
                        Text(verbatim: widthReadout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: topicWidth, in: InspectorStyle.topicWidthRange)
                        .accessibilityLabel(text("长度"))
                        .disabled(InspectorStyle.widthMode(of: style) == .fit)
                        .accessibilityIdentifier("inspector.style.topicWidth")
                }
                .inspectorRowBlock()
            }
            Section(text(InspectorStyleSection.text.titleKey)) {
                Group {
                    TextField(text("副文本"), text: subtitle)
                        .accessibilityIdentifier("inspector.style.subtitle")
                    Picker(text("文字对齐"), selection: textAlignment) {
                        Text(verbatim: text("靠左")).tag(MindMapTextAlignment.leading)
                        Text(verbatim: text("居中")).tag(MindMapTextAlignment.center)
                        Text(verbatim: text("靠右")).tag(MindMapTextAlignment.trailing)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("inspector.style.textAlignment")
                    Picker(text("字体"), selection: fontDesign) {
                        ForEach(fontDesignTags, id: \.self) { tag in
                            Text(verbatim: fontDesignTitle(tag)).tag(tag)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("inspector.style.font")
                    HStack(spacing: 8) {
                        textFlagToggle(.bold)
                        textFlagToggle(.italic)
                        textFlagToggle(.strikethrough)
                        textFlagToggle(.underline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    LabeledContent(text("大小")) {
                        Text(verbatim: "\(Int(InspectorStyle.fontSizeValue(of: style)))pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: fontSize, in: InspectorStyle.fontSizeRange, step: InspectorStyle.fontSizeStep)
                        .accessibilityLabel(text("大小"))
                        .accessibilityIdentifier("inspector.style.fontSize")
                    ColorPicker(selection: textColor, supportsOpacity: false) {
                        Text(verbatim: text("颜色"))
                    }
                    .accessibilityIdentifier("inspector.style.textColor")
                }
                .inspectorRowBlock()
            }
            Section(text(InspectorStyleSection.links.titleKey)) {
                Group {
                    if locksAppearance {
                        Text(verbatim: text(MarkdownModePolicy.reason(.relationship)))
                    } else if let nodeID {
                        if linkedRelationships.isEmpty {
                            Text(verbatim: text("还没有连到其他节点。"))
                        } else {
                            ForEach(linkedRelationships) { link in
                                Button {
                                    onSelectRelationship(link.id)
                                } label: {
                                    Text(verbatim: InspectorStyle.relationshipLine(
                                        link,
                                        seenFrom: nodeID,
                                        document: document,
                                        missingTopic: text("缺失的节点")
                                    ))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("inspector.link.\(link.id.uuidString)")
                            }
                        }
                    }
                }
                .inspectorRowBlock()
            }
        }
        .formStyle(.grouped)
        .appleGlassInspectorFormPlate()
        .disabled(locksAppearance)
        .accessibilityIdentifier("inspector.style")
    }

    private var linkedRelationships: [TopicRelationship] {
        guard let nodeID else { return [] }
        return InspectorStyle.links(in: document, nodeID: nodeID)
    }

    private var fillStyleTags: [String] {
        InspectorStyle.choiceTags(
            known: InspectorFillStyle.allCases.map(\.rawValue),
            current: InspectorStyle.fillStyleValue(of: style)
        )
    }

    private var borderStyleTags: [String] {
        InspectorStyle.choiceTags(
            known: InspectorBorderStyle.allCases.map(\.rawValue),
            current: InspectorStyle.borderStyleValue(of: style)
        )
    }

    private var fontDesignTags: [String] {
        InspectorStyle.choiceTags(
            known: InspectorFontDesign.allCases.map(\.rawValue),
            current: InspectorStyle.fontDesignValue(of: style)
        )
    }

    private func fillStyleTitle(_ tag: String) -> String {
        if let known = InspectorFillStyle(rawValue: tag) { return text(known.titleKey) }
        return tag
    }

    private func borderStyleTitle(_ tag: String) -> String {
        if let known = InspectorBorderStyle(rawValue: tag) { return text(known.titleKey) }
        return tag
    }

    private func fontDesignTitle(_ tag: String) -> String {
        if let known = InspectorFontDesign(rawValue: tag) { return text(known.titleKey) }
        return tag
    }

    private var borderWidthText: String {
        switch InspectorStyle.borderWidthReadout(of: style) {
        case .none:
            return text("无")
        case .points(let width):
            if width.rounded() == width { return "\(Int(width))" }
            return String(format: "%.1f", width)
        }
    }

    private func textFlagToggle(_ flag: InspectorTextFlag) -> some View {
        Toggle(isOn: textFlag(flag)) {
            flagLabel(flag)
        }
        .toggleStyle(.button)
        .buttonBorderShape(.capsule)
        .accessibilityLabel(text(flag.titleKey))
        .accessibilityIdentifier(textFlagIdentifier(flag))
    }

    private func textFlagIdentifier(_ flag: InspectorTextFlag) -> String {
        switch flag {
        case .bold: "inspector.style.bold"
        case .italic: "inspector.style.italic"
        case .strikethrough: "inspector.style.strikethrough"
        case .underline: "inspector.style.underline"
        }
    }

    private func flagLabel(_ flag: InspectorTextFlag) -> Text {
        let mark = Text(verbatim: flag.mark)
        switch flag {
        case .bold: return mark.bold()
        case .italic: return mark.italic()
        case .strikethrough: return mark.strikethrough()
        case .underline: return mark.underline()
        }
    }

    private func text(_ key: String) -> String {
        FlorettaL10n.string(key, locale: locale)
    }

    private var shape: Binding<InspectorTopicShape> {
        Binding(
            get: { InspectorStyle.shape(of: style) },
            set: { apply(.shape($0)) }
        )
    }

    private var fillStyle: Binding<String> {
        Binding(
            get: { InspectorStyle.fillStyleValue(of: style) },
            set: { value in
                guard let parsed = InspectorFillStyle(rawValue: value) else { return }
                apply(.fillStyle(parsed))
            }
        )
    }

    private var fillColor: Binding<Color> {
        Binding(
            get: { StyleColor.color(hex: style?.fillHex ?? style?.colorHex ?? InspectorStyle.fallbackFillHex) },
            set: { apply(.fillHex(StyleColor.hex($0))) }
        )
    }

    private var topicWidth: Binding<Double> {
        Binding(
            get: { InspectorStyle.topicWidthValue(of: style) },
            set: { apply(.topicWidth($0)) }
        )
    }

    private var widthMode: Binding<InspectorWidthMode> {
        Binding(
            get: { InspectorStyle.widthMode(of: style) },
            set: { apply(.widthMode($0)) }
        )
    }

    private var widthReadout: String {
        switch InspectorStyle.widthMode(of: style) {
        case .fit:
            return text("适应")
        case .pixels:
            return "\(Int(InspectorStyle.topicWidthValue(of: style)))px"
        }
    }

    private var borderStyle: Binding<String> {
        Binding(
            get: { InspectorStyle.borderStyleValue(of: style) },
            set: { value in
                guard let parsed = InspectorBorderStyle(rawValue: value) else { return }
                apply(.borderStyle(parsed))
            }
        )
    }

    private var borderWidth: Binding<Double> {
        Binding(
            get: { InspectorStyle.borderWidthValue(of: style) },
            set: { apply(.borderWidth($0)) }
        )
    }

    private var borderColor: Binding<Color> {
        Binding(
            get: { StyleColor.color(hex: style?.borderHex ?? InspectorStyle.fallbackColorHex) },
            set: { apply(.borderHex(StyleColor.hex($0))) }
        )
    }

    private var fontDesign: Binding<String> {
        Binding(
            get: { InspectorStyle.fontDesignValue(of: style) },
            set: { value in
                guard let parsed = InspectorFontDesign(rawValue: value) else { return }
                apply(.fontDesign(parsed))
            }
        )
    }

    private var fontSize: Binding<Double> {
        Binding(
            get: { InspectorStyle.fontSizeValue(of: style) },
            set: { apply(.fontSize($0)) }
        )
    }

    private var textColor: Binding<Color> {
        Binding(
            get: { StyleColor.color(hex: style?.textHex ?? InspectorStyle.fallbackColorHex) },
            set: { apply(.textHex(StyleColor.hex($0))) }
        )
    }

    private var textAlignment: Binding<MindMapTextAlignment> {
        Binding(
            get: { nodeID.flatMap { document.node($0)?.textAlignment } ?? .center },
            set: { alignment in
                guard let nodeID else { return }
                _ = document.setTextAlignment(alignment, on: nodeID)
            }
        )
    }

    private var subtitle: Binding<String> {
        Binding(
            get: { nodeID.flatMap { document.node($0)?.subtitle } ?? "" },
            set: { value in
                guard let nodeID else { return }
                _ = document.replaceSubtitle(value, on: nodeID)
            }
        )
    }

    private func textFlag(_ flag: InspectorTextFlag) -> Binding<Bool> {
        Binding(
            get: { InspectorStyle.isOn(flag, style: style) },
            set: { apply(.flag(flag, $0)) }
        )
    }

    private var style: MindMapNodeStyle? {
        guard let nodeID else { return nil }
        return document.node(nodeID)?.style
    }

    private func apply(_ edit: InspectorStyleEdit) {
        guard let nodeID else { return }
        _ = InspectorStyle.apply(
            edit,
            nodeID: nodeID,
            document: &document,
            allowsAppearanceWrites: !locksAppearance
        )
    }
}

private enum StyleColor {
    static func color(hex: String) -> Color {
        guard let parsed = BranchColor(hex: hex) else { return .black }
        return Color(red: parsed.red, green: parsed.green, blue: parsed.blue)
    }

    static func hex(_ color: Color) -> String {
        #if os(macOS)
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.black
        let red = Int((resolved.redComponent * 255).rounded())
        let green = Int((resolved.greenComponent * 255).rounded())
        let blue = Int((resolved.blueComponent * 255).rounded())
        #else
        var redComponent: CGFloat = 0
        var greenComponent: CGFloat = 0
        var blueComponent: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(color).getRed(&redComponent, green: &greenComponent, blue: &blueComponent, alpha: &alpha)
        let red = Int((redComponent * 255).rounded())
        let green = Int((greenComponent * 255).rounded())
        let blue = Int((blueComponent * 255).rounded())
        #endif
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

struct ExportFile: FileDocument {
    static var readableContentTypes: [UTType] { FlorettaFileTypes.exportableContentTypes }
    var data: Data
    var fileURL: URL?

    init(data: Data, fileURL: URL? = nil) {
        self.data = data
        self.fileURL = fileURL
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        fileURL = nil
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if let fileURL {
            return try FileWrapper(url: fileURL, options: [])
        }
        return FileWrapper(regularFileWithContents: data)
    }
}

private struct BranchThemeSheet: View {
    var themeID: String?
    var language: AppLanguage
    var onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(MapColorPresetCatalog.all) { preset in
                        Button {
                            onSelect(preset.id)
                        } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(ink(preset.canvasBackground))
                                    .frame(width: 22, height: 22)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .strokeBorder(
                                                ink(preset.branchColors.first ?? .black),
                                                lineWidth: min(max(preset.lineWidth, 1), 3)
                                            )
                                    }
                                    .accessibilityHidden(true)
                                HStack(spacing: 4) {
                                    ForEach(Array(preset.branchColors.enumerated()), id: \.offset) { _, swatch in
                                        Circle()
                                            .fill(ink(swatch))
                                            .frame(width: 14, height: 14)
                                    }
                                }
                                .accessibilityHidden(true)
                                Text(verbatim: text(preset.nameKey))
                                Spacer(minLength: 8)
                                if isSelected(preset.id) {
                                    Image(systemName: "checkmark")
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(text(preset.nameKey))
                        .accessibilityAddTraits(isSelected(preset.id) ? .isSelected : AccessibilityTraits())
                        .accessibilityIdentifier("preset.\(preset.id)")
                    }
                } header: {
                    Text(verbatim: text("配色方案"))
                } footer: {
                    Text(verbatim: text("一次换上分支色、画布背景和线条粗细"))
                }
                Section {
                    ForEach(MapThemeCatalog.all) { theme in
                        Button {
                            onSelect(theme.id)
                        } label: {
                            HStack(spacing: 12) {
                                HStack(spacing: 4) {
                                    ForEach(Array(colors(theme).enumerated()), id: \.offset) { _, swatch in
                                        Circle()
                                            .fill(ink(swatch))
                                            .frame(width: 14, height: 14)
                                    }
                                }
                                .accessibilityHidden(true)
                                Text(verbatim: text(theme.nameKey))
                                Spacer(minLength: 8)
                                if isSelected(theme.id) {
                                    Image(systemName: "checkmark")
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(text(theme.nameKey))
                        .accessibilityAddTraits(isSelected(theme.id) ? .isSelected : AccessibilityTraits())
                        .accessibilityIdentifier("theme.\(theme.id)")
                    }
                } footer: {
                    Text(verbatim: text("为各分支自动配色，浅色和深色各用一套"))
                }
            }
            .navigationTitle(text("配色"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(text("关闭"))
                    .accessibilityIdentifier("theme.close")
                }
            }
        }
        .frame(minWidth: 360, idealHeight: 520)
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("theme.sheet")
    }

    private func text(_ key: String) -> String {
        FlorettaL10n.string(key, language: language)
    }

    private func colors(_ theme: MapTheme) -> [BranchColor] {
        let appearance = colorScheme == .dark ? theme.dark : theme.light
        return appearance.palette.colors
    }

    private func ink(_ color: BranchColor) -> Color {
        Color(red: color.red, green: color.green, blue: color.blue)
    }

    private func isSelected(_ id: String) -> Bool {
        MapThemeCatalog.persistedID(id) == MapThemeCatalog.persistedID(themeID)
    }
}

private struct AboutSheet: View {
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(verbatim: FlorettaL10n.format("版本 %@", locale: locale, arguments: [AppInfo.version]))
                        .font(.headline)
                    Text(AppInfo.notice)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle(FlorettaL10n.string("关于", locale: locale))
        }
    }
}

private enum TagMarkerTitle {
    static func text(_ markerId: String, text: (String) -> String, locale: Locale) -> String {
        if let number = TopicMarkerCatalog.priorityNumber(markerId) {
            return FlorettaL10n.format("优先级 %lld", locale: locale, arguments: [Int64(number)])
        }
        switch markerId {
        case "task-start": return text("未开始")
        case "task-oct": return text("1/8")
        case "task-quarter": return text("1/4")
        case "task-3oct": return text("3/8")
        case "task-half": return text("1/2")
        case "task-5oct": return text("5/8")
        case "task-3quar": return text("3/4")
        case "task-7oct": return text("7/8")
        case "task-done": return text("完成")
        case "flag-red": return text("红旗")
        case "flag-orange": return text("橙旗")
        case "flag-yellow": return text("黄旗")
        case "flag-green": return text("绿旗")
        case "flag-blue": return text("蓝旗")
        case "flag-purple": return text("紫旗")
        case "flag-gray": return text("灰旗")
        default: return markerId
        }
    }
}

private struct TagFilterSheet: View {
    @Bindable var session: EditorSession
    var text: (String) -> String
    var locale: Locale
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Form {
                if let node = selectedNode {
                    Section(text("标记")) {
                        markerPicker(text("优先级"), group: .priority, selection: markerID(in: .priority, on: node)) {
                            Text(verbatim: text("无")).tag("")
                            ForEach(TopicMarkerCatalog.priorityIDs, id: \.self) { id in
                                Text(verbatim: title(id)).tag(id)
                            }
                        }
                        markerPicker(text("进度"), group: .progress, selection: markerID(in: .progress, on: node)) {
                            Text(verbatim: text("无")).tag("")
                            ForEach(TopicMarkerCatalog.progressIDs, id: \.self) { id in
                                Text(verbatim: title(id)).tag(id)
                            }
                        }
                        markerPicker(text("旗帜"), group: .flag, selection: markerID(in: .flag, on: node)) {
                            Text(verbatim: text("无")).tag("")
                            ForEach(TopicMarkerCatalog.flagIDs, id: \.self) { id in
                                Text(verbatim: title(id)).tag(id)
                            }
                        }
                    }
                    Section(text("标签")) {
                        if node.labels.isEmpty {
                            Text(verbatim: text("无"))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(node.labels.enumerated()), id: \.offset) { _, label in
                            HStack {
                                Text(verbatim: label)
                                Spacer()
                                Button {
                                    session.updateSelectedTopicTags { topic in
                                        topic.labels = TopicLabels.removing(label, from: topic.labels)
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(text("移除标签"))
                            }
                        }
                        HStack {
                            TextField(text("添加标签"), text: $draft)
                                .onSubmit(addDraft)
                                .accessibilityIdentifier("tagFilter.labelField")
                            Button(action: addDraft) {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel(text("添加标签"))
                            .accessibilityIdentifier("tagFilter.addLabel")
                        }
                    }
                } else {
                    Section {
                        Text(verbatim: text("选择一个主题"))
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    TextField(text("搜索标签"), text: $query)
                        .accessibilityIdentifier("tagFilter.search")
                    Text(verbatim: text("匹配的主题会高亮，其余变淡。"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if filteredLabels.isEmpty && filteredMarkers.isEmpty {
                        Text(verbatim: text(queryTrims.isEmpty ? "这张导图还没有标签。" : "没有找到。"))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(filteredLabels, id: \.self) { label in
                        filterButton(title: label, chosen: session.tagFilter.choice == .label(label)) {
                            toggle(.label(label))
                        }
                    }
                    ForEach(filteredMarkers, id: \.self) { markerId in
                        filterButton(title: title(markerId), chosen: session.tagFilter.choice == .marker(markerId)) {
                            toggle(.marker(markerId))
                        }
                    }
                    if session.tagFilter.isActive {
                        Button(text("清除筛选")) { session.tagFilter.choice = nil }
                    }
                } header: {
                    Text(verbatim: text("筛选"))
                }
            }
            .formStyle(.grouped)
            .navigationTitle(text("标签筛选"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(text("关闭")) { dismiss() }
                        .accessibilityIdentifier("tagFilter.close")
                }
            }
        }
    }

    private var selectedNode: MindMapNode? {
        guard let id = session.keyboard.selectedNodeID else { return nil }
        return session.editingDocument.node(id)
    }

    private var queryTrims: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredLabels: [String] {
        TopicTagIndex.labels(in: session.editingDocument).filter { TopicTagIndex.contains(query, in: $0) }
    }

    private var filteredMarkers: [String] {
        TopicTagIndex.markerIDs(in: session.editingDocument).filter { markerId in
            TopicTagIndex.contains(query, in: title(markerId))
        }
    }

    private func title(_ markerId: String) -> String {
        TagMarkerTitle.text(markerId, text: text, locale: locale)
    }

    private func markerID(in group: TopicMarkerGroup, on node: MindMapNode) -> String {
        node.markers.first { TopicMarkerCatalog.group(of: $0.markerId) == group }?.markerId ?? ""
    }

    private func markerPicker<Content: View>(
        _ label: String,
        group: TopicMarkerGroup,
        selection: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Picker(selection: Binding(
            get: { selection },
            set: { newValue in
                session.updateSelectedTopicTags { topic in
                    topic.markers = TopicMarkerCatalog.assign(
                        topic.markers,
                        markerID: newValue.isEmpty ? nil : newValue,
                        group: group
                    )
                }
            }
        )) {
            content()
        } label: {
            Text(verbatim: label)
        }
    }

    private func filterButton(title: String, chosen: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(verbatim: title)
                Spacer()
                if chosen {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    private func toggle(_ choice: TopicTagFilter.Choice) {
        if session.tagFilter.choice == choice {
            session.tagFilter.choice = nil
        } else {
            session.tagFilter.choice = choice
        }
    }

    private func addDraft() {
        let label = draft
        draft = ""
        guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        session.updateSelectedTopicTags { topic in
            topic.labels = TopicLabels.inserting(label, into: topic.labels)
        }
    }
}

/// Holds the title cache across keystrokes. The view reads it while drawing,
/// and the cache only remeasures a title whose text changed.
@MainActor
private final class TopicCensusModel {
    private var cache = TopicTitleCensusCache()

    func census(of document: MindMapDocument) -> TopicTitleCensus {
        cache.update(document)
    }
}

private struct ExplainedChrome: ViewModifier {
    var sentence: String
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        let resolved = FlorettaL10n.string(sentence, locale: locale)
        content.help(Text(verbatim: resolved)).accessibilityLabel(resolved)
    }
}

private extension View {
    func explained(_ sentence: String) -> some View {
        modifier(ExplainedChrome(sentence: sentence))
    }
}

private struct ShortcutsHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(XMindShortcutCatalog.entries.enumerated()), id: \.offset) { _, entry in
                    LabeledContent(entry.title, value: XMindShortcutCatalog.display(entry.key, entry.modifiers))
                }
                LabeledContent("适应窗口", value: "⌘0")
                LabeledContent("放大 / 缩小", value: "⌘+ / ⌘-")
                LabeledContent("实际大小", value: "⌘=")
                LabeledContent("查找", value: "⌘F")
                LabeledContent("加粗 / 斜体", value: "⌘B / ⌘I")
                LabeledContent("剪切 / 复制 / 粘贴", value: "⌘X / ⌘C / ⌘V")
                LabeledContent("新建 / 保存", value: "⌘N / ⌘S")
            }
            .navigationTitle("快捷键一览")
            .accessibilityIdentifier("shortcuts.help")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 420)
    }
}

private struct MacEditorWindowTitle: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        #if os(macOS)
        content.background(MacWindowTitleUpdater(title: title))
        #else
        content
        #endif
    }
}

#if os(macOS)
private struct MacWindowTitleUpdater: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> MacWindowTitleView {
        MacWindowTitleView(title: title)
    }

    func updateNSView(_ nsView: MacWindowTitleView, context: Context) {
        nsView.title = title
        nsView.applyEditorChrome()
    }

    static func dismantleNSView(_ nsView: MacWindowTitleView, coordinator: ()) {
        MainActor.assumeIsolated {
            nsView.window?.titleVisibility = .visible
        }
    }
}

private final class MacWindowTitleView: NSView {
    var title: String

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Latches the first correction. Applying it again from layout chases the
    /// title and toolbar mode SwiftUI restores while toolbar items are built.
    private var chromePass = WindowChromePass()

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyEditorChrome()
    }

    /// The document title belongs in the native window-title position.
    /// Icon-only is the editor toolbar's display mode. Each item's `Label`
    /// still carries its title for the overflow menu and the customization panel.
    /// This is not called from `layout()`: that call ran inside
    /// `layoutSubtreeIfNeeded`, invalidated toolbar preferences, and re-entered
    /// `DocumentEditor.body` with no state change.
    func applyEditorChrome() {
        guard let window else { return }
        let write = chromePass.applying(
            titleIsHidden: window.titleVisibility != .visible,
            hasToolbar: window.toolbar != nil,
            toolbarIsIconOnly: window.toolbar?.displayMode == .iconOnly
        )
        window.title = title
        if write.hideTitle {
            window.titleVisibility = .visible
        }
        if write.forceIconOnly, let toolbar = window.toolbar {
            toolbar.displayMode = .iconOnly
        }
    }
}
#endif

/// Drag-drop image. The system hands us a file; we copy it before that file disappears.
struct DroppedImage: Transferable, Sendable {
    var url: URL
    var ownsCopy: Bool

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .image) { image in
            SentTransferredFile(image.url)
        } importing: { received in
            let ext = ImageFileName.preferredExtension(
                pathExtension: received.file.pathExtension,
                typeExtension: try? received.file.resourceValues(forKeys: [.contentTypeKey]).contentType?.preferredFilenameExtension
            )
            let original = (received.file.lastPathComponent as NSString).deletingPathExtension
            let stem = original.isEmpty || original == received.file.lastPathComponent ? "图片" : original
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let dest = folder.appendingPathComponent("\(stem).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return DroppedImage(url: dest, ownsCopy: true)
        }
    }
}

enum ImageClipboard {
    static func fileURL(using pasteboard: any PasteboardPort) -> (url: URL, ownsCopy: Bool)? {
        if let url = pasteboard.readImageFileURL() { return (url, false) }
        guard let image = pasteboard.readImageData(),
              let url = write(image.data, extension: image.fileExtension) else { return nil }
        return (url, true)
    }

    private static func write(_ data: Data, extension ext: String) -> URL? {
        let name = ImageFileName.preferredExtension(pathExtension: ext, typeExtension: nil)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let dest = folder.appendingPathComponent("粘贴.\(name)")
            try data.write(to: dest, options: .atomic)
            return dest
        } catch {
            return nil
        }
    }

}

private extension View {
    @ViewBuilder
    func zenChrome(_ chrome: ZenChrome) -> some View {
        #if os(iOS)
        self
            .toolbar(chrome.showsToolbar ? .visible : .hidden, for: .navigationBar)
            .toolbar(chrome.showsTabBar ? .visible : .hidden, for: .tabBar)
            .statusBarHidden(!chrome.showsStatusBar)
        #else
        self
            .toolbar(chrome.showsToolbar ? .visible : .hidden, for: .windowToolbar)
        #endif
    }
}

/// Watches the live camera in its own body. Pan and zoom write `camera.viewport` every frame;
/// reading it in `DocumentEditor.body` re-ran the whole editor body and, on macOS, rebuilt the window toolbar each frame.
private struct CanvasViewportRelay: View {
    let camera: CanvasCamera
    let onChange: (CanvasViewport) -> Void

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: camera.viewport) { _, viewport in
                onChange(viewport)
            }
    }
}
