import Foundation

/// FreeMind residue stored on the project.
/// `sourceXML` is the imported file. Export writes those bytes when the mapped
/// snapshot still matches. A mapped edit rebuilds from each node's attributes
/// and child elements, overlaying only the fields that changed.
public struct MMForeign: Equatable, Sendable, Codable {
    public var sourceXML: Data
    public var snapshot: MMMappedSnapshot
    public var residue: MMDocumentResidue
    public var nodes: [MMNodeResidue]

    public init(
        sourceXML: Data,
        snapshot: MMMappedSnapshot,
        residue: MMDocumentResidue,
        nodes: [MMNodeResidue]
    ) {
        self.sourceXML = sourceXML
        self.snapshot = snapshot
        self.residue = residue
        self.nodes = nodes
    }
}

public struct MMDocumentResidue: Equatable, Sendable, Codable {
    public var mapAttributes: [String: String]
    public var slots: [MMContentSlot]

    public init(mapAttributes: [String: String], slots: [MMContentSlot]) {
        self.mapAttributes = mapAttributes
        self.slots = slots
    }
}

public enum MMContentSlot: Equatable, Sendable, Codable {
    case element(XMLForeignElement)
    case child(UUID)
}

public struct MMNodeResidue: Equatable, Sendable, Codable {
    public var id: UUID
    public var importedText: String
    public var importedNote: String
    public var importedLink: String?
    public var importedCollapsed: Bool
    public var importedSide: MindMapSide?
    public var attributes: [String: String]
    /// Raw `ID` attribute, when the file had one. May differ from `id` when the
    /// attribute is not `ID_` plus 32 hex digits, or when that UUID was already used.
    public var originalID: String?
    /// True when `richcontent TYPE="NODE"` plain text was folded into `note` because it differed from `TEXT`.
    public var nodeRichConsumedIntoNote: Bool
    public var slots: [MMContentSlot]

    public init(
        id: UUID,
        importedText: String,
        importedNote: String,
        importedLink: String?,
        importedCollapsed: Bool,
        importedSide: MindMapSide?,
        attributes: [String: String],
        originalID: String?,
        nodeRichConsumedIntoNote: Bool,
        slots: [MMContentSlot]
    ) {
        self.id = id
        self.importedText = importedText
        self.importedNote = importedNote
        self.importedLink = importedLink
        self.importedCollapsed = importedCollapsed
        self.importedSide = importedSide
        self.attributes = attributes
        self.originalID = originalID
        self.nodeRichConsumedIntoNote = nodeRichConsumedIntoNote
        self.slots = slots
    }
}

public struct MMMappedSnapshot: Equatable, Sendable, Codable {
    public var title: String
    public var roots: [MMNodeSnapshot]

    public init(document: MindMapDocument) {
        title = document.title
        roots = document.roots.map(MMNodeSnapshot.init)
    }
}

public struct MMNodeSnapshot: Equatable, Sendable, Codable {
    public var id: UUID
    public var text: String
    public var note: String
    public var link: String?
    public var isCollapsed: Bool
    public var side: MindMapSide?
    public var children: [MMNodeSnapshot]

    public init(_ node: MindMapNode) {
        id = node.id
        text = node.text
        note = node.note
        link = node.link.flatMap { $0.isEmpty ? nil : $0 }
        isCollapsed = node.isCollapsed
        side = node.side
        children = node.children.map(MMNodeSnapshot.init)
    }
}
