import Foundation

struct MindMapNodeStyle: Equatable, Sendable, Codable {
    /// sRGB color as `#RRGGBB`. Version 1 has no other style fields.
    var colorHex: String
}

/// Canvas coordinates remembered after a drag. Absent means "not placed by hand".
struct MindMapPoint: Equatable, Sendable, Codable {
    var x: Double
    var y: Double
}

/// FreeMind/Freeplane `POSITION` on a node. This is a side, not a canvas point.
enum MindMapSide: String, Equatable, Sendable, Codable {
    case left
    case right
}

/// One topic in the map. Children are an ordered tree.
/// A value tree cannot point at itself, so a cycle is not representable in memory.
struct MindMapNode: Equatable, Sendable, Identifiable {
    var id: UUID
    var text: String
    var note: String
    var isCollapsed: Bool
    var style: MindMapNodeStyle?
    var position: MindMapPoint?
    /// FreeMind `LINK`. Absent when the topic has no link.
    var link: String?
    /// FreeMind `POSITION` (`left` / `right`). Absent when the file did not say.
    var side: MindMapSide?
    var children: [MindMapNode]

    init(
        id: UUID = UUID(),
        text: String,
        note: String = "",
        isCollapsed: Bool = false,
        style: MindMapNodeStyle? = nil,
        position: MindMapPoint? = nil,
        link: String? = nil,
        side: MindMapSide? = nil,
        children: [MindMapNode] = []
    ) {
        self.id = id
        self.text = text
        self.note = note
        self.isCollapsed = isCollapsed
        self.style = style
        self.position = position
        self.link = link
        self.side = side
        self.children = children
    }
}

extension MindMapNode: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case note
        case collapsed
        case style
        case position
        case link
        case side
        case children
    }

    init(from decoder: Decoder) throws {
        // Each nested child adds path entries. Stop before a hostile file can blow the stack.
        if decoder.codingPath.count > 512 {
            throw FlorettaCodecError.corrupt("Document is nested too deeply.")
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        note = try container.decode(String.self, forKey: .note)
        isCollapsed = try container.decode(Bool.self, forKey: .collapsed)
        style = try container.decodeIfPresent(MindMapNodeStyle.self, forKey: .style)
        position = try container.decodeIfPresent(MindMapPoint.self, forKey: .position)
        link = try container.decodeIfPresent(String.self, forKey: .link)
        side = try container.decodeIfPresent(MindMapSide.self, forKey: .side)
        children = try container.decode([MindMapNode].self, forKey: .children)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(note, forKey: .note)
        try container.encode(isCollapsed, forKey: .collapsed)
        try container.encodeIfPresent(style, forKey: .style)
        try container.encodeIfPresent(position, forKey: .position)
        try container.encodeIfPresent(link, forKey: .link)
        try container.encodeIfPresent(side, forKey: .side)
        try container.encode(children, forKey: .children)
    }
}
