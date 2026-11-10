import Foundation

/// One canvas after the first sheet. The first sheet stays on `MindMapDocument`
/// (`title`, `roots`, `freeNodes`, `relationships`) so existing callers keep working.
public struct MindMapCanvas: Equatable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var title: String
    public var roots: [MindMapNode]
    public var freeNodes: [MindMapNode]
    public var relationships: [TopicRelationship]

    public init(
        id: UUID = UUID(),
        title: String,
        roots: [MindMapNode] = [],
        freeNodes: [MindMapNode] = [],
        relationships: [TopicRelationship] = []
    ) {
        self.id = id
        self.title = title
        self.roots = roots
        self.freeNodes = freeNodes
        self.relationships = relationships
    }
}

/// XMind package residue stored on the project model.
/// `contentJSON` is the original `content.json` bytes. Export writes those bytes
/// when the mapped snapshot still matches. A mapped edit rebuilds `content.json`
/// from each object's `source` bag, overlaying the edited fields.
public struct XMindForeign: Equatable, Sendable, Codable {
    public var contentJSON: Data
    public var metadataJSON: Data?
    public var manifestJSON: Data?
    public var entries: [XMindForeignEntry]
    public var snapshot: XMindMappedSnapshot
    public var sheets: [XMindSheetForeign]

    public init(
        contentJSON: Data,
        metadataJSON: Data?,
        manifestJSON: Data?,
        entries: [XMindForeignEntry],
        snapshot: XMindMappedSnapshot,
        sheets: [XMindSheetForeign]
    ) {
        self.contentJSON = contentJSON
        self.metadataJSON = metadataJSON
        self.manifestJSON = manifestJSON
        self.entries = entries
        self.snapshot = snapshot
        self.sheets = sheets
    }
}

public struct XMindForeignEntry: Equatable, Sendable, Codable {
    public var name: String
    public var data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }
}

public struct XMindSheetForeign: Equatable, Sendable, Codable {
    public var originalID: String
    public var source: XMindJSONObject
    public var topics: [String: XMindTopicForeign]
    public var relationships: [String: XMindRelationshipForeign]

    public init(
        originalID: String,
        source: XMindJSONObject,
        topics: [String: XMindTopicForeign],
        relationships: [String: XMindRelationshipForeign]
    ) {
        self.originalID = originalID
        self.source = source
        self.topics = topics
        self.relationships = relationships
    }
}

public struct XMindTopicForeign: Equatable, Sendable, Codable {
    public var originalID: String
    /// The topic object as imported, including keys this codec does not map.
    public var source: XMindJSONObject
    public var styleTokens: XMindStyleTokens
    public var resourceHrefs: [XMindResourceHref]
    /// True when `href` was interpreted as a link or an `xap:` attachment.
    public var ownsHref: Bool

    public init(
        originalID: String,
        source: XMindJSONObject,
        styleTokens: XMindStyleTokens,
        resourceHrefs: [XMindResourceHref],
        ownsHref: Bool
    ) {
        self.originalID = originalID
        self.source = source
        self.styleTokens = styleTokens
        self.resourceHrefs = resourceHrefs
        self.ownsHref = ownsHref
    }
}

public struct XMindRelationshipForeign: Equatable, Sendable, Codable {
    public var originalID: String
    public var source: XMindJSONObject

    public init(originalID: String, source: XMindJSONObject) {
        self.originalID = originalID
        self.source = source
    }
}

public struct XMindResourceHref: Equatable, Sendable, Codable {
    public var sha256: String
    public var href: String
    public var zipPath: String

    public init(sha256: String, href: String, zipPath: String) {
        self.sha256 = sha256
        self.href = href
        self.zipPath = zipPath
    }
}

/// Raw style tokens that were mapped, so an edit of some other field can write
/// `700` and `18pt` back instead of a normalized substitute.
public struct XMindStyleTokens: Equatable, Sendable, Codable {
    public var hadLineColor: Bool = false
    public var importedColorHex: String?
    public var lineColor: String?
    public var fill: String?
    public var textColor: String?
    public var fontFamily: String?
    public var fontSize: String?
    public var fontWeight: String?
    public var fontStyle: String?
    public var textDecoration: String?
    public var borderColor: String?
    public var borderWidth: String?
    public var borderPattern: String?
    public var fillPattern: String?

    public init() {}
}

public struct XMindMappedSnapshot: Equatable, Sendable, Codable {
    public var sheets: [XMindSheetSnapshot]

    public init(sheets: [XMindSheetSnapshot]) {
        self.sheets = sheets
    }

    public init(document: MindMapDocument) {
        var sheets = [
            XMindSheetSnapshot(
                title: document.title,
                roots: document.roots,
                freeNodes: document.freeNodes,
                relationships: document.relationships
            ),
        ]
        for canvas in document.additionalCanvases {
            sheets.append(XMindSheetSnapshot(
                title: canvas.title,
                roots: canvas.roots,
                freeNodes: canvas.freeNodes,
                relationships: canvas.relationships
            ))
        }
        self.sheets = sheets
    }
}

public struct XMindSheetSnapshot: Equatable, Sendable, Codable {
    public var title: String
    public var roots: [XMindNodeSnapshot]
    public var freeNodes: [XMindNodeSnapshot]
    public var relationships: [XMindRelationshipSnapshot]

    public init(
        title: String,
        roots: [MindMapNode],
        freeNodes: [MindMapNode],
        relationships: [TopicRelationship]
    ) {
        self.title = title
        self.roots = roots.map(XMindNodeSnapshot.init)
        self.freeNodes = freeNodes.map(XMindNodeSnapshot.init)
        self.relationships = relationships.map(XMindRelationshipSnapshot.init)
    }
}

public struct XMindNodeSnapshot: Equatable, Sendable, Codable {
    public var id: UUID
    public var text: String
    public var note: String
    public var link: String?
    public var position: MindMapPoint?
    public var style: MindMapNodeStyle?
    public var attachments: [NodeAttachment]
    public var summaries: [TopicSummary]
    public var boundaries: [TopicBoundary]
    public var children: [XMindNodeSnapshot]

    public init(_ node: MindMapNode) {
        id = node.id
        text = node.text
        note = node.note
        link = node.link.flatMap { $0.isEmpty ? nil : $0 }
        position = node.position
        style = node.style
        attachments = node.attachments
        summaries = node.summaries
        boundaries = node.boundaries
        children = node.children.map(XMindNodeSnapshot.init)
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, note, link, position, style, attachments, summaries, boundaries, children
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        note = try container.decode(String.self, forKey: .note)
        link = try container.decodeIfPresent(String.self, forKey: .link)
        position = try container.decodeIfPresent(MindMapPoint.self, forKey: .position)
        style = try container.decodeIfPresent(MindMapNodeStyle.self, forKey: .style)
        attachments = try container.decodeIfPresent([NodeAttachment].self, forKey: .attachments) ?? []
        summaries = try container.decodeIfPresent([TopicSummary].self, forKey: .summaries) ?? []
        boundaries = try container.decodeIfPresent([TopicBoundary].self, forKey: .boundaries) ?? []
        children = try container.decode([XMindNodeSnapshot].self, forKey: .children)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(note, forKey: .note)
        try container.encodeIfPresent(link, forKey: .link)
        try container.encodeIfPresent(position, forKey: .position)
        try container.encodeIfPresent(style, forKey: .style)
        try container.encode(attachments, forKey: .attachments)
        if !summaries.isEmpty {
            try container.encode(summaries, forKey: .summaries)
        }
        if !boundaries.isEmpty {
            try container.encode(boundaries, forKey: .boundaries)
        }
        try container.encode(children, forKey: .children)
    }
}

public struct XMindRelationshipSnapshot: Equatable, Sendable, Codable {
    public var id: UUID
    public var sourceID: UUID
    public var targetID: UUID
    public var title: String

    public init(_ relationship: TopicRelationship) {
        id = relationship.id
        sourceID = relationship.sourceID
        targetID = relationship.targetID
        title = relationship.title
    }
}
