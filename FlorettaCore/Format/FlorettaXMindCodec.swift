import Foundation

/// `.xmind` (ZIP + `content.json`) for this slice.
/// Free nodes are written as `rootTopic.children.detached` with `position`,
/// which is XMind's floating topic. Relationships are written on the sheet
/// and are not drawn by the canvas. One sheet only.
public enum FlorettaXMindError: Error, Equatable, Sendable {
    case notZip
    case missingContent
    case tooManySheets
    case corrupt(String)
}

extension FlorettaXMindError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notZip:
            return "不是 .xmind 压缩包。"
        case .missingContent:
            return "缺少 content.json。"
        case .tooManySheets:
            return ".xmind 有多张画布，这一版只读写一张。"
        case .corrupt(let message):
            return message
        }
    }
}

public enum FlorettaXMindCodec {
    public static let attachmentProvider = "org.floretta.attachments"

    public static func export(_ document: MindMapDocument) throws -> Data {
        do {
            try FlorettaTree.validate(document)
        } catch let error as FlorettaCodecError {
            throw FlorettaXMindError.corrupt(error.localizedDescription)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let sheet = XSheet(document: document)
        let content = try encode([sheet], with: encoder)
        let metadata = XMetadata(
            creator: XMetadata.Creator(name: "Floretta", version: "1"),
            dataStructureVersion: "2"
        )
        let manifest = XManifest(fileEntries: [
            "content.json": XEmpty(),
            "manifest.json": XEmpty(),
            "metadata.json": XEmpty(),
        ])
        return ZipArchive.write([
            ZipEntry(name: "content.json", data: content),
            ZipEntry(name: "metadata.json", data: try encode(metadata, with: encoder)),
            ZipEntry(name: "manifest.json", data: try encode(manifest, with: encoder)),
        ])
    }

    public static func importMap(_ data: Data) throws -> MindMapDocument {
        let entries: [ZipEntry]
        do {
            entries = try ZipArchive.read(data, limits: .standard)
        } catch {
            throw FlorettaXMindError.notZip
        }
        guard let content = entries.first(where: { $0.name == "content.json" })?.data else {
            throw FlorettaXMindError.missingContent
        }
        let sheets: [XSheet]
        do {
            sheets = try JSONDecoder().decode([XSheet].self, from: content)
        } catch {
            throw FlorettaXMindError.corrupt("content.json could not be read.")
        }
        guard let sheet = sheets.first else {
            throw FlorettaXMindError.corrupt("content.json has no sheet.")
        }
        guard sheets.count == 1 else { throw FlorettaXMindError.tooManySheets }
        return try sheet.document()
    }

    private static func encode<T: Encodable>(_ value: T, with encoder: JSONEncoder) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            throw FlorettaXMindError.corrupt("Could not write .xmind JSON.")
        }
    }
}

private struct XSheet: Codable {
    var id: String
    var kind: String
    var title: String
    var topicPositioning: String
    var rootTopic: XTopic
    var relationships: [XRelationship]?

    enum CodingKeys: String, CodingKey {
        case id
        case kind = "class"
        case title
        case topicPositioning
        case rootTopic
        case relationships
    }

    init(document: MindMapDocument) {
        id = UUID().uuidString
        kind = "sheet"
        title = document.title
        topicPositioning = "free"
        if document.roots.count == 1 {
            rootTopic = XTopic(node: document.roots[0], floating: false, detached: document.freeNodes)
        } else {
            let attached = document.roots.map { XTopic(node: $0, floating: false, detached: []) }
            rootTopic = XTopic(
                id: UUID().uuidString,
                kind: "topic",
                title: document.title.isEmpty ? "Mind Map" : document.title,
                position: nil,
                notes: nil,
                href: nil,
                children: XChildren(attached: attached, detached: document.freeNodes.map {
                    XTopic(node: $0, floating: true, detached: [])
                }),
                extensions: nil
            )
        }
        let links = document.relationships.map { XRelationship($0) }
        relationships = links.isEmpty ? nil : links
    }

    func document() throws -> MindMapDocument {
        let detached = rootTopic.children?.detached ?? []
        for topic in rootTopic.children?.attached ?? [] {
            try topic.rejectNestedFloating()
        }
        var hierarchy = rootTopic
        if var children = hierarchy.children {
            children.detached = nil
            hierarchy.children = children.isEmpty ? nil : children
        }
        let root = try hierarchy.mindNode(floating: false)
        let free = try detached.map { try $0.mindNode(floating: true) }
        var relationships: [TopicRelationship] = []
        var known: Set<UUID> = []
        func collect(_ node: MindMapNode) {
            known.insert(node.id)
            node.children.forEach(collect)
        }
        collect(root)
        free.forEach(collect)
        for link in self.relationships ?? [] {
            let relationship = try link.relationship()
            guard known.contains(relationship.sourceID), known.contains(relationship.targetID) else {
                throw FlorettaXMindError.corrupt(
                    "Relationship \(link.id) points at a missing topic."
                )
            }
            relationships.append(relationship)
        }
        let document = MindMapDocument(
            title: title,
            roots: [root],
            freeNodes: free,
            relationships: relationships
        )
        do {
            try FlorettaTree.validate(document)
        } catch let error as FlorettaCodecError {
            throw FlorettaXMindError.corrupt(error.localizedDescription)
        }
        return document
    }
}

private struct XTopic: Codable {
    var id: String
    var kind: String
    var title: String
    var position: XPoint?
    var notes: XNotes?
    var href: String?
    var children: XChildren?
    var extensions: [XExtension]?

    enum CodingKeys: String, CodingKey {
        case id
        case kind = "class"
        case title
        case position
        case notes
        case href
        case children
        case extensions
    }

    init(node: MindMapNode, floating: Bool, detached: [MindMapNode]) {
        id = node.id.uuidString
        kind = "topic"
        title = node.text
        if floating {
            position = XPoint(x: node.position?.x ?? 0, y: node.position?.y ?? 0)
        } else if let stored = node.position {
            position = XPoint(x: stored.x, y: stored.y)
        } else {
            position = nil
        }
        notes = node.note.isEmpty ? nil : XNotes(plain: XPlain(content: node.note))
        if let link = node.link, !link.isEmpty {
            href = link
        } else {
            href = nil
        }
        let attached = node.children.map { XTopic(node: $0, floating: false, detached: []) }
        let floatingTopics = detached.map { XTopic(node: $0, floating: true, detached: []) }
        let built = XChildren(attached: attached, detached: floatingTopics)
        children = built.isEmpty ? nil : built
        if node.attachments.isEmpty {
            extensions = nil
        } else {
            extensions = [
                XExtension(
                    provider: FlorettaXMindCodec.attachmentProvider,
                    content: XAttachmentContent(items: node.attachments.map {
                        XAttachmentItem(
                            sha256: $0.sha256,
                            fileExtension: $0.fileExtension,
                            byteCount: $0.byteCount,
                            filename: $0.filename
                        )
                    })
                ),
            ]
        }
    }

    func rejectNestedFloating() throws {
        if let nested = children?.detached, !nested.isEmpty {
            throw FlorettaXMindError.corrupt("Nested floating topics are not imported.")
        }
        for child in children?.attached ?? [] {
            try child.rejectNestedFloating()
        }
    }

    func mindNode(floating: Bool) throws -> MindMapNode {
        if floating {
            if let nested = children?.detached, !nested.isEmpty {
                throw FlorettaXMindError.corrupt("A floating topic cannot contain another floating list in this version.")
            }
        } else if let nested = children?.detached, !nested.isEmpty {
            throw FlorettaXMindError.corrupt("Nested floating topics are not imported.")
        }
        let topicID = try Self.uuid(id)
        let stored: MindMapPoint?
        if floating {
            stored = MindMapPoint(x: position?.x ?? 0, y: position?.y ?? 0)
        } else if let position {
            stored = MindMapPoint(x: position.x, y: position.y)
        } else {
            stored = nil
        }
        let children = try (self.children?.attached ?? []).map { try $0.mindNode(floating: false) }
        let attachments = (extensions ?? [])
            .filter { $0.provider == FlorettaXMindCodec.attachmentProvider }
            .flatMap(\.content.items)
            .map {
                NodeAttachment(
                    sha256: $0.sha256,
                    fileExtension: $0.fileExtension,
                    byteCount: $0.byteCount,
                    filename: $0.filename
                )
            }
        return MindMapNode(
            id: topicID,
            text: title,
            note: notes?.plain.content ?? "",
            position: stored,
            link: href,
            attachments: attachments,
            children: children
        )
    }

    private static func uuid(_ string: String) throws -> UUID {
        guard let id = UUID(uuidString: string) else {
            throw FlorettaXMindError.corrupt("Topic id \(string) is not a UUID.")
        }
        return id
    }
}

private struct XChildren: Codable {
    var attached: [XTopic]?
    var detached: [XTopic]?

    init(attached: [XTopic], detached: [XTopic]) {
        self.attached = attached.isEmpty ? nil : attached
        self.detached = detached.isEmpty ? nil : detached
    }

    var isEmpty: Bool {
        (attached ?? []).isEmpty && (detached ?? []).isEmpty
    }
}

private struct XPoint: Codable {
    var x: Double
    var y: Double
}

private struct XNotes: Codable {
    var plain: XPlain
}

private struct XPlain: Codable {
    var content: String
}

private struct XExtension: Codable {
    var provider: String
    var content: XAttachmentContent
}

private struct XAttachmentContent: Codable {
    var items: [XAttachmentItem]
}

private struct XAttachmentItem: Codable {
    var sha256: String
    var fileExtension: String
    var byteCount: Int64
    var filename: String
}

private struct XRelationship: Codable {
    var id: String
    var kind: String
    var end1Id: String
    var end2Id: String
    var title: String?

    enum CodingKeys: String, CodingKey {
        case id
        case kind = "class"
        case end1Id
        case end2Id
        case title
    }

    init(_ relationship: TopicRelationship) {
        id = relationship.id.uuidString
        kind = "relationship"
        end1Id = relationship.sourceID.uuidString
        end2Id = relationship.targetID.uuidString
        title = relationship.title.isEmpty ? nil : relationship.title
    }

    func relationship() throws -> TopicRelationship {
        guard let relationshipID = UUID(uuidString: id),
              let sourceID = UUID(uuidString: end1Id),
              let targetID = UUID(uuidString: end2Id) else {
            throw FlorettaXMindError.corrupt("Relationship \(id) is not a UUID.")
        }
        return TopicRelationship(
            id: relationshipID,
            sourceID: sourceID,
            targetID: targetID,
            title: title ?? ""
        )
    }
}

private struct XMetadata: Codable {
    struct Creator: Codable {
        var name: String
        var version: String
    }

    var creator: Creator
    var dataStructureVersion: String
}

private struct XManifest: Codable {
    var fileEntries: [String: XEmpty]

    enum CodingKeys: String, CodingKey {
        case fileEntries = "file-entries"
    }
}

private struct XEmpty: Codable {}

private extension XTopic {
    init(
        id: String,
        kind: String,
        title: String,
        position: XPoint?,
        notes: XNotes?,
        href: String?,
        children: XChildren?,
        extensions: [XExtension]?
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.position = position
        self.notes = notes
        self.href = href
        self.children = children?.isEmpty == true ? nil : children
        self.extensions = extensions
    }
}
