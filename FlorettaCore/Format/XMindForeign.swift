import Foundation

/// Zoom and pan for one canvas. Scale 1 is 100%. Offsets are the viewport's
/// screen-space pan, the same numbers `CanvasViewport` stores.
/// Identity (scale 1, no pan) is omitted from JSON.
public struct CanvasViewportState: Equatable, Sendable, Codable {
    public var scale: Double
    public var offsetX: Double
    public var offsetY: Double

    public static let minimumScale = Double(ZoomStop.fifty.scale)
    public static let maximumScale = Double(ZoomStop.fourHundred.scale)
    public static let standard = CanvasViewportState(scale: 1, offsetX: 0, offsetY: 0)

    public init(scale: Double, offsetX: Double, offsetY: Double) {
        self.scale = Self.clampScale(scale)
        self.offsetX = offsetX.isFinite ? offsetX : 0
        self.offsetY = offsetY.isFinite ? offsetY : 0
    }

    public var isStandard: Bool {
        scale == 1 && offsetX == 0 && offsetY == 0
    }

    public static func clampScale(_ scale: Double) -> Double {
        guard scale.isFinite else { return 1 }
        return min(max(scale, minimumScale), maximumScale)
    }

    public static func clamped(_ state: CanvasViewportState) -> CanvasViewportState {
        CanvasViewportState(scale: state.scale, offsetX: state.offsetX, offsetY: state.offsetY)
    }

    private enum CodingKeys: String, CodingKey {
        case scale
        case offsetX
        case offsetY
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let scale = try container.decode(Double.self, forKey: .scale)
        let offsetX = try container.decode(Double.self, forKey: .offsetX)
        let offsetY = try container.decode(Double.self, forKey: .offsetY)
        self.init(scale: scale, offsetX: offsetX, offsetY: offsetY)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scale, forKey: .scale)
        try container.encode(offsetX, forKey: .offsetX)
        try container.encode(offsetY, forKey: .offsetY)
    }
}

/// One canvas after the first sheet. The first sheet stays on `MindMapDocument`
/// (`title`, `roots`, `freeNodes`, `relationships`, `stickies`) so existing callers keep working.
public struct MindMapCanvas: Equatable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var title: String
    public var roots: [MindMapNode]
    public var freeNodes: [MindMapNode]
    public var relationships: [TopicRelationship]
    /// Cards on this sheet. Empty is omitted from JSON.
    public var stickies: [StickyNote]
    /// Zones on this sheet. Empty is omitted from JSON. Not topics.
    public var regions: [CanvasRegion]
    /// This sheet's zoom and pan. Identity is omitted from JSON.
    public var viewport: CanvasViewportState

    public init(
        id: UUID = UUID(),
        title: String,
        roots: [MindMapNode] = [],
        freeNodes: [MindMapNode] = [],
        relationships: [TopicRelationship] = [],
        stickies: [StickyNote] = [],
        regions: [CanvasRegion] = [],
        viewport: CanvasViewportState = .standard
    ) {
        self.id = id
        self.title = title
        self.roots = roots
        self.freeNodes = freeNodes
        self.relationships = relationships
        self.stickies = stickies
        self.regions = regions
        self.viewport = viewport
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case roots
        case freeNodes
        case relationships
        case stickies
        case regions
        case viewport
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        roots = try container.decodeIfPresent([MindMapNode].self, forKey: .roots) ?? []
        freeNodes = try container.decodeIfPresent([MindMapNode].self, forKey: .freeNodes) ?? []
        relationships = try container.decodeIfPresent([TopicRelationship].self, forKey: .relationships) ?? []
        stickies = try container.decodeIfPresent([StickyNote].self, forKey: .stickies) ?? []
        regions = try container.decodeIfPresent([CanvasRegion].self, forKey: .regions) ?? []
        viewport = try container.decodeIfPresent(CanvasViewportState.self, forKey: .viewport) ?? .standard
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(roots, forKey: .roots)
        try container.encode(freeNodes, forKey: .freeNodes)
        try container.encode(relationships, forKey: .relationships)
        if !stickies.isEmpty {
            try container.encode(stickies, forKey: .stickies)
        }
        if !regions.isEmpty {
            try container.encode(regions, forKey: .regions)
        }
        if !viewport.isStandard {
            try container.encode(viewport, forKey: .viewport)
        }
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
    /// False on a file saved before `topic.labels` and `topic.markers` were mapped.
    /// Missing from the JSON means the same thing. New snapshots always write true.
    public var tagsMapped: Bool

    public init(sheets: [XMindSheetSnapshot], tagsMapped: Bool = true) {
        self.sheets = sheets
        self.tagsMapped = tagsMapped
    }

    public init(document: MindMapDocument) {
        var sheets = [
            XMindSheetSnapshot(
                title: document.canvasTitle(at: 0),
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
        self.tagsMapped = true
    }

    private enum CodingKeys: String, CodingKey {
        case sheets
        case tagsMapped
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sheets = try container.decode([XMindSheetSnapshot].self, forKey: .sheets)
        tagsMapped = try container.decodeIfPresent(Bool.self, forKey: .tagsMapped) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sheets, forKey: .sheets)
        try container.encode(tagsMapped, forKey: .tagsMapped)
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
    public var labels: [String]
    public var markers: [TopicMarker]
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
        labels = node.labels
        markers = node.markers
        children = node.children.map(XMindNodeSnapshot.init)
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, note, link, position, style, attachments, summaries, boundaries, labels, markers, children
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
        labels = try container.decodeIfPresent([String].self, forKey: .labels) ?? []
        markers = try container.decodeIfPresent([TopicMarker].self, forKey: .markers) ?? []
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
        if !labels.isEmpty {
            try container.encode(labels, forKey: .labels)
        }
        if !markers.isEmpty {
            try container.encode(markers, forKey: .markers)
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
