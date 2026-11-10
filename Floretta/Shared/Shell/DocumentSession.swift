import FlorettaCore
import Foundation
import Observation

/// Holds a security-scoped URL until the editor closes. `openFile` used to
/// stop access as soon as the bytes were read, so writing the same URL on
/// the way out failed and the edits never landed.
final class SecurityScopedURL {
    let url: URL
    private var started: Bool

    init(url: URL) {
        self.url = url
        started = url.startAccessingSecurityScopedResource()
    }

    func end() {
        guard started else { return }
        url.stopAccessingSecurityScopedResource()
        started = false
    }

    deinit {
        end()
    }
}

enum SharePayload {
    static func bytes(for kind: String, document: MindMapDocument) throws -> Data {
        switch kind {
        case "floretta":
            return try ZipContainer().write(FlorettaPackage(document: document))
        case "md":
            // Heading-depth 「导出为…」 preset. A `.md` document open/save uses
            // `FlorettaMarkdownDocumentCodec`, not this export.
            return Data(FlorettaMarkdown.export(document).utf8)
        case "opml":
            return try FlorettaOPMLCodec.export(document)
        case "mm":
            return try FlorettaMMCodec.export(document)
        case "xmind":
            return try FlorettaXMindCodec.export(document)
        default:
            throw DocumentOpenError.unsupported(kind)
        }
    }
}

enum AttachmentInserter {
    /// Hashes and stores after the user confirms. Does not read the source into one buffer.
    static func insert(
        source: URL,
        nodeID: UUID,
        document: MindMapDocument,
        archive: URL,
        files: any StreamingFilePort = FoundationStreamingFiles(),
        storedFilename: String? = nil
    ) throws -> (document: MindMapDocument, catalog: ZipDirectory, archiveByteCount: Int64) {
        let reader = try files.openReader(at: source)
        let hashed = try FlorettaStreamingDocument.hashSource(
            reader,
            filename: storedFilename ?? source.lastPathComponent
        )
        try reader.close()
        var attachment = try hashed.nodeAttachment()
        if files.fileExists(at: archive), try files.isZip(at: archive) {
            let archiveReader = try files.openReader(at: archive)
            let opened = try FlorettaStreamingDocument.open(archiveReader)
            try archiveReader.close()
            if let stored = opened.directory.attachments.first(where: { $0.sha256 == hashed.sha256 }),
               let parsed = AttachmentNames.parseAsset(stored.name) {
                attachment = NodeAttachment(
                    sha256: parsed.sha256,
                    fileExtension: parsed.fileExtension,
                    byteCount: Int64(min(stored.byteCount, UInt64(Int64.max))),
                    filename: hashed.filename
                )
            }
        }
        var updated = document
        guard updated.mutateNode(nodeID, { node in
            guard !node.attachments.contains(where: { $0.sha256 == attachment.sha256 }) else { return }
            node.attachments.append(attachment)
        }) else {
            throw DocumentContainerError.corrupt("No topic for the attachment.")
        }
        let catalog = try FlorettaStreamingDocument.save(
            document: updated,
            to: archive,
            files: files,
            appending: (source, hashed)
        )
        return (updated, catalog, try files.byteCount(at: archive))
    }
}

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

struct DocumentOpenPayload: Equatable, Sendable {
    var document: MindMapDocument
    var markdownWarnings: [FlorettaMarkdownDocumentWarning]
    /// True only when `FlorettaMarkdownDocumentCodec` opened the bytes.
    /// A `.md` name whose bytes are OPML or FreeMind stays on that format.
    var openedAsMarkdown: Bool
}

enum DocumentOpener {
    /// Bytes win over the filename. The open panel can label a FreeMind or OPML
    /// file as Markdown because `.mm` is also plain text on macOS.
    static func open(data: Data, filename: String) throws -> MindMapDocument {
        try openPayload(data: data, filename: filename).document
    }

    /// `.md` / `.markdown` opens through `FlorettaMarkdownDocumentCodec`.
    /// Failures keep the codec's `errorDescription`, including its line number.
    /// The heading-depth preset stays on `FlorettaMarkdown.importOutline`.
    static func openPayload(data: Data, filename: String) throws -> DocumentOpenPayload {
        let ext = (filename as NSString).pathExtension.lowercased()
        let format = sniffedFormat(data) ?? format(forExtension: ext)
        do {
            switch format {
            case .floretta:
                return DocumentOpenPayload(
                    document: try FlorettaDocumentFile.read(data: data).package.document,
                    markdownWarnings: [],
                    openedAsMarkdown: false
                )
            case .mm:
                return DocumentOpenPayload(
                    document: try FlorettaMMCodec.importMap(data),
                    markdownWarnings: [],
                    openedAsMarkdown: false
                )
            case .opml:
                return DocumentOpenPayload(
                    document: try FlorettaOPMLCodec.importOutline(data),
                    markdownWarnings: [],
                    openedAsMarkdown: false
                )
            case .markdown:
                let opened = try FlorettaMarkdownDocumentCodec.open(data)
                return DocumentOpenPayload(
                    document: opened.document,
                    markdownWarnings: opened.warnings,
                    openedAsMarkdown: true
                )
            case .xmind:
                return DocumentOpenPayload(
                    document: try FlorettaXMindCodec.importMap(data),
                    markdownWarnings: [],
                    openedAsMarkdown: false
                )
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
        case xmind
    }

    private static func format(forExtension ext: String) -> Format? {
        switch ext {
        case "floretta": .floretta
        case "mm": .mm
        case "opml": .opml
        case "md", "markdown": .markdown
        case "xmind": .xmind
        default: nil
        }
    }

    /// Nil when the bytes are not a map we know. Callers then trust the extension.
    private static func sniffedFormat(_ data: Data) -> Format? {
        if isZip(data) {
            if let names = try? ZipArchive.entryNames(data) {
                if names.contains("document.json") { return .floretta }
                if names.contains("content.json") { return .xmind }
            }
            return .floretta
        }
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
        if document.isInFreeNodeTree(focus) {
            copy.roots = []
            copy.freeNodes = [node]
            return copy
        }
        copy.roots = [node]
        copy.freeNodes = []
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
    var tagFilter = TopicTagFilter()
    var zen = ZenFlags()
    var focusNodeID: UUID?
    var zenEnteredFullScreen = false
    var attachmentCatalog = ZipDirectory(entries: [])
    var archiveByteCount: Int64 = 0
    /// Set from the open result. A `.md` filename is not enough: sniffed OPML or FreeMind is not Markdown mode.
    private(set) var markdownDocument: Bool
    private var savedProjection: MarkdownPersistableProjection?
    private var autosaveProjection: MarkdownPersistableProjection?
    private var warningPresentation = MarkdownWarningPresentation()
    private(set) var markdownWarningText: String?
    private(set) var markdownWarningDismissed = false
    var blockedNotice: String?
    /// Document at the last load or save. Used to tell a share on disk from an unsaved edit.
    var shareBase: MindMapDocument
    /// Bumps when the insert menu asks the focused field to start system dictation.
    var dictationToken = 0
    /// The new child still shows the placeholder, so the field selects it first.
    var dictationReplacesPlaceholder = false

    init(
        document: MindMapDocument,
        url: URL?,
        sourceExtension: String,
        viewMode: DocumentViewMode,
        markdownDocument: Bool? = nil
    ) {
        self.document = document
        self.url = url
        self.sourceExtension = sourceExtension
        self.viewMode = viewMode
        let markdown = markdownDocument ?? MarkdownModePolicy.isDocumentExtension(sourceExtension)
        self.markdownDocument = markdown
        self.shareBase = document
        focusNodeID = document.roots.first?.id
        keyboard.selectedNodeID = document.roots.first?.id
        if markdown {
            let projection = MarkdownPersistableProjection(document)
            savedProjection = projection
            autosaveProjection = projection
        }
    }

    var isMarkdownDocument: Bool { markdownDocument }

    /// The mode strip is visible for the whole time this session is a `.md` file.
    var markdownBannerVisible: Bool { isMarkdownDocument }

    var visibleMarkdownWarning: String? {
        guard isMarkdownDocument, !markdownWarningDismissed else { return nil }
        return markdownWarningText
    }

    var isMarkdownDirty: Bool {
        guard isMarkdownDocument, let savedProjection else { return false }
        return MarkdownPersistableProjection(document) != savedProjection
    }

    var acceptsAttachmentDrop: Bool { !isMarkdownDocument }

    func installMarkdownWarnings(_ warnings: [FlorettaMarkdownDocumentWarning]) {
        guard isMarkdownDocument else {
            markdownWarningText = nil
            return
        }
        markdownWarningText = warningPresentation.present(MarkdownModePolicy.notice(for: warnings))
        markdownWarningDismissed = markdownWarningText == nil
    }

    func dismissMarkdownWarning() {
        markdownWarningDismissed = true
    }

    func revealBlocked(_ reason: String) {
        blockedNotice = reason
    }

    func dismissBlockedNotice() {
        blockedNotice = nil
    }

    /// Crash recovery only notes a Markdown edit when the file's fields changed.
    func consumeAutosaveEdit(_ document: MindMapDocument) -> Bool {
        guard isMarkdownDocument else { return true }
        let next = MarkdownPersistableProjection(document)
        if next == autosaveProjection { return false }
        autosaveProjection = next
        return true
    }

    func markMarkdownSaved() {
        let projection = MarkdownPersistableProjection(document)
        savedProjection = projection
        autosaveProjection = projection
    }

    /// The session is now a `.floretta` file. The mode strip goes away.
    func leaveMarkdownMode() {
        markdownDocument = false
    }

    func notePackage(catalog: ZipDirectory, bytes: Int64) {
        attachmentCatalog = catalog
        archiveByteCount = bytes
    }

    var documentHasAttachments: Bool {
        !attachmentCatalog.attachments.isEmpty || !AttachmentReferences.hashes(in: document).isEmpty
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

    @discardableResult
    func updateSelectedTopicTags(_ body: (inout MindMapNode) -> Void) -> Bool {
        guard !isMarkdownDocument else { return false }
        if keyboard.mode == .edit {
            keyboard.apply(.commitEdit, document: &document, frames: [])
        }
        guard let id = keyboard.selectedNodeID else { return false }
        return keyboard.updateTopicTags(id, document: &document, body)
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

    /// Opens a child, or the editor already on screen, then asks for system dictation.
    /// The spoken string is written by the text view the same way typed text is.
    func beginDictation() {
        let preparation = DictationNodeInput.prepare(session: &keyboard, document: &document)
        guard preparation.target != .unavailable else { return }
        dictationReplacesPlaceholder = preparation.replacesPlaceholder
        dictationToken &+= 1
        if dictationToken == 0 { dictationToken = 1 }
    }

    /// Writes a finished system transcript. Blank speech does not create a topic.
    func applyDictatedText(_ phrase: String) {
        _ = DictationNodeInput.apply(phrase: phrase, session: &keyboard, document: &document)
    }

    func addFreeNodeFromToolbar() {
        guard !isMarkdownDocument else { return }
        finishEditingIfNeeded()
        guard keyboard.mode == .command, !keyboard.isComposing else { return }
        let index = document.freeNodes.count
        let point = MindMapPoint(x: 200 + Double(index) * 32, y: -160 - Double(index) * 28)
        _ = keyboard.addFreeNode(at: point, document: &document)
    }

    func addStickyFromToolbar() {
        guard !isMarkdownDocument else { return }
        finishEditingIfNeeded()
        guard keyboard.mode == .command, !keyboard.isComposing else { return }
        let index = document.stickies.count
        let point = MindMapPoint(x: -260 - Double(index) * 20, y: 72 + Double(index) * 24)
        _ = keyboard.addSticky(at: point, document: &document)
    }

    func linkSelectedTopic(to targetID: UUID) {
        guard !isMarkdownDocument else { return }
        finishEditingIfNeeded()
        guard keyboard.mode == .command, !keyboard.isComposing else { return }
        _ = keyboard.linkSelectedTopic(to: targetID, document: &document)
    }

    func addSummaryFromToolbar() {
        guard !isMarkdownDocument else { return }
        finishEditingIfNeeded()
        guard keyboard.mode == .command, !keyboard.isComposing else { return }
        _ = keyboard.addSummaryForSelection(document: &document)
    }

    func addBoundaryFromToolbar() {
        guard !isMarkdownDocument else { return }
        finishEditingIfNeeded()
        guard keyboard.mode == .command, !keyboard.isComposing else { return }
        _ = keyboard.addBoundaryForSelection(document: &document)
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

    /// Flush a finished edit into the document before it is written. Marked
    /// Chinese text is already on the node and stays there until the system
    /// text view confirms the candidate.
    func prepareToSave() {
        finishEditingIfNeeded()
    }

    /// Replace the selected node's text and commit it as one undo step.
    func commitText(_ text: String) {
        if keyboard.mode != .edit {
            keyboard.apply(.beginEdit, document: &document, frames: [])
        }
        keyboard.replaceEditingText(text, document: &document)
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

    func setBranchTheme(_ id: String) {
        guard !isMarkdownDocument else { return }
        finishEditingIfNeeded()
        guard keyboard.mode == .command, !keyboard.isComposing else { return }
        _ = keyboard.setBranchTheme(id, document: &document)
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
    var alertTitle = "无法打开"
    var openError: String?

    var canSaveActiveFile: Bool {
        guard let editor else { return false }
        if editor.isMarkdownDocument { return editor.url != nil }
        return editor.sourceExtension == "floretta" || editor.url == nil
    }
    var inventoryError: AssetInventoryError?
    var tab: ShellTab = .home
    var showInterruptedSave = false
    var interruptedTitle: String { interruptedPayload?.promptTitle ?? "保存未完成" }
    var interruptedMessage: String { interruptedPayload?.promptMessage ?? "" }
    var interruptedCanRestore: Bool { interruptedPayload?.canRestorePrevious ?? false }
    @ObservationIgnored private var interruptedPayload: InterruptedSave?
    @ObservationIgnored private var interruptedAccess: SecurityScopedURL?
    @ObservationIgnored private var scope: SecurityScopedURL?

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
        if let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            _ = try? AttachmentDirectory.prepare(applicationSupport: support, exclusion: ports.backup)
            thumbnailCache = ThumbnailFileCache(
                directory: AttachmentDirectory.thumbnails(applicationSupport: support)
            )
        } else {
            thumbnailCache = nil
        }
        reload()
    }

    let thumbnailCache: ThumbnailFileCache?

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

    /// Writes the two smoke-test maps into this library and remembers them.
    /// Used by the UI-test launch so the home list does not depend on personal files.
    func installSmokeFixtures() throws {
        for title in HomeLibrary.smokeFixtureTitles {
            let document = MindMapDocument(title: title, roots: [MindMapNode(text: "中心")])
            let url = documentsDirectory.appendingPathComponent("\(title).floretta")
            _ = try FlorettaStreamingDocument.save(
                document: document,
                to: url,
                files: ports.streaming,
                snapshots: .none
            )
            try store.remember(url)
        }
        reload()
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
        guard finishCurrentEditor() else { return }
        interruptedAccess?.end()
        interruptedAccess = nil
        interruptedPayload = nil
        showInterruptedSave = false
        let access = SecurityScopedURL(url: url)
        if let interrupted = SaveRecovery.inspect(documentAt: url, files: ports.streaming) {
            interruptedPayload = interrupted
            interruptedAccess = access
            showInterruptedSave = true
            return
        }
        do {
            let session = try openSession(at: url, access: access)
            try store.remember(url)
            reload()
            scope = access
            dismissOpenError()
            editor = session
        } catch let inventory as AssetInventoryError {
            access.end()
            inventoryError = inventory
            alertTitle = inventory.promptTitle
            openError = inventory.promptMessage
        } catch {
            access.end()
            inventoryError = nil
            alertTitle = "无法打开"
            openError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Drops the half-written sibling and opens the previous package when one exists.
    func restoreInterruptedSave() {
        guard let pending = interruptedPayload else { return }
        let url = pending.documentURL
        do {
            _ = try SaveRecovery.restorePrevious(documentAt: url, files: ports.streaming)
        } catch {
            inventoryError = nil
            alertTitle = "无法恢复"
            openError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }
        interruptedPayload = nil
        interruptedAccess?.end()
        interruptedAccess = nil
        showInterruptedSave = false
        openFile(url)
    }

    /// Removes the half-written sibling. Opens the file that is still there when recovery is possible.
    func discardInterruptedPartial() {
        guard let pending = interruptedPayload else { return }
        let url = pending.documentURL
        let canOpen = pending.canRestorePrevious
        try? SaveRecovery.discardPartial(documentAt: url, files: ports.streaming)
        interruptedPayload = nil
        interruptedAccess?.end()
        interruptedAccess = nil
        showInterruptedSave = false
        if canOpen {
            openFile(url)
        }
    }

    func openRecent(_ entry: RecentMapEntry) {
        guard let url = store.resolve(entry) else {
            store.remove(id: entry.id)
            reload()
            inventoryError = nil
            alertTitle = "无法打开"
            openError = "无法打开最近文件。"
            return
        }
        openFile(url)
    }

    /// Closes the canvas and returns to the library.
    /// True when a `.floretta` or the open `.md` was written, so the caller can drop the crash copy.
    /// A failed write leaves the editor open so the in-memory map is not discarded.
    /// A plain-JSON `.floretta` is not overwritten; the ZIP goes to a new file in the documents folder.
    /// A Markdown document is written back to the same URL.
    @discardableResult
    func closeEditor() -> Bool {
        guard let current = editor else { return false }
        let shouldWrite = shouldWriteOnClose(current)
        if shouldWrite {
            current.prepareToSave()
            do {
                try persist(current)
            } catch {
                inventoryError = nil
                alertTitle = "无法保存"
                openError = saveFailureMessage(error)
                return false
            }
        }
        editor = nil
        scope?.end()
        scope = nil
        if let url = current.url {
            try? store.remember(url)
        }
        reload()
        dismissOpenError()
        return shouldWrite
    }

    func dismissOpenError() {
        openError = nil
        inventoryError = nil
    }

    /// Share sheet "保存为 Floretta" already wrote `url`. Remember it, and if this
    /// session is not already a `.floretta` file, keep editing that copy.
    func noteExportedCopy(_ url: URL) {
        let access = SecurityScopedURL(url: url)
        do {
            try store.remember(url)
        } catch {
            access.end()
            inventoryError = nil
            alertTitle = "无法保存"
            openError = saveFailureMessage(error)
            return
        }
        reload()
        guard let editor else {
            access.end()
            return
        }
        // A Markdown document stays open. Upgrade asks before switching; this
        // share path must not close the `.md` or rewrite it.
        let adopt = !editor.isMarkdownDocument && (editor.url == nil || editor.sourceExtension != "floretta")
        if adopt {
            scope?.end()
            scope = access
            editor.url = url
            editor.sourceExtension = "floretta"
            editor.leaveMarkdownMode()
        } else {
            access.end()
        }
        dismissOpenError()
    }

    /// ⌘S. A Markdown document is written back to its own URL. A `.floretta` uses the existing package write.
    func saveActiveFile() {
        guard let current = editor, canSaveActiveFile else { return }
        current.prepareToSave()
        do {
            try persist(current)
            dismissOpenError()
        } catch {
            inventoryError = nil
            alertTitle = "无法保存"
            openError = saveFailureMessage(error)
        }
    }

    /// Remembers the Save-panel file. The default choice leaves the `.md` open and does not rewrite it.
    func finishMarkdownUpgrade(savedAt url: URL, choice: MarkdownUpgradeChoice) {
        guard let editor, editor.isMarkdownDocument else { return }
        if let current = editor.url, MarkdownUpgrade.replacesOriginal(destination: url, original: current) {
            inventoryError = nil
            alertTitle = "无法保存"
            openError = "不能覆盖原来的 Markdown 文件。"
            return
        }
        do {
            try store.remember(url)
        } catch {
            inventoryError = nil
            alertTitle = "无法保存"
            openError = saveFailureMessage(error)
            return
        }
        reload()
        switch choice {
        case .keepMarkdown:
            break
        case .openFloretta:
            openFile(url)
        }
    }

    /// False when the open `.floretta` or `.md` could not be written. The editor stays.
    private func finishCurrentEditor() -> Bool {
        guard editor != nil else { return true }
        closeEditor()
        return editor == nil
    }

    private func shouldWriteOnClose(_ session: EditorSession) -> Bool {
        if session.isMarkdownDocument { return session.url != nil }
        return session.sourceExtension == "floretta" || session.url == nil
    }

    private func persist(_ session: EditorSession) throws {
        if session.isMarkdownDocument {
            try persistMarkdown(session)
            return
        }
        try persistFloretta(session)
    }

    /// Canonical Markdown for this session, written to the file that was opened.
    private func persistMarkdown(_ session: EditorSession) throws {
        guard let url = session.url else {
            throw DocumentOpenError.message("先把导图存成文件。")
        }
        let text = FlorettaMarkdownDocumentCodec.save(session.document)
        try Data(text.utf8).write(to: url, options: .atomic)
        session.markMarkdownSaved()
    }

    private func persistFloretta(_ session: EditorSession) throws {
        absorbExternalShare()
        if let url = session.url {
            do {
                let catalog = try write(session.document, to: url)
                session.notePackage(catalog: catalog, bytes: (try? ports.streaming.byteCount(at: url)) ?? 0)
                session.shareBase = session.document
                return
            } catch DocumentContainerError.refusesToOverwriteLegacy {
                // The original JSON bytes stay put. The edited map goes to a new ZIP.
            }
        }
        let created = freshURL()
        let catalog = try write(session.document, to: created)
        session.url = created
        session.sourceExtension = "floretta"
        session.notePackage(catalog: catalog, bytes: (try? ports.streaming.byteCount(at: created)) ?? 0)
        session.shareBase = session.document
    }

    private func saveFailureMessage(_ error: Error) -> String {
        if let container = error as? DocumentContainerError, container == .refusesToOverwriteLegacy {
            return "这份还是旧的 JSON 文件，不能直接覆盖。请用「保存为 Floretta」另存。"
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func openDocument(_ document: MindMapDocument, preferredURL: URL?, sourceExtension: String) {
        guard finishCurrentEditor() else { return }
        let mode = settings.defaultView
        do {
            let url = preferredURL ?? freshURL()
            let catalog = try write(document, to: url)
            try store.remember(url)
            reload()
            dismissOpenError()
            let session = EditorSession(
                document: document,
                url: url,
                sourceExtension: sourceExtension,
                viewMode: mode
            )
            session.notePackage(catalog: catalog, bytes: (try? ports.streaming.byteCount(at: url)) ?? 0)
            editor = session
        } catch {
            inventoryError = nil
            alertTitle = "无法保存"
            openError = saveFailureMessage(error)
            editor = EditorSession(
                document: document,
                url: nil,
                sourceExtension: sourceExtension,
                viewMode: mode
            )
        }
    }

    @discardableResult
    private func write(_ document: MindMapDocument, to url: URL) throws -> ZipDirectory {
        let directory = try FlorettaStreamingDocument.save(document: document, to: url, files: ports.streaming)
        ShareCatalogStore.publish(url: url, document: document)
        return directory
    }

    /// Pulls a share that landed on disk while this editor was open.
    /// Unsaved topics stay. A topic deleted here is not put back.
    func absorbExternalShare() {
        guard let session = editor, let url = session.url, session.sourceExtension == "floretta" else { return }
        guard (try? ports.streaming.isZip(at: url)) == true else { return }
        let reader: RandomAccessReader
        do {
            reader = try ports.streaming.openReader(at: url)
        } catch {
            return
        }
        let opened: OpenedFloretta
        do {
            opened = try FlorettaStreamingDocument.open(reader)
            try reader.close()
        } catch {
            try? reader.close()
            return
        }
        let merged = ShareAbsorb.absorb(base: session.shareBase, mine: session.document, theirs: opened.document)
        // The baseline is the package just read. It still names topics this editor
        // deleted, so the next absorb does not put those topics back.
        session.shareBase = opened.document
        guard merged != session.document else { return }
        session.document = merged
        session.notePackage(
            catalog: opened.directory,
            bytes: (try? ports.streaming.byteCount(at: url)) ?? session.archiveByteCount
        )
    }

    /// Shortcuts entry. An open editor on the same file is updated in memory so a later save
    /// does not drop the topic or the unsaved edits around it.
    func saveShared(
        draft: ShareDraft,
        onto query: String,
        archive: URL,
        fileURL: URL?
    ) async throws -> ShareResult {
        absorbExternalShare()
        let files = ports.streaming
        let reader = try files.openReader(at: archive)
        let opened: OpenedFloretta
        do {
            opened = try FlorettaStreamingDocument.open(reader)
            try reader.close()
        } catch {
            try? reader.close()
            throw error
        }
        let sameEditor = editor?.url?.standardizedFileURL.path == archive.standardizedFileURL.path
        let memory = sameEditor ? editor?.document : nil
        let basis = memory ?? opened.document
        let nodeID: UUID
        switch ShareIngress.match(query, in: basis) {
        case .found(let id):
            nodeID = id
        case .none:
            throw ShareIngressError.unknownNode
        case .ambiguous:
            throw ShareIngressError.ambiguousNode
        }
        let result = try await Task.detached {
            try ShareCommit.commit(
                draft,
                onto: nodeID,
                archive: archive,
                fileURL: fileURL,
                files: FoundationStreamingFiles(),
                memory: memory,
                snapshots: .standard
            )
        }.value
        if sameEditor, let session = editor {
            session.document = result.document
            session.shareBase = result.document
            session.notePackage(
                catalog: result.directory,
                bytes: (try? files.byteCount(at: archive)) ?? session.archiveByteCount
            )
        }
        ShareCatalogStore.publish(url: archive, document: result.document)
        return result
    }

    private func openSession(at url: URL, access: SecurityScopedURL) throws -> EditorSession {
        let ext = url.pathExtension.lowercased()
        if ext == "floretta", try ports.streaming.isZip(at: url) {
            let reader = try ports.streaming.openReader(at: url)
            let opened: OpenedFloretta
            do {
                opened = try FlorettaStreamingDocument.open(reader)
                try FlorettaStreamingDocument.verifyInventory(reader, opened: opened)
            } catch {
                try? reader.close()
                throw error
            }
            let bytes = reader.count
            try reader.close()
            ShareCatalogStore.publish(url: url, document: opened.document)
            let session = EditorSession(
                document: opened.document,
                url: url,
                sourceExtension: ext,
                viewMode: settings.defaultView
            )
            session.notePackage(catalog: opened.directory, bytes: bytes)
            _ = access
            return session
        }
        let data = try Data(contentsOf: url)
        let payload = try DocumentOpener.openPayload(data: data, filename: url.lastPathComponent)
        let session = EditorSession(
            document: payload.document,
            url: url,
            sourceExtension: ext,
            viewMode: settings.defaultView,
            markdownDocument: payload.openedAsMarkdown
        )
        session.installMarkdownWarnings(payload.markdownWarnings)
        session.notePackage(catalog: ZipDirectory(entries: []), bytes: Int64(data.count))
        return session
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
    static let insert = ["子节点", "同级", "语音输入", "自由节点", "连到", "图片", "附件", "从文件导入"]
    static let share = ["PDF", "PNG", "Markdown", "保存为 Floretta", ".mm", "OPML", ".xmind", "打印"]
    static let zoom = ["50%", "75%", "100%", "125%", "150%", "200%", "300%", "400%", "适应窗口"]
    static let more = ["大纲", "样式", "配色", "查看模式", "新建画布", "查找", "标签筛选", "粘贴", "关于"]
    static let moreDisabled: [String] = []
    static let file = ["重新命名"]
    static let fileDisabled: [String] = []
    static let export = ["floretta", "mm", "opml", "md", "png", "pdf", "xmind"]
    static let text = ["剪切", "拷贝", "粘贴", "全选", "拷贝样式"]
    static let textDisabled: [String] = []
    static let omitted = [
        "立即升级", "投屏至图库", "方程帮助", "Word", "Excel", "Calendar",
        "ZEN", "Zen", "演说", "反馈", "投屏", "设置密码", "风格化分享",
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
        document.topics(matching: query).first
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
