import CoreTransferable
import FlorettaCore
import SwiftUI
import UniformTypeIdentifiers
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

    var body: some View {
        canvasStack
            .overlay(alignment: .topTrailing) {
                if session.zen.isActive {
                    immersiveExit
                        .padding(16)
                }
            }
        .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .modifier(MacEditorWindowTitle())
        .zenChrome(session.zen.chrome)
        .onChange(of: regionDraftToken) { _, _ in
            syncRegionDrafts()
        }
        .onChange(of: regionMetric) { previous, _ in
            if let previous { commitRegionMetric(previous) }
        }
            .inspector(isPresented: inspectorPresented) {
                inspectorBody
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 440)
            }
            .onAppear(perform: openInspectorForUITest)
            .toolbar {
                if session.zen.chrome.showsToolbar {
                    // A chevron nested in the filename stack is custom bar content:
                    // the glass platter is decoration, and the hit target shrinks to
                    // the glyph. Its own toolbar button is a system bar item, whose
                    // platter is a circle of at least 44pt and owns the hit testing.
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
                        .appleGlassChrome(.iconButton)
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
                    #else
                    ToolbarItem(placement: .cancellationAction) {
                        leadingDocumentChrome
                    }
                    #endif
                    #if !os(macOS)
                    ToolbarItemGroup(placement: .principal) {
                        toolbarControl(.undo)
                            .appleGlassChrome(.toolbarFloatingButton)
                        toolbarControl(.redo)
                            .appleGlassChrome(.toolbarFloatingButton)
                        toolbarControl(.delete)
                            .appleGlassChrome(.toolbarFloatingButton)
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        toolbarControl(.insert)
                            .appleGlassChrome(.toolbarFloatingButton)
                        toolbarControl(.share)
                            .appleGlassChrome(.toolbarFloatingButton)
                        toolbarControl(.zoom)
                            .appleGlassChrome(.toolbarFloatingButton)
                        toolbarControl(.immersive)
                            .appleGlassChrome(.toolbarFloatingButton)
                    }
                    #if os(iOS)
                    // confirmationAction can still disappear once the trailing group
                    // includes a percent-width zoom chip. topBarTrailing plus an icon
                    // zoom control keeps editor.more on a compact phone.
                    ToolbarItem(placement: .topBarTrailing) {
                        toolbarControl(.more)
                    }
                    #endif
                    #endif
                }
            }
            #if os(macOS)
            .toolbar(id: "floretta.editor") {
                if session.zen.chrome.showsToolbar {
                    macItem(.undo)
                    macItem(.redo)
                    macItem(.delete)
                    macItem(.insert)
                    macItem(.share)
                    macItem(.zoom)
                    macItem(.immersive)
                    macItem(.more)
                    macItem(.child)
                    macItem(.sibling)
                    macItem(.dictation)
                    macItem(.freeNode)
                    macItem(.sticky)
                    macItem(.link)
                    macItem(.summary)
                    macItem(.boundary)
                    macItem(.region)
                    macItem(.image)
                    macItem(.attachment)
                    macItem(.importFile)
                    macItem(.outline)
                    macItem(.style)
                    macItem(.theme)
                    macItem(.viewMode)
                    macItem(.newCanvas)
                    macItem(.find)
                    macItem(.tagFilter)
                    macItem(.history)
                    macItem(.paste)
                    macItem(.about)
                    macItem(.mapMode)
                    macItem(.focusMode)
                    macItem(.fit)
                }
            }
            #endif
            #if os(macOS)
            .toolbarBackground(.hidden, for: .windowToolbar)
            #else
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
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
            .onChange(of: camera.viewport) { _, viewport in
                session.noteViewport(viewport.persisted)
            }
            .onChange(of: session.zen.isActive) { _, active in
                syncFullScreen(active)
            }
            .onKeyPress(.escape) {
                session.handleEscape() ? .handled : .ignored
            }
            .contextMenu {
                ForEach(CanvasMenus.text, id: \.self) { item in
                    Button(text(item)) { runTextCommand(item) }
                        .explained(textHelp(item))
                        .disabled(CanvasMenus.textDisabled.contains(item) || (session.isMarkdownDocument && item == "拷贝样式"))
                }
            }
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
            .sheet(isPresented: $showAbout) {
                AboutSheet()
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
                focusNodeID: session.viewMode == .focus ? session.focusNodeID : nil,
                zenActive: session.zen.isActive,
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
                tagFilter: session.tagFilter,
                persistsPlacement: !session.isMarkdownDocument,
                dictationToken: session.dictationToken,
                dictationReplacesPlaceholder: session.dictationReplacesPlaceholder
            )
            .ignoresSafeArea(edges: showsCanvasTabs ? .top.union(.horizontal) : .all)
            if showOutline, session.zen.chrome.showsSidebar {
                outlinePanel
                    .frame(width: outlineWide ? nil : 300)
                    .frame(maxWidth: outlineWide ? .infinity : 300, maxHeight: .infinity)
                    .background(.regularMaterial)
            }
        }
        .overlay(alignment: .top) {
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if showsCanvasTabs { canvasTabBar }
                if session.zen.chrome.showsStatusBar {
                HStack(spacing: 8) {
                    #if os(macOS)
                    Spacer(minLength: 8)
                    #endif

                    TopicStatusBar(
                        census: topicCensus.census(of: session.editingDocument),
                        locale: settings.resolvedLocale
                    )
                    #if !os(macOS)
                    Spacer(minLength: 8)
                    #endif
                    EditorStatusControls(
                        session: session,
                        camera: camera,
                        language: settings.language
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)
                .overlay(alignment: .top) { Divider() }
                .accessibilityIdentifier("statusBar")
                }
            }
            .accessibilityIdentifier("editor.bottomBar")
        }
    }

    /// One row of sheet titles. Only the visible canvas is mounted, so switching
    /// sheets lays that sheet out once and leaves the others off the frame path.
    private var showsCanvasTabs: Bool {
        !session.isMarkdownDocument && !session.zen.isActive
    }

    private var canvasTabBar: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(0..<session.document.canvasCount, id: \.self) { index in
                        canvasTab(index)
                    }
                }
            }
            Button {
                session.addCanvas(viewport: camera.viewport.persisted)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(text("新建画布"))
            .accessibilityIdentifier("canvas.tab.add")
            .help(Text(verbatim: text("在这份文档里再加一张画布")))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .accessibilityIdentifier("canvas.tabs")
        .alert(Text(verbatim: text("重新命名")), isPresented: $showCanvasRename) {
            TextField(text("名称"), text: $canvasRenameText)
            Button(text("确定")) {
                session.renameCanvas(at: canvasRenameIndex, to: canvasRenameText)
            }
            Button(text("取消"), role: .cancel) {}
        }
    }

    private func canvasTab(_ index: Int) -> some View {
        let selected = index == session.document.clampedCanvasIndex
        return Button {
            session.activateCanvas(index, viewport: camera.viewport.persisted)
        } label: {
            Text(verbatim: session.document.canvasTitle(at: index))
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .appleGlassChrome(.bottomBarCapsule)
        .tint(selected ? Color.accentColor : Color.secondary)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("canvas.tab.\(index)")
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            canvasRenameIndex = index
            canvasRenameText = session.document.canvasTitle(at: index)
            showCanvasRename = true
        })
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
                locksCollapse: session.isMarkdownDocument
            )
        }
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
        .background(.regularMaterial)
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
        .background(.regularMaterial)
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

    private var immersiveExit: some View {
        Button {
            session.exitZen()
        } label: {
            Image(systemName: "xmark")
        }
        .buttonStyle(.plain)
        .appleGlassChrome(.iconButton)
        .explained("退出沉浸模式，恢复工具栏")
        .accessibilityIdentifier("zen.exit")
    }

    private var leadingDocumentChrome: some View {
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
            .help(Text(verbatim: text("为这份导图重新命名")))
            .accessibilityLabel(documentTitle)
            .accessibilityHint(text("为这份导图重新命名"))
            .accessibilityIdentifier("document.title")
        }
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

    private func commandLabel(_ id: EditorToolbarCommandID, surface: EditorCommandSurface) -> EditorCommandLabel {
        let command = EditorToolbarCatalog.command(id)
        return EditorCommandLabel(
            title: text(command.title),
            symbol: command.symbol,
            display: EditorToolbarCatalog.display(on: surface)
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
        case .dictation: return "insert.dictation"
        case .region: return "insert.region"
        case .style: return "inspector.open"
        case .theme: return "theme.menu"
        case .tagFilter: return "tagFilter.open"
        case .history: return "snapshotHistory.menu"
        case .upgrade: return "markdown.upgrade"
        case .more: return "editor.more"
        default: return nil
        }
    }

    private func commandMenuButton(_ id: EditorToolbarCommandID, action: @escaping () -> Void) -> some View {
        let helpText = commandHelp(id)
        return Button(action: action) {
            commandLabel(id, surface: .expandedMenu)
        }
        .disabled(!EditorToolbarCatalog.isEnabled(id, in: toolbarContext))
        .help(Text(verbatim: text(helpText)))
        .accessibilityHint(text(helpText))
        .modifier(CommandAccessibilityIdentifier(identifier: accessibilityIdentifier(for: id)))
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
            case .zoom: zoomMenu
            default: EmptyView()
            }
        case .submenu:
            switch id {
            case .link: linkCommandMenu(surface: .toolbar)
            case .viewMode: viewModeCommandMenu(surface: .toolbar)
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
            toolbarControl(id)
                .appleGlassChrome(.toolbarFloatingButton)
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
                Button(target.text.isEmpty ? "未命名" : target.text) {
                    session.linkSelectedTopic(to: target.id)
                }
            }
        } label: {
            commandLabel(.link, surface: surface)
        }
        .disabled(!EditorToolbarCatalog.isEnabled(.link, in: toolbarContext))
        .help(Text(verbatim: text(commandHelp(.link))))
        .accessibilityHint(text(commandHelp(.link)))
    }

    private var zoomMenu: some View {
        Menu {
            ForEach(ZoomStop.allCases, id: \.self) { stop in
                Button("\(stop.percent)%") { camera.zoom(to: stop) }
                    .explained(FlorettaL10n.format("把画布缩放到 %lld%%", locale: settings.resolvedLocale, arguments: [Int64(stop.percent)]))
            }
            commandMenuButton(.fit) { perform(.fit) }
                .keyboardShortcut("0", modifiers: .command)
        } label: {
            #if os(iOS)
            // The bottom status bar already hosts the zoom percent. An icon
            // here leaves room for editor.more on a compact phone.
            commandLabel(.zoom, surface: .toolbar)
            #else
            switch EditorToolbarCatalog.command(.zoom).toolbarFace {
            case .zoomPercent:
                Text("\(camera.chrome.zoomPercent)%")
                    .monospacedDigit()
            case .symbol:
                commandLabel(.zoom, surface: .toolbar)
            }
            #endif
        }
        .explained(EditorToolbarCatalog.command(.zoom).help)
        .appleGlassChrome(.toolbarFloatingButton)
    }

    private var shareMenu: some View {
        Menu {
            ForEach(EditorToolbarCatalog.menu(.share), id: \.self) { id in
                shareRow(id)
            }
        } label: {
            commandLabel(.share, surface: .toolbar)
        }
        .accessibilityLabel(text(EditorToolbarCatalog.command(.share).title))
        .help(Text(verbatim: text(EditorToolbarCatalog.command(.share).help)))
        .appleGlassChrome(.toolbarFloatingButton)
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

    private var moreMenu: some View {
        Menu {
            ForEach(EditorToolbarCatalog.menu(.more), id: \.self) { id in
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
    }

    @ViewBuilder
    private func moreRow(_ id: EditorToolbarCommandID) -> some View {
        if id == .viewMode {
            viewModeCommandMenu(surface: .expandedMenu)
        } else {
            commandMenuButton(id) { perform(id) }
        }
    }

    private func viewModeCommandMenu(surface: EditorCommandSurface) -> some View {
        Menu {
            ForEach(EditorToolbarCatalog.menu(.viewMode), id: \.self) { id in
                commandMenuButton(id) { perform(id) }
            }
        } label: {
            commandLabel(.viewMode, surface: surface)
        }
        .disabled(!EditorToolbarCatalog.isEnabled(.viewMode, in: toolbarContext))
        .help(Text(verbatim: text(commandHelp(.viewMode))))
    }

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
        // The header is an inset, not a sibling of the page. A short page
        // (演说, or 样式 with nothing selected) used to shrink the stack and
        // the column centered it, so 「检查器」 and the segments left the top
        // with the placeholder. The inset keeps a fixed-height header on the
        // top edge. Only the page below is flexible, and it is what scrolls.
        inspectorTabPage
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .safeAreaInset(edge: .top, spacing: 12) {
                inspectorHeader
            }
            .appleGlassChrome(.inspectorPanel)
            .containerRelativeFrame(.vertical, alignment: .top) { length, _ in length }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var inspectorHeader: some View {
        VStack(spacing: 8) {
            if showsSheetDismissHandle {
                // Taller than the segmented control, so the header's center is this
                // handle. A downward drag here dismisses the compact sheet. The same
                // drag on the segments selects 演说 instead, because that control
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
        case .presentation:
            presentationPage
        case .map:
            documentInfo
        }
    }

    @ViewBuilder
    private var stylePage: some View {
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

    private var presentationPage: some View {
        ContentUnavailableView {
            Label(text("尚未实现"), systemImage: "clock")
        } description: {
            Text(verbatim: text("演说"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("inspector.presentation")
    }

    private var documentInfo: some View {
        let facts = InspectorStyle.mapFacts(
            document: session.editingDocument,
            storedAttachmentBytes: session.attachmentCatalog.storedAttachmentBytes,
            archiveByteCount: session.archiveByteCount
        )
        return Form {
            Section {
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
        }
        .formStyle(.grouped)
        .appleGlassInspectorFormPlate()
        .accessibilityIdentifier("inspector.map")
    }

    private var relationshipLabelForm: some View {
        Form {
            Section(text("标签")) {
                TextField(text("标签"), text: relationshipTitle)
                    .onSubmit { commitRelationshipTitle() }
                    .help(Text(verbatim: text("编辑这条关系的标签")))
                    .accessibilityIdentifier("relationship.label")
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
                TextField(text("概要"), text: summaryText)
                    .onSubmit { commitMarkText() }
                    .help(Text(verbatim: text("编辑概要文字")))
                    .accessibilityIdentifier("summary.text")
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
                TextField(text("标题"), text: boundaryTitle)
                    .onSubmit { commitMarkText() }
                    .help(Text(verbatim: text("编辑边界标题")))
                    .accessibilityIdentifier("boundary.title")
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
        }
        .formStyle(.grouped)
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

    private func exportFlorettaCopy() throws {
        guard let archive = session.url else {
            exportFile = ExportFile(data: try SharePayload.bytes(for: "floretta", document: session.document))
            exportType = FlorettaFileTypes.contentType(forExport: "floretta")
            exportName = exportFilename(title: session.document.title, kind: "floretta")
            exportKind = "floretta"
            showExport = true
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
        showExport = true
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
            default:
                return
            }
            exportKind = kind
            exportFile = ExportFile(data: data)
            exportType = type
            exportName = exportFilename(title: title, kind: kind)
            showExport = true
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
        case "floretta": ext = "floretta"
        default: ext = "dat"
        }
        return title + "." + ext
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
            showExport = true
        }
    }

    private func pasteFromClipboard() {
        if let pasted = ImageClipboard.fileURL() {
            stageAttachment(pasted.url, ownsCopy: pasted.ownsCopy)
            return
        }
        #if os(macOS)
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        #else
        let text = UIPasteboard.general.string ?? ""
        #endif
        session.pasteClipboard(text)
    }

    private func textHelp(_ item: String) -> String {
        switch item {
        case "剪切": return "剪下选中节点的文字"
        case "拷贝": return "复制选中节点的文字"
        case "粘贴": return "把剪贴板里的图片放进节点；没有图片时粘贴文字"
        case "全选": return "选中当前节点里的全部文字"
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
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
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
        session.zenFullScreenApplied = active
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
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
            .accessibilityIdentifier("inspector.empty")
        }
    }

    private var appearanceForm: some View {
        Form {
            Section(text(InspectorStyleSection.topic.titleKey)) {
                Picker(text("形状"), selection: shape) {
                    ForEach(InspectorTopicShape.allCases) { item in
                        Text(verbatim: text(item.titleKey)).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("inspector.style.shape")
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
                LabeledContent(text("长度")) {
                    Text(verbatim: "\(Int(InspectorStyle.topicWidthValue(of: style)))px")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: topicWidth, in: InspectorStyle.topicWidthRange)
                    .accessibilityLabel(text("长度"))
                    .accessibilityIdentifier("inspector.style.topicWidth")
            }
            Section(text(InspectorStyleSection.border.titleKey)) {
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
            Section(text(InspectorStyleSection.text.titleKey)) {
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
            Section(text(InspectorStyleSection.links.titleKey)) {
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

/// Topic and word counts for the bottom bar. Mac keeps them on the trailing
/// edge, beside the zoom menu. iPhone and iPad keep them on the leading edge.
private struct TopicStatusBar: View {
    var census: TopicTitleCensus
    var locale: Locale

    var body: some View {
        HStack(spacing: 16) {
            count("主题: %lld", census.topics, identifier: "status.topics")
            count("字数: %lld", census.words, identifier: "status.words")
            #if os(iOS)
            count("字符数: %lld", census.characters, identifier: "status.characters")
            #endif
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(alignment: barAlignment)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(breakdown)
        .accessibilityIdentifier("status.topicCensus")
        .help(Text(verbatim: breakdown))
    }

    private var barAlignment: Alignment {
        #if os(macOS)
        .trailing
        #else
        .leading
        #endif
    }

    private var breakdown: String {
        [
            line("主题: %lld", census.topics),
            line("字数: %lld", census.words),
            line("字符数: %lld", census.characters),
        ].joined(separator: "\n")
    }

    private func count(_ key: String, _ value: Int, identifier: String) -> some View {
        Text(verbatim: line(key, value))
            .monospacedDigit()
            .accessibilityIdentifier(identifier)
    }

    private func line(_ key: String, _ value: Int) -> String {
        FlorettaL10n.format(key, locale: locale, arguments: [Int64(value)])
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

private struct MacEditorWindowTitle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        content.background(MacWindowTitleHider())
        #else
        content
        #endif
    }
}

#if os(macOS)
private struct MacWindowTitleHider: NSViewRepresentable {
    func makeNSView(context: Context) -> MacWindowTitleView {
        MacWindowTitleView()
    }

    func updateNSView(_ nsView: MacWindowTitleView, context: Context) {
        nsView.applyEditorChrome()
    }

    static func dismantleNSView(_ nsView: MacWindowTitleView, coordinator: ()) {
        MainActor.assumeIsolated {
            nsView.window?.titleVisibility = .visible
        }
    }
}

private final class MacWindowTitleView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyEditorChrome()
    }

    override func layout() {
        super.layout()
        applyEditorChrome()
    }

    /// The window title stays hidden so the filename lives in the toolbar.
    /// Icon-only is the editor toolbar's display mode. Each item's `Label`
    /// still carries its title for the overflow menu and the customization panel.
    func applyEditorChrome() {
        guard let window else { return }
        if window.titleVisibility != .hidden {
            window.titleVisibility = .hidden
        }
        if let toolbar = window.toolbar, toolbar.displayMode != .iconOnly {
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
    static func fileURL() -> (url: URL, ownsCopy: Bool)? {
        #if os(macOS)
        macFileURL()
        #else
        iosFileURL()
        #endif
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

    #if os(macOS)
    private static func macFileURL() -> (url: URL, ownsCopy: Bool)? {
        let board = NSPasteboard.general
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
        ]) as? [URL],
           let url = urls.first(where: { ImageInsertRoute.accepts(filename: $0.lastPathComponent) }) {
            return (url, false)
        }
        let types: [(NSPasteboard.PasteboardType, String)] = [
            (.png, "png"),
            (NSPasteboard.PasteboardType("public.jpeg"), "jpg"),
            (.tiff, "tiff"),
            (NSPasteboard.PasteboardType("com.compuserve.gif"), "gif"),
            (NSPasteboard.PasteboardType("public.heic"), "heic"),
        ]
        for (type, ext) in types {
            guard let data = board.data(forType: type), !data.isEmpty, let url = write(data, extension: ext) else { continue }
            return (url, true)
        }
        return nil
    }
    #else
    private static func iosFileURL() -> (url: URL, ownsCopy: Bool)? {
        let board = UIPasteboard.general
        if let url = board.url, ImageInsertRoute.accepts(filename: url.lastPathComponent) {
            return (url, false)
        }
        let types = ["public.png", "public.jpeg", "public.tiff", "com.compuserve.gif", "public.heic"]
        let extensions = ["png", "jpg", "tiff", "gif", "heic"]
        for (type, ext) in zip(types, extensions) {
            guard let data = board.data(forPasteboardType: type), !data.isEmpty, let url = write(data, extension: ext) else { continue }
            return (url, true)
        }
        return nil
    }
    #endif
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
