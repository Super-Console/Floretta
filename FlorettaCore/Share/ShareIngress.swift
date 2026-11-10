import Foundation

/// Where a share came from. Safari keeps the page. Photos keeps the file.
/// Shortcuts names the origin itself.
public enum ShareOrigin: String, Equatable, Sendable {
    case safari
    case photos
    case shortcuts
}

/// One thing to store. File bytes stay on disk; this value is only the name and the length.
public enum SharePayloadKind: Equatable, Sendable {
    case webPage(url: String, title: String)
    case plainText(String)
    case file(filename: String, byteCount: Int64)
}

public struct ShareDraft: Equatable, Sendable {
    public var origin: ShareOrigin
    public var kind: SharePayloadKind

    public init(origin: ShareOrigin, kind: SharePayloadKind) {
        self.origin = origin
        self.kind = kind
    }
}

/// `stat` of a shared file. The bytes are not here.
public struct ShareFileFact: Equatable, Sendable {
    public var filename: String
    public var byteCount: Int64
    public var isDirectory: Bool

    public init(filename: String, byteCount: Int64, isDirectory: Bool) {
        self.filename = filename
        self.byteCount = byteCount
        self.isDirectory = isDirectory
    }
}

public enum ShareIngressError: Error, Equatable, Sendable {
    case unknownNode
    case ambiguousNode
    case emptyPayload
    case notAFile
    case directory
    case textTooLarge
    case notAPackage
    case missingFile
    case notWritableCopy
}

extension ShareIngressError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unknownNode:
            return "找不到这个节点。"
        case .ambiguousNode:
            return "有多个同名节点，请写上路径。"
        case .emptyPayload:
            return "没有可以存入的内容。"
        case .notAFile:
            return "这不是一个文件。"
        case .directory:
            return "不能存入文件夹。"
        case .textTooLarge:
            return "这段文字太长，请改用文件附件。"
        case .notAPackage:
            return "这不是 Floretta 导图。"
        case .missingFile:
            return "找不到要存入的文件。"
        case .notWritableCopy:
            return "这份导图只能打开副本，没法写回原文件。"
        }
    }
}

/// A topic the share sheet or a shortcut can name.
public struct ShareTopicChoice: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var path: String
    public var depth: Int
    /// Free topics do not grow a branch. Text lands on the topic itself.
    public var acceptsChild: Bool

    public init(id: UUID, title: String, path: String, depth: Int, acceptsChild: Bool) {
        self.id = id
        self.title = title
        self.path = path
        self.depth = depth
        self.acceptsChild = acceptsChild
    }
}

public enum ShareNodeMatch: Equatable, Sendable {
    case found(UUID)
    case none
    case ambiguous
}

/// What `commit` changed. `directory` is the ZIP catalog after the write, not the file bytes.
public struct ShareResult: Equatable, Sendable {
    public var nodeID: UUID
    public var childID: UUID?
    public var attachment: NodeAttachment?
    public var proposal: AttachmentInsertProposal?
    public var deduplicated: Bool
    public var storedOnNode: Bool
    public var document: MindMapDocument
    public var directory: ZipDirectory

    public init(
        nodeID: UUID,
        childID: UUID?,
        attachment: NodeAttachment?,
        proposal: AttachmentInsertProposal?,
        deduplicated: Bool,
        storedOnNode: Bool,
        document: MindMapDocument,
        directory: ZipDirectory
    ) {
        self.nodeID = nodeID
        self.childID = childID
        self.attachment = attachment
        self.proposal = proposal
        self.deduplicated = deduplicated
        self.storedOnNode = storedOnNode
        self.document = document
        self.directory = directory
    }
}

public enum ShareTopicText {
    /// A topic string, not an attachment. Larger text has to arrive as a file.
    public static let maxUTF8Bytes = 256 * 1024

    public static func webTitle(url: String, title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let host = URL(string: url)?.host, !host.isEmpty { return host }
        return url
    }

    public static func fits(_ text: String) -> Bool {
        text.utf8.count <= maxUTF8Bytes
    }
}

public enum ShareLinks {
    /// http and https only. `file:` and other schemes are not web pages.
    public static func webURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty,
              let absolute = components.url?.absoluteString else { return nil }
        return absolute
    }
}

/// Picks the UTI to request so Photos is asked for the concrete type, not a transcode.
public enum ShareTypeChoice {
    /// First match wins. `public.image` is last because the system may convert it.
    public static let imagePriority: [String] = [
        "public.heic",
        "public.heif",
        "public.jpeg",
        "public.png",
        "public.gif",
        "public.tiff",
        "public.bmp",
        "public.webp",
        "org.webmproject.webp",
    ]

    /// One plan for a whole share. A web URL wins over a preview image.
    public static func plan(registeredTypeIdentifiers: [[String]]) -> ShareLoadPlan? {
        let flat = registeredTypeIdentifiers.flatMap { $0 }
        if flat.contains("public.url") { return .webPage }
        for identifier in imagePriority where flat.contains(identifier) {
            return .file(typeIdentifier: identifier)
        }
        if flat.contains("public.image") { return .file(typeIdentifier: "public.image") }
        if flat.contains("public.file-url") { return .file(typeIdentifier: "public.file-url") }
        if flat.contains("public.data") { return .file(typeIdentifier: "public.data") }
        if flat.contains("public.plain-text") || flat.contains("public.text") {
            return .plainText
        }
        return nil
    }

    public static func filename(suggested: String?, typeIdentifier: String) -> String {
        let trimmed = (suggested ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (trimmed as NSString).lastPathComponent
        let ext = fileExtension(for: typeIdentifier)
        if base.isEmpty || base == "." || base == ".." {
            return "图片.\(ext)"
        }
        if (base as NSString).pathExtension.isEmpty, ext != "bin" {
            return "\(base).\(ext)"
        }
        return base
    }

    public static func fileExtension(for typeIdentifier: String) -> String {
        switch typeIdentifier {
        case "public.heic", "public.heif":
            return "heic"
        case "public.jpeg":
            return "jpg"
        case "public.png":
            return "png"
        case "public.gif":
            return "gif"
        case "public.tiff":
            return "tiff"
        case "public.bmp":
            return "bmp"
        case "public.webp", "org.webmproject.webp":
            return "webp"
        default:
            return "bin"
        }
    }
}

public enum ShareLoadPlan: Equatable, Sendable {
    case webPage
    case file(typeIdentifier: String)
    case plainText
}

public enum ShareDraftBuilder {
    /// Photos stores the file and ignores a URL. Safari stores the page and ignores a preview file.
    /// Shortcuts prefer a file, then a web URL, then text.
    public static func make(
        origin: ShareOrigin,
        url: String? = nil,
        title: String? = nil,
        text: String? = nil,
        file: ShareFileFact? = nil
    ) throws -> ShareDraft {
        let web = url.flatMap(ShareLinks.webURL)
        let pageTitle = displayTitle(title: title, text: text)
        switch origin {
        case .photos:
            return ShareDraft(origin: origin, kind: .file(try fileKind(file)))
        case .safari:
            if let web {
                return ShareDraft(origin: origin, kind: .webPage(url: web, title: pageTitle))
            }
            if file != nil {
                return ShareDraft(origin: origin, kind: .file(try fileKind(file)))
            }
            return ShareDraft(origin: origin, kind: .plainText(try plain(text)))
        case .shortcuts:
            if file != nil {
                return ShareDraft(origin: origin, kind: .file(try fileKind(file)))
            }
            if let web {
                return ShareDraft(origin: origin, kind: .webPage(url: web, title: pageTitle))
            }
            return ShareDraft(origin: origin, kind: .plainText(try plain(text)))
        }
    }

    private static func fileKind(_ file: ShareFileFact?) throws -> (filename: String, byteCount: Int64) {
        guard let file else { throw ShareIngressError.emptyPayload }
        if file.isDirectory { throw ShareIngressError.directory }
        if file.byteCount < 0 { throw ShareIngressError.notAFile }
        let name = (file.filename as NSString).lastPathComponent
        guard FileAttachmentRoute.accepts(filename: name, isDirectory: false) else {
            throw ShareIngressError.notAFile
        }
        return (name, file.byteCount)
    }

    private static func plain(_ text: String?) throws -> String {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { throw ShareIngressError.emptyPayload }
        if !ShareTopicText.fits(trimmed) { throw ShareIngressError.textTooLarge }
        return trimmed
    }

    /// A title short enough to be a topic. A long selection is not used as the page name.
    private static func displayTitle(title: String?, text: String?) -> String {
        let primary = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !primary.isEmpty, ShareTopicText.fits(primary) { return primary }
        let secondary = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !secondary.isEmpty, ShareTopicText.fits(secondary) { return secondary }
        return ""
    }
}

public enum ShareIngress {
    public static let pathSeparator = " / "

    /// Main sheet, then free topics. Additional sheets are not listed: `mutateNode` cannot write them.
    public static func topics(in document: MindMapDocument) -> [ShareTopicChoice] {
        var choices: [ShareTopicChoice] = []
        func walk(_ nodes: [MindMapNode], prefix: [String], depth: Int) {
            for node in nodes {
                let title = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let shown = title.isEmpty ? "未命名" : title
                let path = (prefix + [shown]).joined(separator: pathSeparator)
                let acceptsChild = !document.isInFreeNodeTree(node.id)
                choices.append(ShareTopicChoice(
                    id: node.id,
                    title: shown,
                    path: path,
                    depth: depth,
                    acceptsChild: acceptsChild
                ))
                walk(node.children, prefix: prefix + [shown], depth: depth + 1)
            }
        }
        walk(document.roots, prefix: [], depth: 0)
        walk(document.freeNodes, prefix: [], depth: 0)
        return choices
    }

    /// UUID, then a unique path (`中心 / 阅读`), then a unique title.
    public static func match(_ query: String, in document: MindMapDocument) -> ShareNodeMatch {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }
        if let id = UUID(uuidString: trimmed) {
            return document.node(id) == nil ? .none : .found(id)
        }
        let choices = topics(in: document)
        let wanted = normalizePath(trimmed)
        let paths = choices.filter { normalizePath($0.path) == wanted }
        if paths.count == 1, let id = paths.first?.id { return .found(id) }
        if paths.count > 1 { return .ambiguous }
        let titles = choices.filter {
            $0.title.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        if titles.count == 1, let id = titles.first?.id { return .found(id) }
        if titles.count > 1 { return .ambiguous }
        return .none
    }

    /// File confirmation only. Text and pages have no byte size to confirm.
    /// The length is the caller's `stat`, not a read of the file.
    public static func proposal(
        for draft: ShareDraft,
        currentDocumentByteCount: Int64
    ) -> AttachmentInsertProposal? {
        guard case .file(let filename, let byteCount) = draft.kind else { return nil }
        return FileAttachmentRoute.proposal(
            filename: filename,
            byteCount: byteCount,
            currentDocumentByteCount: currentDocumentByteCount
        )
    }

    /// Places text or a web page on `nodeID`. A file is not written here.
    public static func stage(
        _ draft: ShareDraft,
        onto nodeID: UUID,
        in document: MindMapDocument,
        childID: UUID = UUID(),
        now: Date = Date()
    ) throws -> (document: MindMapDocument, childID: UUID?, storedOnNode: Bool) {
        guard document.node(nodeID) != nil else { throw ShareIngressError.unknownNode }
        switch draft.kind {
        case .file:
            throw ShareIngressError.notAFile
        case .webPage(let url, let title):
            let text = ShareTopicText.webTitle(url: url, title: title)
            if !ShareTopicText.fits(text) { throw ShareIngressError.textTooLarge }
            return try place(text: text, link: url, onto: nodeID, childID: childID, in: document, now: now)
        case .plainText(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { throw ShareIngressError.emptyPayload }
            if !ShareTopicText.fits(trimmed) { throw ShareIngressError.textTooLarge }
            return try place(text: trimmed, link: nil, onto: nodeID, childID: childID, in: document, now: now)
        }
    }

    public static func normalizePath(_ raw: String) -> String {
        raw.split(whereSeparator: { $0 == "/" || $0 == "／" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "/")
            .lowercased()
    }

    private static func place(
        text: String,
        link: String?,
        onto nodeID: UUID,
        childID: UUID,
        in document: MindMapDocument,
        now: Date
    ) throws -> (document: MindMapDocument, childID: UUID?, storedOnNode: Bool) {
        var copy = document
        if !copy.isInFreeNodeTree(nodeID) {
            let child = MindMapNode(id: childID, text: text, link: link)
            guard copy.insertChild(child, under: nodeID) else { throw ShareIngressError.unknownNode }
            copy.modifiedAt = now
            return (copy, childID, false)
        }
        let before = copy.node(nodeID)
        guard copy.mutateNode(nodeID, { node in
            if let link, node.link == nil || node.link?.isEmpty == true {
                node.link = link
            }
            let existing = noteLines(node.note)
            if !existing.contains(text) {
                node.note = node.note.isEmpty ? text : node.note + "\n" + text
            }
        }) else { throw ShareIngressError.unknownNode }
        if copy.node(nodeID) != before { copy.modifiedAt = now }
        return (copy, nil, true)
    }

    private static func noteLines(_ note: String) -> [String] {
        if note.isEmpty { return [] }
        return note.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}

public enum ShareCommit {
    /// Opens `archive`, places `draft` on `nodeID`, and streams `fileURL` when the draft is a file.
    /// The file is hashed and copied in chunks. A sha256 already in the package is not written again.
    /// `memory`, when set, is the document to edit instead of the copy inside the ZIP, so an open
    /// editor does not lose unsaved topics. Asset bytes still come from `archive`.
    public static func commit(
        _ draft: ShareDraft,
        onto nodeID: UUID,
        archive: URL,
        fileURL: URL? = nil,
        files: any StreamingFilePort,
        memory: MindMapDocument? = nil,
        childID: UUID = UUID(),
        now: Date = Date(),
        snapshots: SnapshotRetention = .standard
    ) throws -> ShareResult {
        guard files.fileExists(at: archive), try files.isZip(at: archive) else {
            throw ShareIngressError.notAPackage
        }
        let archiveReader = try files.openReader(at: archive)
        let opened: OpenedFloretta
        do {
            opened = try FlorettaStreamingDocument.open(archiveReader)
            try archiveReader.close()
        } catch {
            try? archiveReader.close()
            throw error
        }
        let sourceDocument = memory ?? opened.document
        guard sourceDocument.node(nodeID) != nil else { throw ShareIngressError.unknownNode }

        switch draft.kind {
        case .webPage, .plainText:
            let staged = try ShareIngress.stage(draft, onto: nodeID, in: sourceDocument, childID: childID, now: now)
            if staged.document == sourceDocument {
                return ShareResult(
                    nodeID: nodeID,
                    childID: staged.childID,
                    attachment: nil,
                    proposal: nil,
                    deduplicated: false,
                    storedOnNode: staged.storedOnNode,
                    document: sourceDocument,
                    directory: opened.directory
                )
            }
            let directory = try FlorettaStreamingDocument.save(
                document: staged.document,
                to: archive,
                files: files,
                snapshots: snapshots
            )
            return ShareResult(
                nodeID: nodeID,
                childID: staged.childID,
                attachment: nil,
                proposal: nil,
                deduplicated: false,
                storedOnNode: staged.storedOnNode,
                document: staged.document,
                directory: directory
            )
        case .file(let filename, _):
            guard let fileURL else { throw ShareIngressError.missingFile }
            let count = try files.byteCount(at: fileURL)
            let archiveBytes = try files.byteCount(at: archive)
            guard let proposal = FileAttachmentRoute.proposal(
                filename: filename,
                byteCount: count,
                currentDocumentByteCount: archiveBytes
            ) else {
                throw ShareIngressError.notAFile
            }
            let source = try files.openReader(at: fileURL)
            let hashed: HashedAttachment
            do {
                hashed = try FlorettaStreamingDocument.hashSource(source, filename: filename)
                try source.close()
            } catch {
                try? source.close()
                throw error
            }
            var attachment = try hashed.nodeAttachment()
            var deduplicated = false
            if let stored = opened.directory.attachments.first(where: { $0.sha256 == hashed.sha256 }),
               let parsed = AttachmentNames.parseAsset(stored.name) {
                deduplicated = true
                let storedCount = stored.byteCount > UInt64(Int64.max) ? Int64.max : Int64(stored.byteCount)
                attachment = NodeAttachment(
                    sha256: parsed.sha256,
                    fileExtension: parsed.fileExtension,
                    byteCount: storedCount,
                    filename: hashed.filename
                )
            }
            var updated = sourceDocument
            let before = updated.node(nodeID)?.attachments
            guard updated.mutateNode(nodeID, { node in
                guard !node.attachments.contains(where: { $0.sha256 == attachment.sha256 }) else { return }
                node.attachments.append(attachment)
            }) else {
                throw ShareIngressError.unknownNode
            }
            let added = updated.node(nodeID)?.attachments != before
            if !added {
                return ShareResult(
                    nodeID: nodeID,
                    childID: nil,
                    attachment: attachment,
                    proposal: proposal,
                    deduplicated: true,
                    storedOnNode: true,
                    document: sourceDocument,
                    directory: opened.directory
                )
            }
            updated.modifiedAt = now
            let appending: (url: URL, hashed: HashedAttachment)? = deduplicated ? nil : (fileURL, hashed)
            let directory = try FlorettaStreamingDocument.save(
                document: updated,
                to: archive,
                files: files,
                appending: appending,
                snapshots: snapshots
            )
            return ShareResult(
                nodeID: nodeID,
                childID: nil,
                attachment: attachment,
                proposal: proposal,
                deduplicated: deduplicated,
                storedOnNode: true,
                document: updated,
                directory: directory
            )
        }
    }
}

/// Recent maps the share extension can open. Bookmarks are opaque bytes.
public struct ShareDocumentEntry: Equatable, Sendable, Codable, Identifiable {
    public var id: String
    public var filename: String
    public var bookmark: Data
    public var topicCount: Int

    public init(id: String, filename: String, bookmark: Data, topicCount: Int) {
        self.id = id
        self.filename = filename
        self.bookmark = bookmark
        self.topicCount = topicCount
    }
}

public struct ShareDocumentCatalog: Equatable, Sendable, Codable {
    public static let maxDocuments = 40
    public var documents: [ShareDocumentEntry]

    public init(documents: [ShareDocumentEntry] = []) {
        self.documents = documents
    }

    public func upsert(_ entry: ShareDocumentEntry) -> ShareDocumentCatalog {
        var next = documents.filter { $0.id != entry.id }
        next.insert(entry, at: 0)
        if next.count > Self.maxDocuments {
            next = Array(next.prefix(Self.maxDocuments))
        }
        return ShareDocumentCatalog(documents: next)
    }
}

/// Pulls topics and attachments that showed up on disk after `base`.
/// `mine` wins on text the user already changed. A deletion in `mine` stays deleted
/// when that topic was already in `base`.
public enum ShareAbsorb {
    public static func absorb(
        base: MindMapDocument,
        mine: MindMapDocument,
        theirs: MindMapDocument
    ) -> MindMapDocument {
        var result = mine
        result.roots = mergeNodes(base: base.roots, mine: mine.roots, theirs: theirs.roots)
        result.freeNodes = mergeNodes(base: base.freeNodes, mine: mine.freeNodes, theirs: theirs.freeNodes)
        if result == mine { return mine }
        if theirs.modifiedAt > result.modifiedAt {
            result.modifiedAt = theirs.modifiedAt
        }
        return result
    }

    private static func mergeNodes(
        base: [MindMapNode],
        mine: [MindMapNode],
        theirs: [MindMapNode]
    ) -> [MindMapNode] {
        let merged = mine.map { node -> MindMapNode in
            guard let theirNode = theirs.first(where: { $0.id == node.id }) else { return node }
            let baseNode = base.first(where: { $0.id == node.id })
            var copy = node
            copy.attachments = mergeAttachments(
                base: baseNode?.attachments ?? [],
                mine: node.attachments,
                theirs: theirNode.attachments
            )
            copy.children = mergeNodes(
                base: baseNode?.children ?? [],
                mine: node.children,
                theirs: theirNode.children
            )
            if (copy.link == nil || copy.link?.isEmpty == true),
               baseNode?.link == nil || baseNode?.link?.isEmpty == true,
               let link = theirNode.link,
               !link.isEmpty {
                copy.link = link
            }
            copy.note = mergeNote(base: baseNode?.note ?? "", mine: node.note, theirs: theirNode.note)
            return copy
        }
        let baseIDs = Set(base.map(\.id))
        let mineIDs = Set(mine.map(\.id))
        let added = theirs.filter { !baseIDs.contains($0.id) && !mineIDs.contains($0.id) }
        return merged + added
    }

    private static func mergeAttachments(
        base: [NodeAttachment],
        mine: [NodeAttachment],
        theirs: [NodeAttachment]
    ) -> [NodeAttachment] {
        let known = Set(base.map(\.sha256))
        var seen = Set(mine.map(\.sha256))
        var output = mine
        for attachment in theirs where !known.contains(attachment.sha256) && !seen.contains(attachment.sha256) {
            output.append(attachment)
            seen.insert(attachment.sha256)
        }
        return output
    }

    private static func mergeNote(base: String, mine: String, theirs: String) -> String {
        let known = Set(noteLines(base))
        var output = noteLines(mine)
        for line in noteLines(theirs) where !known.contains(line) && !output.contains(line) {
            output.append(line)
        }
        return output.joined(separator: "\n")
    }

    private static func noteLines(_ note: String) -> [String] {
        if note.isEmpty { return [] }
        return note.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}
