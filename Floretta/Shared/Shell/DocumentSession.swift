import FlorettaCore
import Foundation
import Observation

enum DocumentOpenError: Error, Equatable, LocalizedError {
    case unsupported(String)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let name):
            return "不支持的文件类型 \(name)。"
        case .message(let text):
            return text
        }
    }
}

enum DocumentOpener {
    /// Bytes win over the filename. The open panel can label a FreeMind or OPML
    /// file as Markdown because `.mm` is also plain text on macOS.
    static func open(data: Data, filename: String) throws -> MindMapDocument {
        let ext = (filename as NSString).pathExtension.lowercased()
        let format = sniffedFormat(data) ?? format(forExtension: ext)
        do {
            switch format {
            case .floretta:
                return try FlorettaDocumentFile.read(data: data).package.document
            case .mm:
                return try FlorettaMMCodec.importMap(data)
            case .opml:
                return try FlorettaOPMLCodec.importOutline(data)
            case .markdown:
                return try FlorettaMarkdown.importOutline(data)
            case nil:
                throw DocumentOpenError.unsupported(ext.isEmpty ? filename : ext)
            }
        } catch let error as DocumentOpenError {
            throw error
        } catch {
            let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            throw DocumentOpenError.message(text)
        }
    }

    private enum Format {
        case floretta
        case mm
        case opml
        case markdown
    }

    private static func format(forExtension ext: String) -> Format? {
        switch ext {
        case "floretta": .floretta
        case "mm": .mm
        case "opml": .opml
        case "md", "markdown": .markdown
        default: nil
        }
    }

    /// Nil when the bytes are not a map we know. Callers then trust the extension.
    private static func sniffedFormat(_ data: Data) -> Format? {
        if isZip(data) { return .floretta }
        if isFlorettaJSON(data) { return .floretta }
        guard let prefix = String(data: data.prefix(4096), encoding: .utf8)?.lowercased() else {
            return nil
        }
        if prefix.contains("<opml") { return .opml }
        if prefix.contains("<map") { return .mm }
        return nil
    }

    private static func isZip(_ data: Data) -> Bool {
        data.count >= 2 && data[data.startIndex] == 0x50 && data[data.index(after: data.startIndex)] == 0x4b
    }

    private static func isFlorettaJSON(_ data: Data) -> Bool {
        guard let text = String(data: data.prefix(1024), encoding: .utf8) else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") && text.contains("\"formatVersion\"") && text.contains("\"roots\"")
    }
}

struct ZenChrome: Equatable, Sendable {
    var showsToolbar: Bool
    /// The shell owns the tab bar. The document editor keeps it hidden, Zen or not,
    /// so the editor toolbar and the home tab bar are never on screen together.
    var showsTabBar: Bool
    var showsStatusBar: Bool
    var showsSidebar: Bool
    var showsInspector: Bool

    static let editing = ZenChrome(
        showsToolbar: true,
        showsTabBar: false,
        showsStatusBar: true,
        showsSidebar: true,
        showsInspector: true
    )

    static let hidden = ZenChrome(
        showsToolbar: false,
        showsTabBar: false,
        showsStatusBar: false,
        showsSidebar: false,
        showsInspector: false
    )
}

struct ZenFlags: Equatable, Sendable {
    var isActive = false

    var chrome: ZenChrome { isActive ? .hidden : .editing }
}

enum ZenCommand {
    static func enter(_ flags: ZenFlags) -> ZenFlags {
        var copy = flags
        copy.isActive = true
        return copy
    }

    static func exit(_ flags: ZenFlags) -> ZenFlags {
        var copy = flags
        copy.isActive = false
        return copy
    }
}

enum FocusLayout {
    static func focusedDocument(_ document: MindMapDocument, focus: UUID?) -> MindMapDocument {
        guard let focus, let node = document.node(focus) else { return document }
        var copy = document
        copy.roots = [node]
        return copy
    }

    static func visibleIDs(_ document: MindMapDocument, focus: UUID?) -> [UUID] {
        CanvasPlacement.nodes(in: focusedDocument(document, focus: focus)).map(\.id)
    }

    static func chain(_ document: MindMapDocument, to id: UUID) -> [MindMapNode] {
        func walk(_ nodes: [MindMapNode], prefix: [MindMapNode]) -> [MindMapNode]? {
            for node in nodes {
                let path = prefix + [node]
                if node.id == id { return path }
                if let found = walk(node.children, prefix: path) { return found }
            }
            return nil
        }
        return walk(document.roots, prefix: []) ?? []
    }
}

@MainActor
@Observable
final class EditorSession {
    var document: MindMapDocument
    var url: URL?
    var sourceExtension: String
    var viewMode: DocumentViewMode
    var keyboard = MindMapKeyboardSession()
    var zen = ZenFlags()
    var focusNodeID: UUID?
    var zenEnteredFullScreen = false

    init(
        document: MindMapDocument,
        url: URL?,
        sourceExtension: String,
        viewMode: DocumentViewMode
    ) {
        self.document = document
        self.url = url
        self.sourceExtension = sourceExtension
        self.viewMode = viewMode
        focusNodeID = document.roots.first?.id
        keyboard.selectedNodeID = document.roots.first?.id
    }

    func enterZen() {
        zen = ZenCommand.enter(zen)
    }

    func exitZen() {
        zen = ZenCommand.exit(zen)
    }

    /// Esc while Zen is on leaves the document and the selection alone.
    @discardableResult
    func handleEscape() -> Bool {
        guard zen.isActive else { return false }
        exitZen()
        return true
    }

    /// Blank double-tap while Zen is on exits and must not edit the map.
    @discardableResult
    func consumeBlankDoubleTap() -> Bool {
        guard zen.isActive else { return false }
        exitZen()
        return true
    }

    func undo() {
        finishEditingIfNeeded()
        guard keyboard.mode == .command, !keyboard.isComposing else { return }
        let event = KeyEvent(key: .character("z"), modifiers: .command, mode: .command, isComposing: false)
        _ = keyboard.handle(event, document: &document, frames: [])
    }

    func redo() {
        finishEditingIfNeeded()
        guard keyboard.mode == .command, !keyboard.isComposing else { return }
        let event = KeyEvent(key: .character("Z"), modifiers: [.command, .shift], mode: .command, isComposing: false)
        _ = keyboard.handle(event, document: &document, frames: [])
    }

    func addChildFromToolbar() {
        finishEditingIfNeeded()
        guard keyboard.mode == .command, !keyboard.isComposing else { return }
        let event = KeyEvent(key: .tab, modifiers: [], mode: .command, isComposing: false)
        _ = keyboard.handle(event, document: &document, frames: [])
    }

    func addSiblingFromToolbar() {
        finishEditingIfNeeded()
        guard keyboard.mode == .command, !keyboard.isComposing else { return }
        let event = KeyEvent(key: .enter, modifiers: [], mode: .command, isComposing: false)
        _ = keyboard.handle(event, document: &document, frames: [])
    }

    func deleteSelection() {
        finishEditingIfNeeded()
        guard keyboard.mode == .command, !keyboard.isComposing else { return }
        let event = KeyEvent(key: .backspace, modifiers: [], mode: .command, isComposing: false)
        _ = keyboard.handle(event, document: &document, frames: [])
    }

    /// Toolbar actions arrive while a new node is still in the text view.
    /// Commit that edit first so create / delete / undo see command mode.
    private func finishEditingIfNeeded() {
        guard !keyboard.isComposing, keyboard.mode == .edit else { return }
        keyboard.apply(.commitEdit, document: &document, frames: [])
    }

    func pasteClipboard(_ text: String) {
        CanvasEditCommands.paste(text: text, document: &document, keyboard: &keyboard)
    }

    func cutSelection() -> String? {
        CanvasEditCommands.cut(document: &document, keyboard: &keyboard)
    }

    func copySelection() -> String? {
        CanvasEditCommands.copyText(document: document, nodeID: keyboard.selectedNodeID)
    }

    func selectCurrent() {
        CanvasEditCommands.select(document: &document, keyboard: &keyboard)
    }

    func addCanvas() {
        let id = CanvasEditCommands.addCanvas(to: &document)
        keyboard.selectedNodeID = id
    }
}

@MainActor
@Observable
final class LibraryModel {
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var store: RecentMapsStore
    @ObservationIgnored private let documentsDirectory: URL
    @ObservationIgnored private var saveDirectory: URL
    @ObservationIgnored private let ports: ApplePlatformPorts

    var documentsRoot: URL { documentsDirectory }

    var recents: [RecentMapEntry] = []
    var editor: EditorSession?
    var showImporter = false
    var openError: String?
    var tab: ShellTab = .home

    init(
        settings: AppSettings,
        store: RecentMapsStore,
        documentsDirectory: URL,
        ports: ApplePlatformPorts = .current()
    ) {
        self.settings = settings
        self.store = store
        self.documentsDirectory = documentsDirectory
        self.saveDirectory = documentsDirectory
        self.ports = ports
        reload()
    }

    func useDocumentsForNewFiles() {
        saveDirectory = documentsDirectory
    }

    @discardableResult
    func useICloudForNewFiles() -> Bool {
        guard let cloud = iCloudDocumentsDirectory() else { return false }
        saveDirectory = cloud
        return true
    }

    static let shared: LibraryModel = {
        let directory = (try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return LibraryModel(
            settings: .shared,
            store: RecentMapsStore(defaults: .standard),
            documentsDirectory: directory
        )
    }()

    func reload() {
        recents = store.load()
    }

    func makeNew() {
        let document = MindMapDocument(title: "未命名", roots: [MindMapNode(text: "中心")])
        openDocument(document, preferredURL: nil, sourceExtension: "floretta")
    }

    func makeTemplate(_ kind: TemplateKind) {
        openDocument(kind.document(), preferredURL: nil, sourceExtension: "floretta")
    }

    func openRecovered(_ document: MindMapDocument) {
        var copy = document
        if copy.title.isEmpty { copy.title = "未命名" }
        openDocument(copy, preferredURL: nil, sourceExtension: "floretta")
    }

    func openFile(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url)
            let document = try DocumentOpener.open(data: data, filename: url.lastPathComponent)
            try store.remember(url)
            reload()
            editor = EditorSession(
                document: document,
                url: url,
                sourceExtension: url.pathExtension.lowercased(),
                viewMode: settings.defaultView
            )
        } catch {
            openError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func openRecent(_ entry: RecentMapEntry) {
        guard let url = store.resolve(entry) else {
            store.remove(id: entry.id)
            reload()
            openError = "无法打开最近文件。"
            return
        }
        openFile(url)
    }

    /// Closes the canvas and returns to the library.
    /// True when a `.floretta` file was written, so the caller can drop the crash copy.
    @discardableResult
    func closeEditor() -> Bool {
        guard let current = editor else { return false }
        editor = nil
        var saved = false
        if current.sourceExtension == "floretta", let url = current.url {
            do {
                try FlorettaDocumentFile.save(
                    FlorettaPackage(document: current.document),
                    to: url,
                    fileAccess: ports.files
                )
                saved = true
            } catch {
                openError = error.localizedDescription
            }
        }
        if let url = current.url {
            try? store.remember(url)
        }
        reload()
        return saved
    }

    private func openDocument(_ document: MindMapDocument, preferredURL: URL?, sourceExtension: String) {
        let mode = settings.defaultView
        do {
            let url = try write(document, to: preferredURL ?? freshURL())
            try store.remember(url)
            reload()
            editor = EditorSession(
                document: document,
                url: url,
                sourceExtension: sourceExtension,
                viewMode: mode
            )
        } catch {
            openError = error.localizedDescription
            editor = EditorSession(
                document: document,
                url: nil,
                sourceExtension: sourceExtension,
                viewMode: mode
            )
        }
    }

    private func write(_ document: MindMapDocument, to url: URL) throws -> URL {
        try FlorettaDocumentFile.save(FlorettaPackage(document: document), to: url, fileAccess: ports.files)
        return url
    }

    func files(in directory: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let allowed = Set(FlorettaFileTypes.allowedExtensions)
        return urls.filter { url in
            let directory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if directory { return true }
            return allowed.contains(url.pathExtension.lowercased())
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    func iCloudDocumentsDirectory() -> URL? {
        guard let root = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        return documents
    }

    private func freshURL() -> URL {
        let manager = FileManager.default
        let first = saveDirectory.appendingPathComponent("未命名.floretta")
        if !manager.fileExists(atPath: first.path) { return first }
        for index in 2...999 {
            let url = saveDirectory.appendingPathComponent("未命名 \(index).floretta")
            if !manager.fileExists(atPath: url.path) { return url }
        }
        return saveDirectory.appendingPathComponent("未命名 \(UUID().uuidString).floretta")
    }
}

enum TemplateKind: String, Equatable, Sendable, CaseIterable {
    case mindMap
    case logic
    case brace
    case org
    case timeline
    case fishbone
    case swot
    case compare
    case okr
    case sevenQuestions
    case meeting
    case reading

    var name: String {
        switch self {
        case .mindMap: "左右思维导图"
        case .logic: "逻辑分解"
        case .brace: "括号图"
        case .org: "组织架构"
        case .timeline: "里程碑"
        case .fishbone: "鱼骨图"
        case .swot: "优劣势四象限"
        case .compare: "方案对照"
        case .okr: "目标树"
        case .sevenQuestions: "七何分析"
        case .meeting: "会议记录"
        case .reading: "读书笔记"
        }
    }

    var symbol: String {
        switch self {
        case .mindMap: "map"
        case .logic: "arrow.triangle.branch"
        case .brace: "curlybraces"
        case .org: "rectangle.3.group"
        case .timeline: "calendar"
        case .fishbone: "fish"
        case .swot: "square.grid.2x2"
        case .compare: "rectangle.split.2x1"
        case .okr: "target"
        case .sevenQuestions: "questionmark"
        case .meeting: "person.2"
        case .reading: "book"
        }
    }

    var section: String {
        switch self {
        case .mindMap, .logic, .brace, .org, .timeline, .fishbone:
            "结构"
        case .swot, .compare, .okr, .sevenQuestions:
            "分析"
        case .meeting, .reading:
            "记录"
        }
    }

    func document() -> MindMapDocument {
        MindMapDocument(title: name, roots: [root])
    }

    /// Child-count signature. Two templates that only recolor the same tree share a signature.
    static func shape(_ document: MindMapDocument) -> String {
        func walk(_ nodes: [MindMapNode], depth: Int) -> String {
            nodes.map { node in
                "\(depth):\(node.children.count)[\(walk(node.children, depth: depth + 1))]"
            }.joined(separator: ",")
        }
        return walk(document.roots, depth: 0)
    }

    private var root: MindMapNode {
        switch self {
        case .mindMap:
            return topic("周末出行", [
                topic("去程", [topic("高铁"), topic("市内")]),
                topic("预算", [topic("住宿"), topic("餐饮")]),
                topic("行程", [topic("古城"), topic("海边")]),
                topic("行装", [topic("证件"), topic("常备药")]),
            ])
        case .logic:
            return topic("把文章写清楚", [
                topic("先定读者", [topic("给谁看")]),
                topic("一句论点", [topic("证据"), topic("反例")]),
                topic("先写结论"),
                topic("删掉空话"),
            ])
        case .brace:
            return topic("菜市场", [
                topic("叶菜", [topic("菠菜"), topic("生菜"), topic("油麦菜")]),
                topic("根茎", [topic("萝卜"), topic("土豆"), topic("莲藕")]),
            ])
        case .org:
            return topic("邻里食堂", [
                topic("前厅", [topic("领位"), topic("收银")]),
                topic("厨房", [topic("热菜"), topic("面点")]),
                topic("采购", [topic("供应商"), topic("库存")]),
            ])
        case .timeline:
            return topic("产品发布", [
                topic("立项", [topic("范围说明")]),
                topic("设计", [topic("线框确认")]),
                topic("开发", [topic("内测包")]),
                topic("上架", [topic("发布说明")]),
            ])
        case .fishbone:
            return topic("交货延误", [
                topic("人员", [topic("交接没做完"), topic("请假撞车")]),
                topic("设备", [topic("烤箱故障"), topic("车不够")]),
                topic("材料", [topic("面粉晚到"), topic("包装缺货")]),
                topic("方法", [topic("排产写错"), topic("质检来回")]),
                topic("环境", [topic("暴雨封路"), topic("午后停电")]),
            ])
        case .swot:
            return topic("社区书店", [
                topic("优势", [topic("走路就到"), topic("店员认得熟客")]),
                topic("劣势", [topic("租金高")]),
                topic("机会", [topic("对面是学校"), topic("有人要夜读")]),
                topic("威胁", [topic("商场里的大店")]),
            ])
        case .compare:
            return topic("选办公地点", [
                topic("旧楼", [topic("月租"), topic("通勤"), topic("装修")]),
                topic("园区", [topic("月租"), topic("通勤")]),
                topic("待定", [topic("是否合租")]),
            ])
        case .okr:
            return topic("复购做到三成", [
                topic("月回头客一百人", [topic("会员日"), topic("到期提醒")]),
                topic("客诉七天内回完", [topic("值班表")]),
                topic("新品两周一上", [topic("试吃记录")]),
            ])
        case .sevenQuestions:
            return topic("办一场读书会", [
                topic("何人：常客和店员"),
                topic("何事：共读一章"),
                topic("何时：周四晚七点"),
                topic("何地：二楼靠窗"),
                topic("何因：让人愿意再来"),
                topic("如何：一人朗读"),
                topic("何价：茶水自备"),
            ])
        case .meeting:
            return topic("周三店务会", [
                topic("议题", [topic("周末人流怎么接")]),
                topic("决定", [topic("多开一台咖啡机")]),
                topic("待办", [topic("周五前排班"), topic("阿宁负责")]),
                topic("未决", [topic("要不要延到九点")]),
            ])
        case .reading:
            return topic("动物园长的故事", [
                topic("人物", [topic("管理员老周")]),
                topic("情节", [topic("幼虎拒食"), topic("改了喂食时间")]),
                topic("摘句", [topic("动物不是展品")]),
                topic("我的看法", [topic("先看它自己的节奏")]),
            ])
        }
    }

    private func topic(_ text: String, _ children: [MindMapNode] = []) -> MindMapNode {
        MindMapNode(text: text, children: children)
    }
}

struct TemplateSection: Identifiable, Equatable, Sendable {
    var title: String
    var cards: [TemplateCard]
    var id: String { title }
}

struct TemplateCard: Identifiable, Equatable, Sendable {
    var kind: TemplateKind
    var name: String { kind.name }
    var symbol: String { kind.symbol }
    var id: String { kind.rawValue }
    var createsDocument: Bool { true }
}

enum TemplateCatalog {
    static let sections: [TemplateSection] = [
        TemplateSection(title: "结构", cards: [
            .mindMap, .logic, .brace, .org, .timeline, .fishbone,
        ].map { TemplateCard(kind: $0) }),
        TemplateSection(title: "分析", cards: [
            .swot, .compare, .okr, .sevenQuestions,
        ].map { TemplateCard(kind: $0) }),
        TemplateSection(title: "记录", cards: [
            .meeting, .reading,
        ].map { TemplateCard(kind: $0) }),
    ]
}

enum HomePage: String, Hashable, Sendable {
    case recent
    case newMap
    case browse
}

/// Menu rows that are allowed to appear. Disabled rows are listed separately.
enum CanvasMenus {
    static let immersive = "全屏沉浸"
    static let insert = ["子节点", "同级", "从文件导入"]
    static let share = ["PDF", "PNG", "Markdown", "保存为 Floretta", ".mm", "OPML", "打印"]
    static let zoom = ["50%", "75%", "100%", "125%", "150%", "200%", "300%", "400%", "适应窗口"]
    static let more = ["大纲", "样式", "查看模式", "新建画布", "查找", "粘贴", "关于"]
    static let moreDisabled: [String] = []
    static let file = ["重新命名"]
    static let fileDisabled: [String] = []
    static let export = ["floretta", "mm", "opml", "md", "png", "pdf"]
    static let text = ["剪切", "拷贝", "粘贴", "全选", "拷贝样式"]
    static let textDisabled: [String] = []
    static let omitted = [
        "立即升级", "投屏至图库", "方程帮助", "Word", "Excel", "Calendar",
        "ZEN", "Zen", ".xmind", "XMind", "演说", "反馈", "投屏", "设置密码", "风格化分享",
        "生成想法", "AI 工作分解", "关系线", "Add Page", "Canvas",
    ]
}

enum CanvasEditCommands {
    static func copyText(document: MindMapDocument, nodeID: UUID?) -> String? {
        guard let nodeID else { return nil }
        return document.node(nodeID)?.text
    }

    @MainActor
    static func cut(document: inout MindMapDocument, keyboard: inout MindMapKeyboardSession) -> String? {
        guard let text = copyText(document: document, nodeID: keyboard.selectedNodeID) else { return nil }
        keyboard.mode = .command
        let event = KeyEvent(key: .backspace, modifiers: [], mode: .command, isComposing: false)
        _ = keyboard.handle(event, document: &document, frames: [])
        return text
    }

    static func paste(text: String, document: inout MindMapDocument, keyboard: inout MindMapKeyboardSession) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let id = keyboard.selectedNodeID else { return }
        if keyboard.mode == .edit {
            keyboard.replaceEditingText(keyboard.editingText + trimmed, document: &document)
            return
        }
        let child = MindMapNode(text: trimmed)
        guard document.insertChild(child, under: id) else { return }
        keyboard.selectedNodeID = child.id
    }

    @MainActor
    static func select(document: inout MindMapDocument, keyboard: inout MindMapKeyboardSession) {
        guard keyboard.selectedNodeID != nil else { return }
        keyboard.mode = .command
        let event = KeyEvent(key: .space, modifiers: [], mode: .command, isComposing: false)
        _ = keyboard.handle(event, document: &document, frames: [])
    }

    static func find(in document: MindMapDocument, query: String) -> UUID? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        func walk(_ nodes: [MindMapNode]) -> UUID? {
            for node in nodes {
                if node.text.localizedCaseInsensitiveContains(needle) { return node.id }
                if let found = walk(node.children) { return found }
            }
            return nil
        }
        return walk(document.roots)
    }

    static func addCanvas(to document: inout MindMapDocument) -> UUID {
        let node = MindMapNode(text: "新画布")
        document.roots.append(node)
        return node.id
    }

    static func setFill(hex: String, nodeID: UUID, document: inout MindMapDocument) -> Bool {
        document.mutateNode(nodeID) { node in
            var style = node.style ?? MindMapNodeStyle(colorHex: hex)
            style.fillHex = hex
            style.colorHex = hex
            style.fillStyle = "solid"
            node.style = style
        }
    }
}
