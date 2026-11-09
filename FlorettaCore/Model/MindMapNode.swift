import Foundation

/// Topic style stored in the document. `colorHex` is the original branch color.
/// Fill, border, and font size are optional overrides and are omitted from JSON when unset.
public struct MindMapNodeStyle: Equatable, Sendable {
    public var colorHex: String
    public var fillHex: String? = nil
    public var borderHex: String? = nil
    public var textHex: String? = nil
    public var fontSize: Double? = nil
    public var borderWidth: Double? = nil
    public var topicWidth: Double? = nil
    public var cornerRadius: Double? = nil
    public var fontDesign: String? = nil
    public var bold: Bool? = nil
    public var italic: Bool? = nil
    public var strikethrough: Bool? = nil
    public var underline: Bool? = nil
    public var fillStyle: String? = nil
    public var borderStyle: String? = nil

    public init(
        colorHex: String,
        fillHex: String? = nil,
        borderHex: String? = nil,
        textHex: String? = nil,
        fontSize: Double? = nil,
        borderWidth: Double? = nil,
        topicWidth: Double? = nil,
        cornerRadius: Double? = nil,
        fontDesign: String? = nil,
        bold: Bool? = nil,
        italic: Bool? = nil,
        strikethrough: Bool? = nil,
        underline: Bool? = nil,
        fillStyle: String? = nil,
        borderStyle: String? = nil
    ) {
        self.colorHex = colorHex
        self.fillHex = fillHex
        self.borderHex = borderHex
        self.textHex = textHex
        self.fontSize = fontSize
        self.borderWidth = borderWidth
        self.topicWidth = topicWidth
        self.cornerRadius = cornerRadius
        self.fontDesign = fontDesign
        self.bold = bold
        self.italic = italic
        self.strikethrough = strikethrough
        self.underline = underline
        self.fillStyle = fillStyle
        self.borderStyle = borderStyle
    }
}

extension MindMapNodeStyle: Codable {
    private enum CodingKeys: String, CodingKey {
        case colorHex, fillHex, borderHex, textHex, fontSize, borderWidth, topicWidth
        case cornerRadius, fontDesign, bold, italic, strikethrough, underline, fillStyle, borderStyle
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        fillHex = try container.decodeIfPresent(String.self, forKey: .fillHex)
        borderHex = try container.decodeIfPresent(String.self, forKey: .borderHex)
        textHex = try container.decodeIfPresent(String.self, forKey: .textHex)
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize)
        borderWidth = try container.decodeIfPresent(Double.self, forKey: .borderWidth)
        topicWidth = try container.decodeIfPresent(Double.self, forKey: .topicWidth)
        cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius)
        fontDesign = try container.decodeIfPresent(String.self, forKey: .fontDesign)
        bold = try container.decodeIfPresent(Bool.self, forKey: .bold)
        italic = try container.decodeIfPresent(Bool.self, forKey: .italic)
        strikethrough = try container.decodeIfPresent(Bool.self, forKey: .strikethrough)
        underline = try container.decodeIfPresent(Bool.self, forKey: .underline)
        fillStyle = try container.decodeIfPresent(String.self, forKey: .fillStyle)
        borderStyle = try container.decodeIfPresent(String.self, forKey: .borderStyle)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encodeIfPresent(fillHex, forKey: .fillHex)
        try container.encodeIfPresent(borderHex, forKey: .borderHex)
        try container.encodeIfPresent(textHex, forKey: .textHex)
        try container.encodeIfPresent(fontSize, forKey: .fontSize)
        try container.encodeIfPresent(borderWidth, forKey: .borderWidth)
        try container.encodeIfPresent(topicWidth, forKey: .topicWidth)
        try container.encodeIfPresent(cornerRadius, forKey: .cornerRadius)
        try container.encodeIfPresent(fontDesign, forKey: .fontDesign)
        try container.encodeIfPresent(bold, forKey: .bold)
        try container.encodeIfPresent(italic, forKey: .italic)
        try container.encodeIfPresent(strikethrough, forKey: .strikethrough)
        try container.encodeIfPresent(underline, forKey: .underline)
        try container.encodeIfPresent(fillStyle, forKey: .fillStyle)
        try container.encodeIfPresent(borderStyle, forKey: .borderStyle)
    }
}

/// Canvas coordinates remembered after a drag. Absent means "not placed by hand".
public struct MindMapPoint: Equatable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// FreeMind/Freeplane `POSITION` on a node. This is a side, not a canvas point.
public enum MindMapSide: String, Equatable, Sendable, Codable {
    case left
    case right
}

/// One topic in the map. Children are an ordered tree.
/// A value tree cannot point at itself, so a cycle is not representable in memory.
public struct MindMapNode: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var text: String
    public var note: String
    public var isCollapsed: Bool
    public var style: MindMapNodeStyle?
    public var position: MindMapPoint?
    /// FreeMind `LINK`. Absent when the topic has no link.
    public var link: String?
    /// FreeMind `POSITION` (`left` / `right`). Absent when the file did not say.
    public var side: MindMapSide?
    public var children: [MindMapNode]

    public init(
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

    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
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
