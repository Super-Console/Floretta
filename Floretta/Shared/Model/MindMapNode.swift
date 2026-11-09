import Foundation

struct MindMapNodeStyle: Equatable, Sendable, Codable {
    /// sRGB color as `#RRGGBB`. Version 1 has no other style fields.
    var colorHex: String
}

/// One topic in the map. Children are an ordered tree.
/// A value tree cannot point at itself, so a cycle is not representable in memory.
struct MindMapNode: Equatable, Sendable, Identifiable {
    var id: UUID
    var text: String
    var note: String
    var isCollapsed: Bool
    var style: MindMapNodeStyle?
    var children: [MindMapNode]

    init(
        id: UUID = UUID(),
        text: String,
        note: String = "",
        isCollapsed: Bool = false,
        style: MindMapNodeStyle? = nil,
        children: [MindMapNode] = []
    ) {
        self.id = id
        self.text = text
        self.note = note
        self.isCollapsed = isCollapsed
        self.style = style
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
        children = try container.decode([MindMapNode].self, forKey: .children)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(note, forKey: .note)
        try container.encode(isCollapsed, forKey: .collapsed)
        try container.encodeIfPresent(style, forKey: .style)
        try container.encode(children, forKey: .children)
    }
}
