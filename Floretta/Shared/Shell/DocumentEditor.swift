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
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showFind = false
    @State private var findQuery = ""
    @State private var showTagFilter = false
    @State private var inspectorTab = 0
    @State private var showAbout = false
    @State private var showThemes = false
    @Environment(\.colorScheme) private var colorScheme
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
            .inspector(isPresented: inspectorPresented) {
                inspectorBody
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 440)
            }
            .toolbar {
                if session.zen.chrome.showsToolbar {
                    ToolbarItem(placement: .cancellationAction) {
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
                    ToolbarItemGroup(placement: .principal) {
                        Button { session.undo() } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .accessibilityLabel(text("撤销"))
                        .help(Text(verbatim: text("撤销上一步编辑")))
                        Button { session.redo() } label: {
                            Image(systemName: "arrow.uturn.forward")
                        }
                        .accessibilityLabel(text("重做"))
                        .help(Text(verbatim: text("恢复刚刚撤销的编辑")))
                        Button { session.deleteSelection() } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel(text("删除"))
                        .help(Text(verbatim: text("删除选中的节点、便签、关系、概要或边界")))
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        insertMenu
                        shareMenu
                        zoomMenu
                        Button(text(CanvasMenus.immersive)) { session.enterZen() }
                            .explained("进入全屏沉浸模式，暂时只留下导图")
                        moreMenu
                    }
                }
            }
            #if os(macOS)
            .toolbarBackground(.hidden, for: .windowToolbar)
            #else
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
            .onChange(of: session.viewMode) { _, mode in
                guard mode == .focus else { return }
                if session.focusNodeID == nil {
                    session.focusNodeID = session.keyboard.selectedNodeID ?? session.document.roots.first?.id
                }
            }
            .onChange(of: session.document) { _, updated in
                onEdit(updated)
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
            .alert(Text(verbatim: text("查找")), isPresented: $showFind) {
                TextField(text("文字"), text: $findQuery)
                Button(text("查找")) {
                    if let id = CanvasEditCommands.find(in: session.document, query: findQuery) {
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
                document: $session.document,
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
                persistsPlacement: !session.isMarkdownDocument
            )
            .ignoresSafeArea()
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
        .background(.regularMaterial, in: Capsule())
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
                Button {
                    showOutline = false
                } label: {
                    Image(systemName: "xmark")
                }
                .explained("关闭大纲")
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
                document: $session.document,
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

    private func markdownHelp(_ control: MarkdownBlockedControl, otherwise sentence: String) -> String {
        session.isMarkdownDocument ? MarkdownModePolicy.reason(control) : sentence
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
        .padding(10)
        .background { Circle().fill(.ultraThinMaterial) }
        .explained("退出沉浸模式，恢复工具栏")
        .accessibilityIdentifier("zen.exit")
    }

    private var insertMenu: some View {
        Menu {
            Button { session.addChildFromToolbar() } label: {
                Label(text("子节点"), systemImage: "plus.square")
            }
            .help(Text(verbatim: text("在选中的节点下新建一个子节点")))
            Button { session.addSiblingFromToolbar() } label: {
                Label(text("同级"), systemImage: "square.on.square")
            }
            .help(Text(verbatim: text("在选中的节点旁新建一个同级节点")))
            Button { session.addFreeNodeFromToolbar() } label: {
                Label(text("自由节点"), systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .disabled(session.isMarkdownDocument)
            .help(Text(verbatim: text(markdownHelp(.freeNode, otherwise: "在画布上放一个不进层级的节点，位置会保存"))))
            .accessibilityHint(text(markdownHelp(.freeNode, otherwise: "在画布上放一个不进层级的节点，位置会保存")))
            Button { session.addStickyFromToolbar() } label: {
                Label(text("便签"), systemImage: "note.text")
            }
            .disabled(session.isMarkdownDocument)
            .help(Text(verbatim: text(markdownHelp(.sticky, otherwise: "在画布上放一张便签。最多五种颜色，不计入节点，可以拖动，大小有上限"))))
            .accessibilityHint(text(markdownHelp(.sticky, otherwise: "在画布上放一张便签。最多五种颜色，不计入节点，可以拖动，大小有上限")))
            Menu {
                let source = session.keyboard.selectedNodeID
                let targets = session.document.linkTargets(excluding: source)
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
                Label(text("连到"), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
            .disabled(session.isMarkdownDocument || session.keyboard.selectedNodeID == nil)
            .help(Text(verbatim: text(markdownHelp(.relationship, otherwise: "把选中的节点连到另一个节点，画布上会画出这条线。"))))
            .accessibilityHint(text(markdownHelp(.relationship, otherwise: "把选中的节点连到另一个节点，画布上会画出这条线。")))
            Button { session.addSummaryFromToolbar() } label: {
                Label(text("概要"), systemImage: "curlybraces")
            }
            .disabled(session.isMarkdownDocument || !session.document.canEnclose(session.keyboard.selectedNodeID))
            .help(Text(verbatim: text(markdownHelp(.summary, otherwise: "为选中的节点生成概要，并画出括住它的括号"))))
            .accessibilityHint(text(markdownHelp(.summary, otherwise: "为选中的节点生成概要，并画出括住它的括号")))
            Button { session.addBoundaryFromToolbar() } label: {
                Label(text("边界"), systemImage: "rectangle.dashed")
            }
            .disabled(session.isMarkdownDocument || !session.document.canEnclose(session.keyboard.selectedNodeID))
            .help(Text(verbatim: text(markdownHelp(.boundary, otherwise: "用边界圈住选中的节点"))))
            .accessibilityHint(text(markdownHelp(.boundary, otherwise: "用边界圈住选中的节点")))
            Button { showImageImporter = true } label: {
                Label(text("图片"), systemImage: "photo")
            }
            .disabled(session.isMarkdownDocument)
            .help(Text(verbatim: text(markdownHelp(.insertImage, otherwise: "从文件选择一张图片放进选中的节点"))))
            .accessibilityHint(text(markdownHelp(.insertImage, otherwise: "从文件选择一张图片放进选中的节点")))
            Button { showAttachmentImporter = true } label: {
                Label(text("附件"), systemImage: "paperclip")
            }
            .disabled(session.isMarkdownDocument)
            .help(Text(verbatim: text(markdownHelp(.insertAttachment, otherwise: "把一个文件原样放进选中的节点"))))
            .accessibilityHint(text(markdownHelp(.insertAttachment, otherwise: "把一个文件原样放进选中的节点")))
            Button { onImport() } label: {
                Label(text("从文件导入"), systemImage: "folder")
            }
            .help(Text(verbatim: text("从文件打开另一份导图")))
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel(text("插入"))
        .help(Text(verbatim: text("插入子节点、同级、自由节点、便签、概要、边界、图片、附件，或从文件导入")))
    }

    private var zoomMenu: some View {
        Menu {
            ForEach(ZoomStop.allCases, id: \.self) { stop in
                Button("\(stop.percent)%") { camera.zoom(to: stop) }
                    .explained(FlorettaL10n.format("把画布缩放到 %lld%%", locale: settings.resolvedLocale, arguments: [Int64(stop.percent)]))
            }
            Button(text("适应窗口")) { camera.fitToContent() }
                .explained("让整张导图缩进窗口里")
                .keyboardShortcut("0", modifiers: .command)
        } label: {
            Text("\(camera.chrome.zoomPercent)%")
                .monospacedDigit()
        }
        .explained("选择缩放比例，或让导图适应窗口")
    }

    private var shareMenu: some View {
        Menu {
            Button("PDF") { export("pdf") }
                .explained("把这份导图导出为 PDF")
            Button("PNG") { export("png") }
                .explained("把这份导图导出为 PNG 图片")
            Button("Markdown") { export("md") }
                .explained("把这份导图导出为 Markdown")
            if session.isMarkdownDocument {
                Button { beginUpgrade() } label: {
                    Label(text(MarkdownUpgrade.actionTitle), systemImage: "arrow.up.document")
                }
                .help(Text(verbatim: text("把当前导图另存为 Floretta 工程。原来的 Markdown 文件不会被改掉。")))
                .accessibilityIdentifier("markdown.upgrade")
            } else {
                Button(text("保存为 Floretta")) { export("floretta") }
                    .explained("把这份导图保存为 Floretta 文件")
            }
            Button(".mm") { export("mm") }
                .explained("把这份导图导出为 FreeMind .mm")
            Button("OPML") { export("opml") }
                .explained("把这份导图导出为 OPML")
            Button(".xmind") { export("xmind") }
                .explained("导出为 XMind，自由节点写成浮动主题")
            #if os(macOS)
            Button(text("打印")) { printMap() }
                .explained("打印这份导图")
            #endif
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel(text("分享"))
        .help(Text(verbatim: text("把导图导出为 PDF、PNG、Markdown，或保存为已支持的文件")))
    }

    private var moreMenu: some View {
        Menu {
            Button(text("大纲")) { showOutline.toggle() }
                .explained("打开或关闭左侧大纲")
            Button(text("样式")) { showInspector.toggle() }
                .disabled(session.isMarkdownDocument)
                .help(Text(verbatim: text(markdownHelp(.nodeColor, otherwise: "打开样式检查器，修改选中节点的外观"))))
                .accessibilityHint(text(markdownHelp(.nodeColor, otherwise: "打开样式检查器，修改选中节点的外观")))
            Button {
                showThemes = true
            } label: {
                Label(text("配色"), systemImage: "paintpalette")
            }
            .disabled(session.isMarkdownDocument)
            .help(Text(verbatim: text(markdownHelp(.themeColor, otherwise: "为各分支自动配色，浅色和深色各用一套"))))
            .accessibilityHint(text(markdownHelp(.themeColor, otherwise: "为各分支自动配色，浅色和深色各用一套")))
            .accessibilityIdentifier("theme.menu")
            Menu(text("查看模式")) {
                Button(text("地图模式")) { session.viewMode = .map }
                    .explained("用整张地图查看导图")
                Button(text("聚焦模式")) { session.viewMode = .focus }
                    .explained("只看当前选中的这一支")
            }
            .explained("在地图模式和聚焦模式之间切换")
            Button(text("新建画布")) { session.addCanvas() }
                .explained("在这份导图里再加一个中心主题")
            Button(text("查找")) {
                findQuery = ""
                showFind = true
            }
            .explained("按文字或标签查找节点")
            Button {
                showTagFilter = true
            } label: {
                Label(text("标签筛选"), systemImage: "tag")
            }
            .disabled(session.isMarkdownDocument)
            .help(Text(verbatim: text(markdownHelp(.tags, otherwise: "给选中的主题加上优先级、进度、旗帜或标签，并按标签高亮"))))
            .accessibilityHint(text(markdownHelp(.tags, otherwise: "给选中的主题加上优先级、进度、旗帜或标签，并按标签高亮")))
            .accessibilityIdentifier("tagFilter.open")
            Button(text("粘贴")) { pasteFromClipboard() }
                .explained("把剪贴板里的图片放进节点；没有图片时粘贴文字")
            Button(text("关于")) { showAbout = true }
                .explained("查看版本号和开源致谢")
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel(text("更多"))
        .help(Text(verbatim: text("大纲、样式、配色、标签筛选和关于")))
    }

    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { showInspector && !session.zen.isActive },
            set: { showInspector = $0 }
        )
    }

    private var inspectorBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(text("检查器"), selection: $inspectorTab) {
                Text(verbatim: text("样式")).tag(0)
                Text(verbatim: text("演说")).tag(1)
                Text(verbatim: text("导图")).tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            if inspectorTab == 0 {
                if session.keyboard.selectedRelationshipID != nil {
                    relationshipLabelForm
                } else if session.keyboard.selectedSummaryID != nil {
                    summaryTextForm
                } else if session.keyboard.selectedBoundaryID != nil {
                    boundaryTitleForm
                } else {
                    StyleInspector(
                        document: $session.document,
                        nodeID: session.keyboard.selectedNodeID,
                        locksAppearance: session.isMarkdownDocument,
                        onSelectRelationship: { id in
                            if session.keyboard.mode == .edit {
                                session.keyboard.apply(.commitEdit, document: &session.document, frames: [])
                            }
                            session.keyboard.selectedRelationshipID = id
                        }
                    )
                }
            } else if inspectorTab == 2 {
                documentInfo
            } else {
                ContentUnavailableView {
                    Label(text("尚未实现"), systemImage: "clock")
                } description: {
                    Text(verbatim: text("演说"))
                }
            }
        }
        .padding(.top, 12)
    }

    private var documentInfo: some View {
        let references = AttachmentReferences.counts(in: session.document)
        let stored = session.attachmentCatalog.storedAttachmentBytes
        let total = stored > 0 ? stored : references.reduce(Int64(0)) { $0 + $1.byteCount }
        return Form {
            LabeledContent(text("附件合计")) {
                Text(verbatim: AttachmentByteFormat.label(total)).monospacedDigit()
            }
            LabeledContent(text("文档大小")) {
                Text(verbatim: AttachmentByteFormat.label(session.archiveByteCount)).monospacedDigit()
            }
            LabeledContent(text("引用")) {
                Text(verbatim: "\(references.reduce(0) { $0 + $1.count })").monospacedDigit()
            }
            LabeledContent(text("节点")) {
                Text(verbatim: "\(session.document.topicCount)").monospacedDigit()
            }
            LabeledContent(text("便签")) {
                Text(verbatim: "\(session.document.stickies.count)").monospacedDigit()
            }
            LabeledContent(text("关系")) {
                Text(verbatim: "\(session.document.relationships.count)").monospacedDigit()
            }
            LabeledContent(text("概要")) {
                Text(verbatim: "\(session.document.summaryCount)").monospacedDigit()
            }
            LabeledContent(text("边界")) {
                Text(verbatim: "\(session.document.boundaryCount)").monospacedDigit()
            }
        }
        .formStyle(.grouped)
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
    }

    private var relationshipTitle: Binding<String> {
        Binding(
            get: {
                guard let id = session.keyboard.selectedRelationshipID else { return "" }
                if session.keyboard.editingRelationshipID == id {
                    return session.keyboard.editingText
                }
                return session.document.relationship(id)?.title ?? ""
            },
            set: { newValue in
                guard let id = session.keyboard.selectedRelationshipID else { return }
                if session.keyboard.editingRelationshipID != id {
                    session.keyboard.apply(.beginEdit, document: &session.document, frames: [])
                }
                session.keyboard.replaceEditingText(newValue, document: &session.document)
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
    }

    private var summaryText: Binding<String> {
        Binding(
            get: {
                guard let id = session.keyboard.selectedSummaryID else { return "" }
                if session.keyboard.editingSummaryID == id {
                    return session.keyboard.editingText
                }
                return session.document.summary(id)?.text ?? ""
            },
            set: { newValue in
                guard let id = session.keyboard.selectedSummaryID else { return }
                if session.keyboard.editingSummaryID != id {
                    session.keyboard.apply(.beginEdit, document: &session.document, frames: [])
                }
                session.keyboard.replaceEditingText(newValue, document: &session.document)
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
    }

    private var boundaryTitle: Binding<String> {
        Binding(
            get: {
                guard let id = session.keyboard.selectedBoundaryID else { return "" }
                if session.keyboard.editingBoundaryID == id {
                    return session.keyboard.editingText
                }
                return session.document.boundary(id)?.title ?? ""
            },
            set: { newValue in
                guard let id = session.keyboard.selectedBoundaryID else { return }
                if session.keyboard.editingBoundaryID != id {
                    session.keyboard.apply(.beginEdit, document: &session.document, frames: [])
                }
                session.keyboard.replaceEditingText(newValue, document: &session.document)
            }
        )
    }

    private func commitMarkText() {
        guard session.keyboard.mode == .edit else { return }
        session.keyboard.apply(.commitEdit, document: &session.document, frames: [])
    }

    private func commitRelationshipTitle() {
        guard session.keyboard.mode == .edit else { return }
        session.keyboard.apply(.commitEdit, document: &session.document, frames: [])
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
        let nodeID = session.keyboard.selectedNodeID ?? session.document.roots.first?.id
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
               let style = session.document.node(id)?.style {
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
            VStack(alignment: .leading, spacing: 8) {
                if locksAppearance {
                    Text(verbatim: text(MarkdownModePolicy.reason(.nodeColor)))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .accessibilityHint(text(MarkdownModePolicy.reason(.nodeColor)))
                }
                appearanceForm
            }
        } else {
            ContentUnavailableView {
                Label(text("选择一个主题"), systemImage: "paintbrush")
            } description: {
                Text(verbatim: text(locksAppearance ? MarkdownModePolicy.reason(.nodeColor) : "样式会写进导图文件。"))
            }
        }
    }

    private var appearanceForm: some View {
        Form {
                Section(text("主题")) {
                    Picker(text("形状"), selection: shape) {
                        Text(verbatim: text("矩形")).tag("rectangle")
                        Text(verbatim: text("圆角")).tag("rounded")
                        Text(verbatim: text("胶囊")).tag("capsule")
                        Text(verbatim: text("无边框")).tag("none")
                    }
                    Picker(text("填充样式"), selection: fillStyle) {
                        Text(verbatim: text("实心")).tag("solid")
                        Text(verbatim: text("无")).tag("none")
                    }
                    ColorPicker(selection: fillColor, supportsOpacity: false) {
                        Text(verbatim: text("填充颜色"))
                    }
                    HStack {
                        Text(verbatim: text("长度"))
                        Slider(value: topicWidth, in: 40...480)
                        Text("\(Int(topicWidth.wrappedValue))px")
                            .monospacedDigit()
                    }
                }
                Section(text("边框")) {
                    Picker(text("样式"), selection: borderStyle) {
                        Text(verbatim: text("实线")).tag("solid")
                        Text(verbatim: text("无")).tag("none")
                    }
                    HStack {
                        Text(verbatim: text("宽度"))
                        Slider(value: borderWidth, in: 0...8)
                    }
                    ColorPicker(selection: borderColor, supportsOpacity: false) {
                        Text(verbatim: text("颜色"))
                    }
                }
                Section(text("文本")) {
                    Picker(text("字体"), selection: fontDesign) {
                        Text(verbatim: text("系统")).tag("default")
                        Text(verbatim: text("衬线")).tag("serif")
                        Text(verbatim: text("圆体")).tag("rounded")
                        Text(verbatim: text("等宽")).tag("monospaced")
                    }
                    HStack {
                        Toggle("B", isOn: boolFlag("bold"))
                        Toggle("I", isOn: boolFlag("italic"))
                        Toggle("S", isOn: boolFlag("strikethrough"))
                        Toggle("U", isOn: boolFlag("underline"))
                    }
                    .toggleStyle(.button)
                    HStack {
                        Text(verbatim: text("大小"))
                        Slider(value: fontSize, in: 10...64, step: 1)
                        Text("\(Int(fontSize.wrappedValue))pt")
                            .monospacedDigit()
                    }
                    ColorPicker(selection: textColor, supportsOpacity: false) {
                        Text(verbatim: text("颜色"))
                    }
                }
                Section(text("连到")) {
                    if locksAppearance {
                        Text(verbatim: text(MarkdownModePolicy.reason(.relationship)))
                    } else if let nodeID {
                        let links = document.relationships.filter {
                            $0.sourceID == nodeID || $0.targetID == nodeID
                        }
                        if links.isEmpty {
                            Text(verbatim: text("还没有连到其他节点。"))
                        } else {
                            ForEach(links) { link in
                                Button {
                                    onSelectRelationship(link.id)
                                } label: {
                                    Text(verbatim: relationshipLine(link, seenFrom: nodeID))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(locksAppearance)
    }

    private var shape: Binding<String> {
        Binding(
            get: { shapeName },
            set: { name in
                let radius: Double
                let width: Double?
                switch name {
                case "rectangle": radius = 2; width = nil
                case "capsule": radius = 40; width = nil
                case "none": radius = 0; width = 0
                default: radius = 8; width = nil
                }
                update { style in
                    style.cornerRadius = radius
                    if let width { style.borderWidth = width; style.borderStyle = "none" }
                }
            }
        )
    }

    private var shapeName: String {
        guard let radius = style?.cornerRadius else { return "rounded" }
        if style?.borderStyle == "none" || style?.borderWidth == 0 { return "none" }
        if radius >= 24 { return "capsule" }
        if radius <= 3 { return "rectangle" }
        return "rounded"
    }

    private func text(_ key: String) -> String {
        FlorettaL10n.string(key, locale: locale)
    }

    /// Node text and relationship titles stay as stored. Only the missing-topic fallback is chrome.
    private func relationshipLine(_ link: TopicRelationship, seenFrom id: UUID) -> String {
        let otherID = link.sourceID == id ? link.targetID : link.sourceID
        let name = document.node(otherID)?.text ?? text("缺失的节点")
        if link.title.isEmpty { return name }
        return "\(name) · \(link.title)"
    }

    private var fillStyle: Binding<String> {
        Binding(
            get: { style?.fillStyle ?? "solid" },
            set: { value in update { $0.fillStyle = value } }
        )
    }

    private var fillColor: Binding<Color> {
        Binding(
            get: { StyleColor.color(hex: style?.fillHex ?? style?.colorHex ?? "#FFFFFF") },
            set: { color in
                guard !locksAppearance else { return }
                let hex = StyleColor.hex(color)
                guard let nodeID else { return }
                _ = CanvasEditCommands.setFill(hex: hex, nodeID: nodeID, document: &document)
            }
        )
    }

    private var topicWidth: Binding<Double> {
        Binding(
            get: { style?.topicWidth ?? 120 },
            set: { value in update { $0.topicWidth = value } }
        )
    }

    private var borderStyle: Binding<String> {
        Binding(
            get: { style?.borderStyle ?? "solid" },
            set: { value in
                update {
                    $0.borderStyle = value
                    if value == "none" { $0.borderWidth = 0 }
                }
            }
        )
    }

    private var borderWidth: Binding<Double> {
        Binding(
            get: { style?.borderWidth ?? 1.5 },
            set: { value in update { $0.borderWidth = value; $0.borderStyle = value == 0 ? "none" : "solid" } }
        )
    }

    private var borderColor: Binding<Color> {
        Binding(
            get: { StyleColor.color(hex: style?.borderHex ?? "#000000") },
            set: { color in update { $0.borderHex = StyleColor.hex(color) } }
        )
    }

    private var fontDesign: Binding<String> {
        Binding(
            get: { style?.fontDesign ?? "default" },
            set: { value in update { $0.fontDesign = value } }
        )
    }

    private var fontSize: Binding<Double> {
        Binding(
            get: { style?.fontSize ?? 18 },
            set: { value in update { $0.fontSize = value } }
        )
    }

    private var textColor: Binding<Color> {
        Binding(
            get: { StyleColor.color(hex: style?.textHex ?? "#000000") },
            set: { color in update { $0.textHex = StyleColor.hex(color) } }
        )
    }

    private func boolFlag(_ key: String) -> Binding<Bool> {
        Binding(
            get: {
                switch key {
                case "bold": return style?.bold ?? false
                case "italic": return style?.italic ?? false
                case "strikethrough": return style?.strikethrough ?? false
                case "underline": return style?.underline ?? false
                default: return false
                }
            },
            set: { value in
                update { style in
                    switch key {
                    case "bold": style.bold = value
                    case "italic": style.italic = value
                    case "strikethrough": style.strikethrough = value
                    case "underline": style.underline = value
                    default: break
                    }
                }
            }
        )
    }

    private var style: MindMapNodeStyle? {
        guard let nodeID else { return nil }
        return document.node(nodeID)?.style
    }

    private func update(_ body: (inout MindMapNodeStyle) -> Void) {
        guard !locksAppearance, let nodeID else { return }
        _ = document.mutateNode(nodeID) { node in
            var style = node.style ?? MindMapNodeStyle(colorHex: "#000000")
            body(&style)
            node.style = style
        }
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
                                if isSelected(theme) {
                                    Image(systemName: "checkmark")
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(text(theme.nameKey))
                        .accessibilityAddTraits(isSelected(theme) ? .isSelected : AccessibilityTraits())
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

    private func isSelected(_ theme: MapTheme) -> Bool {
        MapThemeCatalog.persistedID(theme.id) == MapThemeCatalog.persistedID(themeID)
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
        return session.document.node(id)
    }

    private var queryTrims: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredLabels: [String] {
        TopicTagIndex.labels(in: session.document).filter { TopicTagIndex.contains(query, in: $0) }
    }

    private var filteredMarkers: [String] {
        TopicTagIndex.markerIDs(in: session.document).filter { markerId in
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
        nsView.hideDocumentTitle()
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
        hideDocumentTitle()
    }

    override func layout() {
        super.layout()
        hideDocumentTitle()
    }

    func hideDocumentTitle() {
        guard let window, window.titleVisibility != .hidden else { return }
        window.titleVisibility = .hidden
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
