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
    @State private var inspectorTab = 0
    @State private var showAbout = false
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
                            .accessibilityLabel("返回")
                            .accessibilityIdentifier("basicChain.back")
                            .help("返回导图列表")
                            Button(action: beginRename) {
                                Text(documentTitle)
                                    .lineLimit(1)
                            }
                            .explained("为这份导图重新命名")
                        }
                    }
                    ToolbarItemGroup(placement: .principal) {
                        Button { session.undo() } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .accessibilityLabel("撤销")
                        .help("撤销上一步编辑")
                        Button { session.redo() } label: {
                            Image(systemName: "arrow.uturn.forward")
                        }
                        .accessibilityLabel("重做")
                        .help("恢复刚刚撤销的编辑")
                        Button { session.deleteSelection() } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("删除")
                        .help("删除选中的节点")
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        insertMenu
                        shareMenu
                        zoomMenu
                        Button(CanvasMenus.immersive) { session.enterZen() }
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
                    Button(item) { runTextCommand(item) }
                        .explained(textHelp(item))
                        .disabled(CanvasMenus.textDisabled.contains(item))
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
            .alert("无法导出", isPresented: exportErrorPresented) {
                Button("好", role: .cancel) {}
            } message: {
                Text(exportError ?? "")
            }
            .alert("重新命名", isPresented: $showRename) {
                TextField("名称", text: $renameText)
                Button("确定") {
                    let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !title.isEmpty { session.document.title = title }
                }
                Button("取消", role: .cancel) {}
            }
            .sheet(isPresented: $showAbout) {
                AboutSheet()
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
                guard let item = items.first else { return false }
                stageAttachment(item.url, ownsCopy: item.ownsCopy)
                return true
            }
            .confirmationDialog("放入附件？", isPresented: insertDialogPresented, titleVisibility: .visible) {
                Button("放入") { beginInsert() }
                Button("取消", role: .cancel) { cancelInsert() }
            } message: {
                Text(insertProposal?.confirmationMessage ?? "")
            }
            .alert("无法预览", isPresented: previewAlertPresented) {
                Button("好", role: .cancel) {}
            } message: {
                Text(previewPhase.alertMessage ?? "")
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
            .alert("查找", isPresented: $showFind) {
                TextField("文字", text: $findQuery)
                Button("查找") {
                    if let id = CanvasEditCommands.find(in: session.document, query: findQuery) {
                        session.keyboard.selectedNodeID = id
                    } else {
                        exportError = "没有找到。"
                    }
                }
                Button("取消", role: .cancel) {}
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
                }
            )
            .ignoresSafeArea()
            if showOutline, session.zen.chrome.showsSidebar {
                outlinePanel
                    .frame(width: outlineWide ? nil : 300)
                    .frame(maxWidth: outlineWide ? .infinity : 300, maxHeight: .infinity)
                    .background(.regularMaterial)
            }
        }
    }

    private var outlinePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("大纲").font(.headline)
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
            OutlineView(document: $session.document, keyboard: $session.keyboard)
        }
    }

    private var documentTitle: String {
        session.document.title.isEmpty ? "未命名" : session.document.title
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
    }

    private var insertMenu: some View {
        Menu {
            Button { session.addChildFromToolbar() } label: {
                Label("子节点", systemImage: "plus.square")
            }
            .help("在选中的节点下新建一个子节点")
            Button { session.addSiblingFromToolbar() } label: {
                Label("同级", systemImage: "square.on.square")
            }
            .help("在选中的节点旁新建一个同级节点")
            Button { session.addFreeNodeFromToolbar() } label: {
                Label("自由节点", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .help("在画布上放一个不进层级的节点，位置会保存")
            Menu {
                let source = session.keyboard.selectedNodeID
                let targets = session.document.linkTargets(excluding: source)
                if targets.isEmpty {
                    Button("没有其他节点") {}
                        .disabled(true)
                }
                ForEach(targets) { target in
                    Button(target.text.isEmpty ? "未命名" : target.text) {
                        session.linkSelectedFreeNode(to: target.id)
                    }
                }
            } label: {
                Label("连到", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
            .disabled(session.keyboard.selectedNodeID.map { session.document.isFreeNode($0) } != true)
            .help("把选中的自由节点连到另一个节点。只记下关系，不画线。")
            Button { showImageImporter = true } label: {
                Label("图片", systemImage: "photo")
            }
            .help("从文件选择一张图片放进选中的节点")
            Button { showAttachmentImporter = true } label: {
                Label("附件", systemImage: "paperclip")
            }
            .help("把一个文件原样放进选中的节点")
            Button { onImport() } label: {
                Label("从文件导入", systemImage: "folder")
            }
            .help("从文件打开另一份导图")
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("插入")
        .help("插入子节点、同级、自由节点、图片、附件，或从文件导入")
    }

    private var zoomMenu: some View {
        Menu {
            ForEach(ZoomStop.allCases, id: \.self) { stop in
                Button("\(stop.percent)%") { camera.zoom(to: stop) }
                    .explained("把画布缩放到 \(stop.percent)%")
            }
            Button("适应窗口") { camera.fitToContent() }
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
            Button("保存为 Floretta") { export("floretta") }
                .explained("把这份导图保存为 Floretta 文件")
            Button(".mm") { export("mm") }
                .explained("把这份导图导出为 FreeMind .mm")
            Button("OPML") { export("opml") }
                .explained("把这份导图导出为 OPML")
            Button(".xmind") { export("xmind") }
                .explained("导出为 XMind，自由节点写成浮动主题")
            #if os(macOS)
            Button("打印") { printMap() }
                .explained("打印这份导图")
            #endif
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel("分享")
        .help("把导图导出为 PDF、PNG、Markdown，或保存为已支持的文件")
    }

    private var moreMenu: some View {
        Menu {
            Button("大纲") { showOutline.toggle() }
                .explained("打开或关闭左侧大纲")
            Button("样式") { showInspector.toggle() }
                .explained("打开样式检查器，修改选中节点的外观")
            Menu("查看模式") {
                Button("地图模式") { session.viewMode = .map }
                    .explained("用整张地图查看导图")
                Button("聚焦模式") { session.viewMode = .focus }
                    .explained("只看当前选中的这一支")
            }
            .explained("在地图模式和聚焦模式之间切换")
            Button("新建画布") { session.addCanvas() }
                .explained("在这份导图里再加一个中心主题")
            Button("查找") {
                findQuery = ""
                showFind = true
            }
            .explained("按文字查找节点")
            Button("粘贴") { pasteFromClipboard() }
                .explained("把剪贴板里的图片放进节点；没有图片时粘贴文字")
            Button("关于") { showAbout = true }
                .explained("查看版本号和开源致谢")
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("更多")
        .help("大纲、样式和关于")
    }

    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { showInspector && !session.zen.isActive },
            set: { showInspector = $0 }
        )
    }

    private var inspectorBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("检查器", selection: $inspectorTab) {
                Text("样式").tag(0)
                Text("演说").tag(1)
                Text("导图").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            if inspectorTab == 0 {
                StyleInspector(document: $session.document, nodeID: session.keyboard.selectedNodeID)
            } else if inspectorTab == 2 {
                documentInfo
            } else {
                ContentUnavailableView {
                    Label("尚未实现", systemImage: "clock")
                } description: {
                    Text("演说")
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
            LabeledContent("附件合计") {
                Text(AttachmentByteFormat.label(total)).monospacedDigit()
            }
            LabeledContent("文档大小") {
                Text(AttachmentByteFormat.label(session.archiveByteCount)).monospacedDigit()
            }
            LabeledContent("引用") {
                Text("\(references.reduce(0) { $0 + $1.count })").monospacedDigit()
            }
            LabeledContent("节点") {
                Text("\(session.document.topicCount)").monospacedDigit()
            }
            LabeledContent("关系") {
                Text("\(session.document.relationships.count)").monospacedDigit()
            }
        }
        .formStyle(.grouped)
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

    private func beginInsert() {
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
                    let result = MapExporter.png(document: session.document, settings: settings)
                    guard let png = result.png, !png.isEmpty else {
                        exportError = result.notice ?? "没有导出图片。"
                        return
                    }
                    data = png
                } else {
                    let result = MapExporter.pdf(document: session.document)
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
        let options = kind == "png" ? MapExportOptions(settings: settings) : MapExportOptions()
        let scale = Double(options.scale.rawValue)
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
                ? MapExporter.png(document: document, options: options, images: images)
                : MapExporter.pdf(document: document, options: options, images: images)
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
        case "拷贝样式": return "复制选中节点的填充颜色"
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
        let result = MapExporter.pdf(document: session.document)
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

    var body: some View {
        if let nodeID, document.node(nodeID) != nil {
            Form {
                Section("主题") {
                    Picker("形状", selection: shape) {
                        Text("矩形").tag("rectangle")
                        Text("圆角").tag("rounded")
                        Text("胶囊").tag("capsule")
                        Text("无边框").tag("none")
                    }
                    Picker("填充样式", selection: fillStyle) {
                        Text("实心").tag("solid")
                        Text("无").tag("none")
                    }
                    ColorPicker("填充颜色", selection: fillColor, supportsOpacity: false)
                    HStack {
                        Text("长度")
                        Slider(value: topicWidth, in: 40...480)
                        Text("\(Int(topicWidth.wrappedValue))px")
                            .monospacedDigit()
                    }
                }
                Section("边框") {
                    Picker("样式", selection: borderStyle) {
                        Text("实线").tag("solid")
                        Text("无").tag("none")
                    }
                    HStack {
                        Text("宽度")
                        Slider(value: borderWidth, in: 0...8)
                    }
                    ColorPicker("颜色", selection: borderColor, supportsOpacity: false)
                }
                Section("文本") {
                    Picker("字体", selection: fontDesign) {
                        Text("系统").tag("default")
                        Text("衬线").tag("serif")
                        Text("圆体").tag("rounded")
                        Text("等宽").tag("monospaced")
                    }
                    HStack {
                        Toggle("B", isOn: boolFlag("bold"))
                        Toggle("I", isOn: boolFlag("italic"))
                        Toggle("S", isOn: boolFlag("strikethrough"))
                        Toggle("U", isOn: boolFlag("underline"))
                    }
                    .toggleStyle(.button)
                    HStack {
                        Text("大小")
                        Slider(value: fontSize, in: 10...64, step: 1)
                        Text("\(Int(fontSize.wrappedValue))pt")
                            .monospacedDigit()
                    }
                    ColorPicker("颜色", selection: textColor, supportsOpacity: false)
                }
                if document.isFreeNode(nodeID) {
                    Section("连到") {
                        let links = document.relationships.filter {
                            $0.sourceID == nodeID || $0.targetID == nodeID
                        }
                        if links.isEmpty {
                            Text("还没有连到其他节点。只保存关系，不画线。")
                        } else {
                            ForEach(links) { link in
                                Text(document.relationshipSummary(link, seenFrom: nodeID))
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView {
                Label("选择一个主题", systemImage: "paintbrush")
            } description: {
                Text("样式会写进导图文件。")
            }
        }
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
        guard let nodeID else { return }
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

private struct AboutSheet: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("版本 \(AppInfo.version)")
                        .font(.headline)
                    Text(AppInfo.notice)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("关于")
        }
    }
}

private extension View {
    func explained(_ sentence: String) -> some View {
        help(sentence).accessibilityLabel(sentence)
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
