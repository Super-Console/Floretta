import Foundation

/// OPML residue stored on the project.
/// `sourceXML` is the imported file. Export writes those bytes when the mapped
/// snapshot still matches. A mapped edit rebuilds the file from `residue` and
/// `nodes`, overlaying the edited fields and leaving every other attribute and
/// element as it was read.
public struct OPMLForeign: Equatable, Sendable, Codable {
    public var sourceXML: Data
    public var snapshot: OPMLMappedSnapshot
    public var residue: OPMLDocumentResidue
    public var nodes: [OPMLNodeResidue]

    public init(
        sourceXML: Data,
        snapshot: OPMLMappedSnapshot,
        residue: OPMLDocumentResidue,
        nodes: [OPMLNodeResidue]
    ) {
        self.sourceXML = sourceXML
        self.snapshot = snapshot
        self.residue = residue
        self.nodes = nodes
    }
}

public struct OPMLDocumentResidue: Equatable, Sendable, Codable {
    public var opmlAttributes: [String: String]
    public var headAttributes: [String: String]
    public var bodyAttributes: [String: String]
    public var headSlots: [OPMLHeadSlot]
    public var bodySlots: [OPMLContentSlot]
    /// Title actually stored on the document after import, including the root-text fallback.
    public var importedTitle: String

    public init(
        opmlAttributes: [String: String],
        headAttributes: [String: String],
        bodyAttributes: [String: String],
        headSlots: [OPMLHeadSlot],
        bodySlots: [OPMLContentSlot],
        importedTitle: String
    ) {
        self.opmlAttributes = opmlAttributes
        self.headAttributes = headAttributes
        self.bodyAttributes = bodyAttributes
        self.headSlots = headSlots
        self.bodySlots = bodySlots
        self.importedTitle = importedTitle
    }
}

public enum OPMLHeadSlot: Equatable, Sendable, Codable {
    case title
    case element(XMLForeignElement)
}

public enum OPMLContentSlot: Equatable, Sendable, Codable {
    case element(XMLForeignElement)
    case child(UUID)
}

public struct OPMLNodeResidue: Equatable, Sendable, Codable {
    public var id: UUID
    public var importedText: String
    public var importedNote: String
    public var importedLink: String?
    /// Every attribute on the outline, including the ones mapped into the model.
    public var attributes: [String: String]
    public var slots: [OPMLContentSlot]

    public init(
        id: UUID,
        importedText: String,
        importedNote: String,
        importedLink: String?,
        attributes: [String: String],
        slots: [OPMLContentSlot]
    ) {
        self.id = id
        self.importedText = importedText
        self.importedNote = importedNote
        self.importedLink = importedLink
        self.attributes = attributes
        self.slots = slots
    }
}

public struct OPMLMappedSnapshot: Equatable, Sendable, Codable {
    public var title: String
    public var roots: [OPMLNodeSnapshot]

    public init(document: MindMapDocument) {
        title = document.title
        roots = document.roots.map(OPMLNodeSnapshot.init)
    }
}

public struct OPMLNodeSnapshot: Equatable, Sendable, Codable {
    public var id: UUID
    public var text: String
    public var note: String
    public var link: String?
    public var children: [OPMLNodeSnapshot]

    public init(_ node: MindMapNode) {
        id = node.id
        text = node.text
        note = node.note
        link = node.link.flatMap { $0.isEmpty ? nil : $0 }
        children = node.children.map(OPMLNodeSnapshot.init)
    }
}
