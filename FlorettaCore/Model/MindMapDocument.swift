import Foundation

/// A mind map.
/// `roots` is the ordered hierarchy and may contain more than one center.
/// `freeNodes` are outside that tree: each has its own id and a canvas point.
/// `stickies` are canvas cards. They are not topics and are not stored in `freeNodes`.
public struct MindMapDocument: Equatable, Sendable {
    /// Additive keys (`freeNodes`, `relationships`, `stickies`, `additionalCanvases`, `xmindForeign`, `opmlForeign`, `mmForeign`) stay on version 1.
    /// A version bump would refuse every existing file. Empty arrays are omitted.
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var title: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var roots: [MindMapNode]
    /// Topics that do not participate in parent/child layout.
    public var freeNodes: [MindMapNode]
    /// Connections between any topics. The canvas does not draw these yet.
    public var relationships: [TopicRelationship]
    /// Canvas cards. Not topics, so they are outside the tree and the node count.
    public var stickies: [StickyNote]
    /// Opaque YAML front matter for a Markdown document, fences included.
    /// Nil when the map is not a Markdown projection. Omitted from `.floretta` JSON when nil.
    public var markdownFrontMatter: String?
    /// Sheets after the first. The first sheet is `title` / `roots` / `freeNodes` / `relationships`.
    /// Empty for a map that did not come from a multi-sheet file. Omitted from JSON when empty.
    public var additionalCanvases: [MindMapCanvas]
    /// XMind bytes and unknown fields. Nil for a map that did not come from `.xmind`.
    /// Omitted from JSON when nil.
    public var xmindForeign: XMindForeign?
    /// OPML bytes and unmapped attributes/elements. Nil when the map did not come from `.opml`.
    /// Omitted from JSON when nil.
    public var opmlForeign: OPMLForeign?
    /// FreeMind bytes and unmapped attributes/elements. Nil when the map did not come from `.mm`.
    /// Omitted from JSON when nil.
    public var mmForeign: MMForeign?

    public init(
        title: String,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        roots: [MindMapNode] = [],
        freeNodes: [MindMapNode] = [],
        relationships: [TopicRelationship] = [],
        stickies: [StickyNote] = [],
        formatVersion: Int = MindMapDocument.currentFormatVersion,
        markdownFrontMatter: String? = nil,
        additionalCanvases: [MindMapCanvas] = [],
        xmindForeign: XMindForeign? = nil,
        opmlForeign: OPMLForeign? = nil,
        mmForeign: MMForeign? = nil
    ) {
        self.formatVersion = formatVersion
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.roots = roots
        self.freeNodes = freeNodes
        self.relationships = relationships
        self.stickies = stickies
        self.markdownFrontMatter = markdownFrontMatter
        self.additionalCanvases = additionalCanvases
        self.xmindForeign = xmindForeign
        self.opmlForeign = opmlForeign
        self.mmForeign = mmForeign
    }
}

/// A stored connection between two topics. Either end may be a tree topic or a free node.
/// Drawing is a later pass; this record is the data layer those lines will read.
public struct TopicRelationship: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var sourceID: UUID
    public var targetID: UUID
    public var title: String

    public init(id: UUID = UUID(), sourceID: UUID, targetID: UUID, title: String = "") {
        self.id = id
        self.sourceID = sourceID
        self.targetID = targetID
        self.title = title
    }
}

extension TopicRelationship: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case sourceID
        case targetID
        case title
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourceID = try container.decode(UUID.self, forKey: .sourceID)
        targetID = try container.decode(UUID.self, forKey: .targetID)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sourceID, forKey: .sourceID)
        try container.encode(targetID, forKey: .targetID)
        if !title.isEmpty {
            try container.encode(title, forKey: .title)
        }
    }
}

/// One topic another topic can connect to. Used by the link menu.
public struct TopicLinkTarget: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var text: String

    public init(id: UUID, text: String) {
        self.id = id
        self.text = text
    }
}

extension MindMapDocument: Codable {
    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case title
        case createdAt
        case modifiedAt
        case roots
        case freeNodes
        case relationships
        case stickies
        case markdownFrontMatter
        case additionalCanvases
        case xmindForeign
        case opmlForeign
        case mmForeign
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .formatVersion)
        guard version == Self.currentFormatVersion else {
            throw FlorettaCodecError.unsupportedVersion(
                found: version,
                supported: Self.currentFormatVersion
            )
        }
        let title = try container.decode(String.self, forKey: .title)
        let createdAt = try FlorettaTimestamp.date(
            from: try container.decode(String.self, forKey: .createdAt)
        )
        let modifiedAt = try FlorettaTimestamp.date(
            from: try container.decode(String.self, forKey: .modifiedAt)
        )
        let roots = try container.decode([MindMapNode].self, forKey: .roots)
        let markdownFrontMatter = try container.decodeIfPresent(String.self, forKey: .markdownFrontMatter)
        let opmlForeign = try container.decodeIfPresent(OPMLForeign.self, forKey: .opmlForeign)
        let mmForeign = try container.decodeIfPresent(MMForeign.self, forKey: .mmForeign)
        let freeNodes = try container.decodeIfPresent([MindMapNode].self, forKey: .freeNodes) ?? []
        let relationships = try container.decodeIfPresent([TopicRelationship].self, forKey: .relationships) ?? []
        let stickies = try container.decodeIfPresent([StickyNote].self, forKey: .stickies) ?? []
        let additionalCanvases = try container.decodeIfPresent([MindMapCanvas].self, forKey: .additionalCanvases) ?? []
        let xmindForeign = try container.decodeIfPresent(XMindForeign.self, forKey: .xmindForeign)
        self.formatVersion = version
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.roots = roots
        self.freeNodes = freeNodes
        self.relationships = relationships
        self.stickies = stickies
        self.markdownFrontMatter = markdownFrontMatter
        self.additionalCanvases = additionalCanvases
        self.xmindForeign = xmindForeign
        self.opmlForeign = opmlForeign
        self.mmForeign = mmForeign
        try FlorettaTree.validate(self)
    }

    public func encode(to encoder: Encoder) throws {
        guard formatVersion == Self.currentFormatVersion else {
            throw FlorettaCodecError.unsupportedVersion(
                found: formatVersion,
                supported: Self.currentFormatVersion
            )
        }
        try FlorettaTree.validate(self)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(title, forKey: .title)
        try container.encode(FlorettaTimestamp.string(from: createdAt), forKey: .createdAt)
        try container.encode(FlorettaTimestamp.string(from: modifiedAt), forKey: .modifiedAt)
        try container.encode(roots, forKey: .roots)
        if !freeNodes.isEmpty {
            try container.encode(freeNodes, forKey: .freeNodes)
        }
        if !relationships.isEmpty {
            try container.encode(relationships, forKey: .relationships)
        }
        if !stickies.isEmpty {
            try container.encode(stickies, forKey: .stickies)
        }
        try container.encodeIfPresent(markdownFrontMatter, forKey: .markdownFrontMatter)
        if !additionalCanvases.isEmpty {
            try container.encode(additionalCanvases, forKey: .additionalCanvases)
        }
        try container.encodeIfPresent(xmindForeign, forKey: .xmindForeign)
        try container.encodeIfPresent(opmlForeign, forKey: .opmlForeign)
        try container.encodeIfPresent(mmForeign, forKey: .mmForeign)
    }
}

/// JSON has no pointers, and `MindMapNode.children` is a value array, so a real pointer
/// cycle cannot be stored. Reusing an ancestor's id is the cyclic case this format can
/// express; any other repeated id is a duplicate. Both are rejected.
enum FlorettaTree {
    static func validate(_ document: MindMapDocument) throws {
        var seen: Set<UUID> = []
        var stack: [UUID] = []
        let primary = try collect(document.roots, document.freeNodes, seen: &seen, stack: &stack)
        var canvasTopics: [Set<UUID>] = []
        for canvas in document.additionalCanvases {
            if !seen.insert(canvas.id).inserted {
                throw FlorettaCodecError.duplicateID(canvas.id)
            }
            canvasTopics.append(try collect(canvas.roots, canvas.freeNodes, seen: &seen, stack: &stack))
        }
        var stickyIDs: Set<UUID> = []
        for sticky in document.stickies {
            if seen.contains(sticky.id) || !stickyIDs.insert(sticky.id).inserted {
                throw FlorettaCodecError.duplicateID(sticky.id)
            }
        }
        var relationshipIDs: Set<UUID> = []
        try check(
            document.relationships,
            within: primary,
            seen: seen,
            stickyIDs: stickyIDs,
            relationshipIDs: &relationshipIDs
        )
        for (index, canvas) in document.additionalCanvases.enumerated() {
            try check(
                canvas.relationships,
                within: canvasTopics[index],
                seen: seen,
                stickyIDs: stickyIDs,
                relationshipIDs: &relationshipIDs
            )
        }
    }

    private static func collect(
        _ roots: [MindMapNode],
        _ freeNodes: [MindMapNode],
        seen: inout Set<UUID>,
        stack: inout [UUID]
    ) throws -> Set<UUID> {
        var ids: Set<UUID> = []
        for root in roots {
            try visit(root, seen: &seen, stack: &stack, ids: &ids)
        }
        for node in freeNodes {
            try visit(node, seen: &seen, stack: &stack, ids: &ids)
        }
        return ids
    }

    private static func check(
        _ relationships: [TopicRelationship],
        within topics: Set<UUID>,
        seen: Set<UUID>,
        stickyIDs: Set<UUID>,
        relationshipIDs: inout Set<UUID>
    ) throws {
        for relationship in relationships {
            if seen.contains(relationship.id)
                || stickyIDs.contains(relationship.id)
                || !relationshipIDs.insert(relationship.id).inserted {
                throw FlorettaCodecError.duplicateID(relationship.id)
            }
            if !topics.contains(relationship.sourceID) || !topics.contains(relationship.targetID) {
                let missing = topics.contains(relationship.sourceID) ? relationship.targetID : relationship.sourceID
                throw FlorettaCodecError.corrupt(
                    "Relationship \(relationship.id.uuidString) points at a missing topic \(missing.uuidString)."
                )
            }
        }
    }

    private static func visit(
        _ node: MindMapNode,
        seen: inout Set<UUID>,
        stack: inout [UUID],
        ids: inout Set<UUID>
    ) throws {
        if stack.contains(node.id) {
            throw FlorettaCodecError.cyclicID(node.id)
        }
        if !seen.insert(node.id).inserted {
            throw FlorettaCodecError.duplicateID(node.id)
        }
        ids.insert(node.id)
        stack.append(node.id)
        for child in node.children {
            try visit(child, seen: &seen, stack: &stack, ids: &ids)
        }
        stack.removeLast()
    }
}

public enum FlorettaTimestamp {
    public static func string(from date: Date) -> String {
        let whole = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded())
        return formatter(fractional: false).string(from: whole)
    }

    public static func date(from string: String) throws -> Date {
        if let date = formatter(fractional: true).date(from: string) {
            return date
        }
        if let date = formatter(fractional: false).date(from: string) {
            return date
        }
        throw FlorettaCodecError.corrupt(
            "Unreadable timestamp \"\(string)\". Use ISO-8601 UTC, for example 2026-11-09T08:00:00Z."
        )
    }

    private static func formatter(fractional: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        var options: ISO8601DateFormatter.Options = [.withInternetDateTime]
        if fractional {
            options.insert(.withFractionalSeconds)
        }
        formatter.formatOptions = options
        return formatter
    }
}

public extension MindMapDocument {
    /// Hierarchy topics plus free nodes, including children stored under a free node.
    /// Sticky notes are not topics and are not included.
    public var topicCount: Int {
        countTopics(roots) + countTopics(freeNodes) + additionalCanvases.reduce(0) { partial, canvas in
            partial + countTopics(canvas.roots) + countTopics(canvas.freeNodes)
        }
    }

    public func sticky(_ id: UUID) -> StickyNote? {
        stickies.first { $0.id == id }
    }

    /// Cards to draw in a PNG or PDF. `included` is the user's choice; the default is to include them.
    public func stickiesForPictureExport(included: Bool = true) -> [StickyNote] {
        included ? stickies : []
    }

    public func isFreeNode(_ id: UUID) -> Bool {
        freeNodes.contains { $0.id == id }
    }

    /// True for a free node and for any topic stored under one.
    public func isInFreeNodeTree(_ id: UUID) -> Bool {
        func walk(_ nodes: [MindMapNode]) -> Bool {
            for node in nodes {
                if node.id == id || walk(node.children) { return true }
            }
            return false
        }
        return walk(freeNodes)
    }

    public func walkTopics(_ visit: (MindMapNode) -> Void) {
        func walk(_ nodes: [MindMapNode]) {
            for node in nodes {
                visit(node)
                walk(node.children)
            }
        }
        walk(roots)
        walk(freeNodes)
    }

    /// Text search. Tree topics come first, then free nodes. Neither list is a parent of the other.
    public func topics(matching query: String) -> [UUID] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        var ids: [UUID] = []
        walkTopics { node in
            if node.text.localizedCaseInsensitiveContains(needle) {
                ids.append(node.id)
            }
        }
        return ids
    }

    public func linkTargets(excluding id: UUID?) -> [TopicLinkTarget] {
        var targets: [TopicLinkTarget] = []
        walkTopics { node in
            if node.id != id {
                targets.append(TopicLinkTarget(id: node.id, text: node.text))
            }
        }
        return targets
    }

    public func relationshipSummary(_ relationship: TopicRelationship, seenFrom id: UUID) -> String {
        let otherID = relationship.sourceID == id ? relationship.targetID : relationship.sourceID
        let name = node(otherID)?.text ?? "缺失的节点"
        if relationship.title.isEmpty { return name }
        return "\(name) · \(relationship.title)"
    }

    /// Appends a topic outside the hierarchy. Children are cleared so it cannot grow a branch.
    @discardableResult
    public mutating func addFreeNode(
        text: String = "自由节点",
        at position: MindMapPoint,
        id: UUID = UUID(),
        note: String = "",
        link: String? = nil,
        attachments: [NodeAttachment] = []
    ) -> UUID {
        let node = MindMapNode(
            id: id,
            text: text,
            note: note,
            position: position,
            link: link,
            attachments: attachments,
            children: []
        )
        freeNodes.append(node)
        return id
    }

    /// Appends a canvas card. Returns nil when `id` is already a topic, a sticky, or a relationship.
    @discardableResult
    public mutating func addSticky(
        text: String = "便签",
        color: StickyColor = .yellow,
        at origin: MindMapPoint,
        width: Double = StickyLimits.defaultWidth,
        height: Double = StickyLimits.defaultHeight,
        id: UUID = UUID()
    ) -> UUID? {
        if node(id) != nil || sticky(id) != nil || relationships.contains(where: { $0.id == id }) {
            return nil
        }
        stickies.append(StickyNote(
            id: id,
            text: text,
            color: color,
            origin: origin,
            width: width,
            height: height
        ))
        return id
    }

    /// Moves and resizes one card. Size is clamped. Returns false when `id` is missing or the origin is not finite.
    @discardableResult
    public mutating func placeSticky(
        _ id: UUID,
        origin: MindMapPoint,
        width: Double,
        height: Double
    ) -> Bool {
        guard origin.x.isFinite, origin.y.isFinite else { return false }
        guard let index = stickies.firstIndex(where: { $0.id == id }) else { return false }
        stickies[index].origin = origin
        stickies[index].width = width
        stickies[index].height = height
        return true
    }

    @discardableResult
    public mutating func moveSticky(_ id: UUID, to origin: MindMapPoint) -> Bool {
        guard let current = sticky(id) else { return false }
        return placeSticky(id, origin: origin, width: current.width, height: current.height)
    }

    @discardableResult
    public mutating func resizeSticky(_ id: UUID, width: Double, height: Double) -> Bool {
        guard let current = sticky(id) else { return false }
        return placeSticky(id, origin: current.origin, width: width, height: height)
    }

    @discardableResult
    public mutating func replaceStickyText(_ id: UUID, with text: String) -> Bool {
        guard let index = stickies.firstIndex(where: { $0.id == id }) else { return false }
        stickies[index].text = text
        return true
    }

    @discardableResult
    public mutating func recolorSticky(_ id: UUID, color: StickyColor) -> Bool {
        guard let index = stickies.firstIndex(where: { $0.id == id }) else { return false }
        stickies[index].color = color
        return true
    }

    @discardableResult
    public mutating func removeSticky(_ id: UUID) -> Bool {
        guard let index = stickies.firstIndex(where: { $0.id == id }) else { return false }
        stickies.remove(at: index)
        return true
    }

    /// The sticky to select after `id` is removed. Does not fall through to a topic.
    public func stickySelection(afterRemoving id: UUID) -> UUID? {
        guard let index = stickies.firstIndex(where: { $0.id == id }) else { return nil }
        if index + 1 < stickies.count { return stickies[index + 1].id }
        if index > 0 { return stickies[index - 1].id }
        return nil
    }

    /// Writes the canvas point. Returns false when `id` is not a free node, so a tree topic is left alone.
    @discardableResult
    public mutating func moveFreeNode(_ id: UUID, to position: MindMapPoint) -> Bool {
        guard let index = freeNodes.firstIndex(where: { $0.id == id }) else { return false }
        freeNodes[index].position = position
        return true
    }

    /// Records a connection between two existing topics. The same topic cannot link to itself.
    @discardableResult
    public mutating func linkTopics(
        from sourceID: UUID,
        to targetID: UUID,
        title: String = "",
        id: UUID = UUID()
    ) -> TopicRelationship? {
        guard sourceID != targetID, node(sourceID) != nil, node(targetID) != nil else { return nil }
        let relationship = TopicRelationship(id: id, sourceID: sourceID, targetID: targetID, title: title)
        relationships.append(relationship)
        return relationship
    }

    private func countTopics(_ nodes: [MindMapNode]) -> Int {
        nodes.reduce(0) { partial, node in
            partial + 1 + countTopics(node.children)
        }
    }
}
