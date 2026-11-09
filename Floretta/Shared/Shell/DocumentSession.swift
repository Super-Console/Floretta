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
    static func open(data: Data, filename: String) throws -> MindMapDocument {
        let ext = (filename as NSString).pathExtension.lowercased()
        do {
            switch ext {
            case "floretta":
                return try FlorettaDocumentFile.read(data: data).package.document
            case "mm":
                return try FlorettaMMCodec.importMap(data)
            case "opml":
                return try FlorettaOPMLCodec.importOutline(data)
            case "md", "markdown":
                return try FlorettaMarkdown.importOutline(data)
            default:
                throw DocumentOpenError.unsupported(ext.isEmpty ? filename : ext)
            }
        } catch let error as DocumentOpenError {
            throw error
        } catch {
            let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            throw DocumentOpenError.message(text)
        }
    }
}

struct ZenChrome: Equatable, Sendable {
    var showsToolbar: Bool
    var showsTabBar: Bool
    var showsStatusBar: Bool
    var showsSidebar: Bool
    var showsInspector: Bool

    static let editing = ZenChrome(
        showsToolbar: true,
        showsTabBar: true,
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
        let event = KeyEvent(key: .character("z"), modifiers: .command, mode: .command, isComposing: false)
        guard keyboard.mode == .command else { return }
        _ = keyboard.handle(event, document: &document, frames: [])
    }

    func addChildFromToolbar() {
        keyboard.mode = .command
        let event = KeyEvent(key: .tab, modifiers: [], mode: .command, isComposing: false)
        _ = keyboard.handle(event, document: &document, frames: [])
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

    var documentsRoot: URL { documentsDirectory }

    var recents: [RecentMapEntry] = []
    var editor: EditorSession?
    var showImporter = false
    var openError: String?
    var tab: ShellTab = .home

    init(settings: AppSettings, store: RecentMapsStore, documentsDirectory: URL) {
        self.settings = settings
        self.store = store
        self.documentsDirectory = documentsDirectory
        self.saveDirectory = documentsDirectory
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
                try FlorettaDocumentFile.save(FlorettaPackage(document: current.document), to: url)
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
        try FlorettaDocumentFile.save(FlorettaPackage(document: document), to: url)
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

enum TemplateTap: Equatable, Sendable {
    case createMindMap
    case laterLayout
    case comingSoon
}

struct TemplateSection: Identifiable, Equatable, Sendable {
    var title: String
    var cards: [TemplateCard]
    var id: String { title }
}

struct TemplateCard: Identifiable, Equatable, Sendable {
    var name: String
    var symbol: String
    var tap: TemplateTap
    var id: String { name }

    var createsDocument: Bool { tap == .createMindMap }
}

enum TemplateCatalog {
    static let laterLayoutNotice = "该布局将在后续版本提供"
    static let comingSoonNotice = "即将推出"
    static let seeAllNotice = "敬请期待"

    static let sections: [TemplateSection] = [
        TemplateSection(title: "基本", cards: [
            TemplateCard(name: "思维导图", symbol: "map", tap: .createMindMap),
            TemplateCard(name: "逻辑图", symbol: "arrow.triangle.branch", tap: .laterLayout),
            TemplateCard(name: "括号图", symbol: "curlybraces", tap: .laterLayout),
            TemplateCard(name: "组织结构图", symbol: "rectangle.3.group", tap: .laterLayout),
            TemplateCard(name: "树形图", symbol: "tree", tap: .laterLayout),
            TemplateCard(name: "时间轴", symbol: "calendar", tap: .laterLayout),
        ]),
        TemplateSection(title: "知识管理", cards: names([
            "解决问题的步骤", "GRAP 框架基础", "航天器", "建筑图示", "品牌探索", "气候变化",
        ])),
        TemplateSection(title: "会议和计划", cards: names([
            "商业计划", "协调即将发布的1.0版本", "工作坊", "论文计划", "活动公司夏季野餐会", "求职",
        ])),
        TemplateSection(title: "学习和教育", cards: names([
            "学校课程表", "如何高效做笔记", "英语口语能力", "AR 应用程序", "气候变化解决方案", "博士学位论文",
        ])),
    ]

    private static func names(_ values: [String]) -> [TemplateCard] {
        values.map { TemplateCard(name: $0, symbol: "doc", tap: .comingSoon) }
    }
}

enum HomePage: String, Hashable, Sendable {
    case recent
    case newMap
    case browse
}

/// Menu rows that are allowed to appear. Disabled rows are listed separately.
enum CanvasMenus {
    static let more = ["查看模式", "新建画布", "演说", "ZEN", "查找", "反馈"]
    static let moreDisabled = ["演说", "反馈"]
    static let file = ["重新命名", "设置密码", "风格化分享", "导出", "保存至", "打印"]
    static let fileDisabled = ["设置密码", "风格化分享"]
    static let export = ["floretta", "mm", "opml", "md", "png", "pdf"]
    static let share = ["导出", "保存至"]
    static let text = ["剪切", "拷贝", "粘贴", "全选", "拷贝样式", "生成想法", "AI 工作分解"]
    static let textDisabled = ["生成想法", "AI 工作分解"]
    static let omitted = ["立即升级", "投屏至图库", "方程帮助", "Word", "Excel", "Calendar"]
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
