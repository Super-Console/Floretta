import Foundation

/// A mind map.
/// `roots` is the ordered hierarchy and may contain more than one center.
/// `freeNodes` are outside that tree: each has its own id and a canvas point.
/// `stickies` are canvas cards. They are not topics and are not stored in `freeNodes`.
/// `regions` are resizable canvas zones. They are not topics either: a zone may
/// sit around nodes, and those nodes keep their parents.
public struct MindMapDocument: Equatable, Sendable {
    /// Additive keys (`freeNodes`, `relationships`, `stickies`, `regions`, `summaries`, `boundaries`, `additionalCanvases`, `themeID`, `xmindForeign`, `opmlForeign`, `mmForeign`, `activeCanvasIndex`, `primaryCanvasTitle`, `primaryCanvasViewport`) stay on version 1.
    /// A version bump would refuse every existing file. Empty arrays, the standard theme, canvas 0, and an identity camera are omitted.

    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var title: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var roots: [MindMapNode]
    /// Topics that do not participate in parent/child layout.
    public var freeNodes: [MindMapNode]
    /// Connections between any topics. The canvas and PNG/PDF export draw these
    /// from the topic frames. This array is the only stored copy.
    public var relationships: [TopicRelationship]
    /// Canvas cards. Not topics, so they are outside the tree and the node count.
    public var stickies: [StickyNote]
    /// Canvas zones. Not topics, so they are outside the tree and the node count.
    /// Omitted from JSON when empty.
    public var regions: [CanvasRegion]
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
    /// Preset id from `MapThemeCatalog`. Nil is the standard light/dark pair (墨色).
    /// Omitted from JSON when nil. Branch colors are computed at layout time, not copied onto nodes.
    /// A new map stores `MapThemeCatalog.defaultThemeID`. Opening a file does not fill this in.
    public var themeID: String?
    /// Which canvas the editor shows. 0 is the first sheet (`roots`). Omitted from JSON when 0.
    /// A stored index past the last sheet is read back as 0 so an older file still opens.
    public var activeCanvasIndex: Int
    /// Title of the first sheet when it should differ from `title`. Nil shows `title`.
    /// Omitted from JSON when nil. Later sheets use `MindMapCanvas.title`.
    public var primaryCanvasTitle: String?
    /// Zoom and pan of the first sheet. Later sheets store this on `MindMapCanvas`.
    /// The identity camera (scale 1, no pan) is omitted from JSON.
    public var primaryCanvasViewport: CanvasViewportState

    public init(
        title: String,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        roots: [MindMapNode] = [],
        freeNodes: [MindMapNode] = [],
        relationships: [TopicRelationship] = [],
        stickies: [StickyNote] = [],
        regions: [CanvasRegion] = [],
        formatVersion: Int = MindMapDocument.currentFormatVersion,
        markdownFrontMatter: String? = nil,
        additionalCanvases: [MindMapCanvas] = [],
        xmindForeign: XMindForeign? = nil,
        opmlForeign: OPMLForeign? = nil,
        mmForeign: MMForeign? = nil,
        themeID: String? = nil,
        activeCanvasIndex: Int = 0,
        primaryCanvasTitle: String? = nil,
        primaryCanvasViewport: CanvasViewportState = .standard,
        clock: any ClockPort = FoundationClock()
    ) {
        self.formatVersion = formatVersion
        self.title = title
        self.createdAt = createdAt ?? clock.now()
        self.modifiedAt = modifiedAt ?? clock.now()
        self.roots = roots
        self.freeNodes = freeNodes
        self.relationships = relationships
        self.stickies = stickies
        self.regions = regions
        self.markdownFrontMatter = markdownFrontMatter
        self.additionalCanvases = additionalCanvases
        self.xmindForeign = xmindForeign
        self.opmlForeign = opmlForeign
        self.mmForeign = mmForeign
        self.themeID = MapThemeCatalog.persistedID(themeID)
        self.activeCanvasIndex = activeCanvasIndex
        let trimmedTitle = primaryCanvasTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.primaryCanvasTitle = (trimmedTitle?.isEmpty == false) ? trimmedTitle : nil
        self.primaryCanvasViewport = primaryCanvasViewport
        clampActiveCanvasIndex()
    }

    /// A map the user just created. The official theme id is written on the document.
    /// Importers and `init(from:)` keep using `init`, so an opened file keeps the theme it saved.
    public static func newMap(
        title: String,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        roots: [MindMapNode] = [],
        clock: any ClockPort = FoundationClock()
    ) -> MindMapDocument {
        MindMapDocument(
            title: title,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            roots: roots,
            themeID: MapThemeCatalog.defaultThemeID,
            clock: clock
        )
    }
}

/// A stored connection between two topics. Either end may be a tree topic or a free node.
/// `RelationshipGeometry` reads this record when it draws the line and its label.
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
        case regions
        case markdownFrontMatter
        case additionalCanvases
        case xmindForeign
        case opmlForeign
        case mmForeign
        case themeID
        case activeCanvasIndex
        case primaryCanvasTitle
        case primaryCanvasViewport
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
        let regions = try container.decodeIfPresent([CanvasRegion].self, forKey: .regions) ?? []
        let additionalCanvases = try container.decodeIfPresent([MindMapCanvas].self, forKey: .additionalCanvases) ?? []
        let xmindForeign = try container.decodeIfPresent(XMindForeign.self, forKey: .xmindForeign)
        let themeID = MapThemeCatalog.persistedID(
            try container.decodeIfPresent(String.self, forKey: .themeID)
        )
        let activeCanvasIndex = try container.decodeIfPresent(Int.self, forKey: .activeCanvasIndex) ?? 0
        let primaryCanvasTitle = try container.decodeIfPresent(String.self, forKey: .primaryCanvasTitle)
        let primaryCanvasViewport = try container.decodeIfPresent(
            CanvasViewportState.self,
            forKey: .primaryCanvasViewport
        ) ?? .standard
        self.formatVersion = version
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.roots = roots
        self.freeNodes = freeNodes
        self.relationships = relationships
        self.stickies = stickies
        self.regions = regions
        self.markdownFrontMatter = markdownFrontMatter
        self.additionalCanvases = additionalCanvases
        self.xmindForeign = xmindForeign
        self.opmlForeign = opmlForeign
        self.mmForeign = mmForeign
        self.themeID = themeID
        self.activeCanvasIndex = activeCanvasIndex
        let trimmedTitle = primaryCanvasTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.primaryCanvasTitle = (trimmedTitle?.isEmpty == false) ? trimmedTitle : nil
        self.primaryCanvasViewport = primaryCanvasViewport
        clampActiveCanvasIndex()
        promoteUnmappedTopicTags()
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
        if !regions.isEmpty {
            try container.encode(regions, forKey: .regions)
        }
        try container.encodeIfPresent(markdownFrontMatter, forKey: .markdownFrontMatter)
        if !additionalCanvases.isEmpty {
            try container.encode(additionalCanvases, forKey: .additionalCanvases)
        }
        try container.encodeIfPresent(xmindForeign, forKey: .xmindForeign)
        try container.encodeIfPresent(opmlForeign, forKey: .opmlForeign)
        try container.encodeIfPresent(mmForeign, forKey: .mmForeign)
        if let themeID = MapThemeCatalog.persistedID(themeID) {
            try container.encode(themeID, forKey: .themeID)
        }
        if clampedCanvasIndex != 0 {
            try container.encode(clampedCanvasIndex, forKey: .activeCanvasIndex)
        }
        if let primaryCanvasTitle, !primaryCanvasTitle.isEmpty {
            try container.encode(primaryCanvasTitle, forKey: .primaryCanvasTitle)
        }
        if !primaryCanvasViewport.isStandard {
            try container.encode(primaryCanvasViewport, forKey: .primaryCanvasViewport)
        }
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
        func takeSticky(_ sticky: StickyNote) throws {
            if seen.contains(sticky.id) || !stickyIDs.insert(sticky.id).inserted {
                throw FlorettaCodecError.duplicateID(sticky.id)
            }
        }
        for sticky in document.stickies {
            try takeSticky(sticky)
        }
        for canvas in document.additionalCanvases {
            for sticky in canvas.stickies {
                try takeSticky(sticky)
            }
        }
        var regionIDs: Set<UUID> = []
        func takeRegion(_ region: CanvasRegion) throws {
            if seen.contains(region.id) || stickyIDs.contains(region.id) || !regionIDs.insert(region.id).inserted {
                throw FlorettaCodecError.duplicateID(region.id)
            }
        }
        for region in document.regions {
            try takeRegion(region)
        }
        for canvas in document.additionalCanvases {
            for region in canvas.regions {
                try takeRegion(region)
            }
        }
        var relationshipIDs: Set<UUID> = []
        try check(
            document.relationships,
            within: primary,
            seen: seen,
            stickyIDs: stickyIDs,
            regionIDs: regionIDs,
            relationshipIDs: &relationshipIDs
        )
        for (index, canvas) in document.additionalCanvases.enumerated() {
            try check(
                canvas.relationships,
                within: canvasTopics[index],
                seen: seen,
                stickyIDs: stickyIDs,
                regionIDs: regionIDs,
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
        regionIDs: Set<UUID>,
        relationshipIDs: inout Set<UUID>
    ) throws {
        for relationship in relationships {
            if seen.contains(relationship.id)
                || stickyIDs.contains(relationship.id)
                || regionIDs.contains(relationship.id)
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
        for summary in node.summaries {
            if !seen.insert(summary.id).inserted {
                throw FlorettaCodecError.duplicateID(summary.id)
            }
            try checkRange(summary.rangeStart, summary.rangeEnd, count: node.children.count, id: summary.id, kind: "Summary")
        }
        for boundary in node.boundaries {
            if !seen.insert(boundary.id).inserted {
                throw FlorettaCodecError.duplicateID(boundary.id)
            }
            try checkRange(boundary.rangeStart, boundary.rangeEnd, count: node.children.count, id: boundary.id, kind: "Boundary")
        }
        stack.append(node.id)
        for child in node.children {
            try visit(child, seen: &seen, stack: &stack, ids: &ids)
        }
        stack.removeLast()
    }

    private static func checkRange(_ start: Int, _ end: Int, count: Int, id: UUID, kind: String) throws {
        if start < 0 || end < start || end >= count {
            throw FlorettaCodecError.corrupt(
                "\(kind) \(id.uuidString) covers a child range outside 0..<\(count)."
            )
        }
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
    /// Sticky notes and canvas regions are not topics and are not included.
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
        if walk(freeNodes) { return true }
        for canvas in additionalCanvases where walk(canvas.freeNodes) {
            return true
        }
        return false
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
            if node.text.localizedCaseInsensitiveContains(needle)
                || node.labels.contains(where: { $0.localizedCaseInsensitiveContains(needle) }) {
                ids.append(node.id)
            }
        }
        return ids
    }

    /// Writes user-typed labels. Trims and drops blanks. Returns false when `id` is missing.
    @discardableResult
    public mutating func replaceLabels(_ labels: [String], on id: UUID) -> Bool {
        let cleaned = TopicLabels.normalized(labels)
        return mutateNode(id) { node in
            node.labels = cleaned
        }
    }

    @discardableResult
    public mutating func setTextAlignment(_ alignment: MindMapTextAlignment, on id: UUID) -> Bool {
        mutateOwningNode(where: { $0.id == id }) { $0.textAlignment = alignment }
    }

    /// Sets or clears the priority, progress, or flag on one topic.
    /// Other marker ids, including ones this app does not draw, stay on the same array.
    @discardableResult
    public mutating func setMarker(_ markerID: String?, in group: TopicMarkerGroup, on id: UUID) -> Bool {
        mutateNode(id) { node in
            node.markers = TopicMarkerCatalog.assign(node.markers, markerID: markerID, group: group)
        }
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
        if node(id) != nil || sticky(id) != nil || region(id) != nil || relationships.contains(where: { $0.id == id }) {
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

    public func relationship(_ id: UUID) -> TopicRelationship? {
        relationships.first { $0.id == id }
    }

    /// Writes the label. Returns false when `id` is missing. An unchanged title still returns true.
    @discardableResult
    public mutating func renameRelationship(_ id: UUID, title: String) -> Bool {
        guard let index = relationships.firstIndex(where: { $0.id == id }) else { return false }
        relationships[index].title = title
        return true
    }

    @discardableResult
    public mutating func removeRelationship(_ id: UUID) -> Bool {
        guard let index = relationships.firstIndex(where: { $0.id == id }) else { return false }
        relationships.remove(at: index)
        return true
    }

    /// The relationship to select after `id` is removed. Does not fall through to a topic.
    public func relationshipSelection(afterRemoving id: UUID) -> UUID? {
        guard let index = relationships.firstIndex(where: { $0.id == id }) else { return nil }
        if index + 1 < relationships.count { return relationships[index + 1].id }
        if index > 0 { return relationships[index - 1].id }
        return nil
    }

    public func region(_ id: UUID) -> CanvasRegion? {
        regions.first { $0.id == id }
    }

    /// Appends a canvas zone. Returns nil when `id` is already used.
    /// The zone is not inserted into `roots` or `freeNodes`.
    @discardableResult
    public mutating func addRegion(
        label: String = "专区",
        at origin: MindMapPoint,
        width: Double = CanvasRegionLimits.defaultWidth,
        height: Double = CanvasRegionLimits.defaultHeight,
        id: UUID = UUID()
    ) -> UUID? {
        if containsIdentifier(id) { return nil }
        regions.append(CanvasRegion(
            id: id,
            label: label,
            origin: origin,
            width: width,
            height: height
        ))
        return id
    }

    /// Moves and resizes one zone. Size is clamped. Returns false when `id` is missing or the origin is not finite.
    @discardableResult
    public mutating func placeRegion(
        _ id: UUID,
        origin: MindMapPoint,
        width: Double,
        height: Double
    ) -> Bool {
        guard origin.x.isFinite, origin.y.isFinite else { return false }
        guard let index = regions.firstIndex(where: { $0.id == id }) else { return false }
        regions[index].origin = origin
        regions[index].width = width
        regions[index].height = height
        return true
    }

    @discardableResult
    public mutating func moveRegion(_ id: UUID, to origin: MindMapPoint) -> Bool {
        guard let current = region(id) else { return false }
        return placeRegion(id, origin: origin, width: current.width, height: current.height)
    }

    /// Writes a typed width or height. A locked zone keeps its height/width ratio.
    @discardableResult
    public mutating func setRegionLength(
        _ id: UUID,
        axis: CanvasRegionAxis,
        value: Double
    ) -> Bool {
        guard let current = region(id) else { return false }
        let next = CanvasRegionGeometry.typed(
            width: current.width,
            height: current.height,
            axis: axis,
            value: value,
            locked: current.aspectLocked
        )
        return placeRegion(id, origin: current.origin, width: next.width, height: next.height)
    }

    @discardableResult
    public mutating func setRegionAspectLocked(_ id: UUID, _ locked: Bool) -> Bool {
        guard let index = regions.firstIndex(where: { $0.id == id }) else { return false }
        regions[index].aspectLocked = locked
        return true
    }

    @discardableResult
    public mutating func setRegionShape(_ id: UUID, _ shape: CanvasRegionShape) -> Bool {
        guard let index = regions.firstIndex(where: { $0.id == id }) else { return false }
        regions[index].shape = shape
        return true
    }

    /// Makes the zone a circle: equal sides, ellipse, aspect locked, same center.
    @discardableResult
    public mutating func makeRegionCircle(_ id: UUID) -> Bool {
        guard let current = region(id) else { return false }
        let placement = CanvasRegionGeometry.circle(current)
        guard let index = regions.firstIndex(where: { $0.id == id }) else { return false }
        regions[index].origin = placement.origin
        regions[index].width = placement.width
        regions[index].height = placement.height
        regions[index].shape = .ellipse
        regions[index].aspectLocked = true
        return true
    }

    /// Shrinks or grows the zone around node frames that are fully inside it.
    /// Does not move those nodes and does not change their parents.
    /// Returns false when `id` is missing or no frame is enclosed.
    @discardableResult
    public mutating func fitRegion(_ id: UUID, to frames: [NodeFrame]) -> Bool {
        guard let current = region(id) else { return false }
        guard let placement = CanvasRegionGeometry.fitted(current, around: frames.map(\.frame)) else { return false }
        return placeRegion(id, origin: placement.origin, width: placement.width, height: placement.height)
    }

    @discardableResult
    public mutating func replaceRegionLabel(_ id: UUID, with label: String) -> Bool {
        guard let index = regions.firstIndex(where: { $0.id == id }) else { return false }
        regions[index].label = label
        return true
    }

    @discardableResult
    public mutating func setRegionFill(_ id: UUID, _ color: BranchColor) -> Bool {
        guard let index = regions.firstIndex(where: { $0.id == id }) else { return false }
        regions[index].fill = color
        return true
    }

    @discardableResult
    public mutating func setRegionBorder(_ id: UUID, _ color: BranchColor) -> Bool {
        guard let index = regions.firstIndex(where: { $0.id == id }) else { return false }
        regions[index].border = color
        return true
    }

    @discardableResult
    public mutating func setRegionStrokeWidth(_ id: UUID, _ width: Double) -> Bool {
        guard let index = regions.firstIndex(where: { $0.id == id }) else { return false }
        regions[index].strokeWidth = width
        return true
    }

    @discardableResult
    public mutating func removeRegion(_ id: UUID) -> Bool {
        guard let index = regions.firstIndex(where: { $0.id == id }) else { return false }
        regions.remove(at: index)
        return true
    }

    /// The region to select after `id` is removed. Does not fall through to a topic.
    public func regionSelection(afterRemoving id: UUID) -> UUID? {
        guard let index = regions.firstIndex(where: { $0.id == id }) else { return nil }
        if index + 1 < regions.count { return regions[index + 1].id }
        if index > 0 { return regions[index - 1].id }
        return nil
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

    /// True when the first sheet has at least one summary. Geometry uses this to skip a walk.
    public var hasSummaries: Bool {
        func walk(_ nodes: [MindMapNode]) -> Bool {
            for node in nodes {
                if !node.summaries.isEmpty || walk(node.children) { return true }
            }
            return false
        }
        return walk(roots) || walk(freeNodes)
    }

    /// True when the first sheet has at least one boundary.
    public var hasBoundaries: Bool {
        func walk(_ nodes: [MindMapNode]) -> Bool {
            for node in nodes {
                if !node.boundaries.isEmpty || walk(node.children) { return true }
            }
            return false
        }
        return walk(roots) || walk(freeNodes)
    }

    /// Summaries on the sheet the editor changes. Additional sheets keep their own.
    public var summaryCount: Int {
        countMarks(roots) { $0.summaries.count } + countMarks(freeNodes) { $0.summaries.count }
    }

    /// Boundaries on the sheet the editor changes.
    public var boundaryCount: Int {
        countMarks(roots) { $0.boundaries.count } + countMarks(freeNodes) { $0.boundaries.count }
    }

    /// A topic can be enclosed when it is a child in the main tree.
    public func canEnclose(_ id: UUID?) -> Bool {
        guard let id, parentID(of: id) != nil else { return false }
        return !isInFreeNodeTree(id)
    }

    public func summary(_ id: UUID) -> TopicSummary? {
        var found: TopicSummary?
        walkMarks { node in
            if found == nil, let summary = node.summaries.first(where: { $0.id == id }) {
                found = summary
            }
        }
        return found
    }

    public func boundary(_ id: UUID) -> TopicBoundary? {
        var found: TopicBoundary?
        walkMarks { node in
            if found == nil, let boundary = node.boundaries.first(where: { $0.id == id }) {
                found = boundary
            }
        }
        return found
    }

    /// Summary to select after `id` is removed. Does not fall through to a topic.
    public func summarySelection(afterRemoving id: UUID) -> UUID? {
        var next: UUID?
        walkMarks { node in
            guard next == nil, let index = node.summaries.firstIndex(where: { $0.id == id }) else { return }
            if index + 1 < node.summaries.count {
                next = node.summaries[index + 1].id
            } else if index > 0 {
                next = node.summaries[index - 1].id
            }
        }
        return next
    }

    /// Boundary to select after `id` is removed. Does not fall through to a topic.
    public func boundarySelection(afterRemoving id: UUID) -> UUID? {
        var next: UUID?
        walkMarks { node in
            guard next == nil, let index = node.boundaries.firstIndex(where: { $0.id == id }) else { return }
            if index + 1 < node.boundaries.count {
                next = node.boundaries[index + 1].id
            } else if index > 0 {
                next = node.boundaries[index - 1].id
            }
        }
        return next
    }

    /// Covers one selected child. The summary topic is not inserted into `children`.
    @discardableResult
    public mutating func addSummary(
        covering childID: UUID,
        text: String = "概要",
        id: UUID = UUID()
    ) -> TopicSummary? {
        guard let parentID = parentID(of: childID), let parent = node(parentID) else { return nil }
        guard let index = parent.children.firstIndex(where: { $0.id == childID }) else { return nil }
        return addSummary(under: parentID, rangeStart: index, rangeEnd: index, text: text, id: id)
    }

    /// Covers `children[rangeStart...rangeEnd]` of `parentID`.
    @discardableResult
    public mutating func addSummary(
        under parentID: UUID,
        rangeStart: Int,
        rangeEnd: Int,
        text: String = "概要",
        id: UUID = UUID()
    ) -> TopicSummary? {
        guard !containsIdentifier(id), node(parentID) != nil else { return nil }
        let summary = TopicSummary(id: id, text: text, rangeStart: rangeStart, rangeEnd: rangeEnd)
        let wrote = mutateNode(parentID) { parent in
            guard rangeStart >= 0, rangeEnd >= rangeStart, rangeEnd < parent.children.count else { return }
            parent.summaries.append(summary)
        }
        guard wrote, self.summary(id) != nil else { return nil }
        return summary
    }

    @discardableResult
    public mutating func renameSummary(_ id: UUID, text: String) -> Bool {
        mutateMark(summary: id) { node in
            guard let index = node.summaries.firstIndex(where: { $0.id == id }) else { return }
            node.summaries[index].text = text
        }
    }

    @discardableResult
    public mutating func removeSummary(_ id: UUID) -> Bool {
        mutateMark(summary: id) { node in
            node.summaries.removeAll { $0.id == id }
        }
    }

    /// Encloses one selected child.
    @discardableResult
    public mutating func addBoundary(
        covering childID: UUID,
        title: String = "",
        id: UUID = UUID()
    ) -> TopicBoundary? {
        guard let parentID = parentID(of: childID), let parent = node(parentID) else { return nil }
        guard let index = parent.children.firstIndex(where: { $0.id == childID }) else { return nil }
        return addBoundary(under: parentID, rangeStart: index, rangeEnd: index, title: title, id: id)
    }

    @discardableResult
    public mutating func addBoundary(
        under parentID: UUID,
        rangeStart: Int,
        rangeEnd: Int,
        title: String = "",
        id: UUID = UUID()
    ) -> TopicBoundary? {
        guard !containsIdentifier(id), node(parentID) != nil else { return nil }
        let boundary = TopicBoundary(id: id, title: title, rangeStart: rangeStart, rangeEnd: rangeEnd)
        let wrote = mutateNode(parentID) { parent in
            guard rangeStart >= 0, rangeEnd >= rangeStart, rangeEnd < parent.children.count else { return }
            parent.boundaries.append(boundary)
        }
        guard wrote, self.boundary(id) != nil else { return nil }
        return boundary
    }

    @discardableResult
    public mutating func renameBoundary(_ id: UUID, title: String) -> Bool {
        mutateMark(boundary: id) { node in
            guard let index = node.boundaries.firstIndex(where: { $0.id == id }) else { return }
            node.boundaries[index].title = title
        }
    }

    @discardableResult
    public mutating func removeBoundary(_ id: UUID) -> Bool {
        mutateMark(boundary: id) { node in
            node.boundaries.removeAll { $0.id == id }
        }
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

    public func containsIdentifier(_ id: UUID) -> Bool {
        func marks(_ nodes: [MindMapNode]) -> Bool {
            for node in nodes {
                if node.id == id { return true }
                if node.summaries.contains(where: { $0.id == id }) { return true }
                if node.boundaries.contains(where: { $0.id == id }) { return true }
                if marks(node.children) { return true }
            }
            return false
        }
        if marks(roots) || marks(freeNodes) { return true }
        if stickies.contains(where: { $0.id == id }) { return true }
        if regions.contains(where: { $0.id == id }) { return true }
        if relationships.contains(where: { $0.id == id }) { return true }
        for canvas in additionalCanvases {
            if canvas.id == id || marks(canvas.roots) || marks(canvas.freeNodes) { return true }
            if canvas.relationships.contains(where: { $0.id == id }) { return true }
            if canvas.stickies.contains(where: { $0.id == id }) { return true }
        }
        return false
    }

    private func countMarks(_ nodes: [MindMapNode], _ count: (MindMapNode) -> Int) -> Int {
        nodes.reduce(0) { partial, node in
            partial + count(node) + countMarks(node.children, count)
        }
    }

    private func walkMarks(_ visit: (MindMapNode) -> Void) {
        func walk(_ nodes: [MindMapNode]) {
            for node in nodes {
                visit(node)
                walk(node.children)
            }
        }
        walk(roots)
        walk(freeNodes)
        for canvas in additionalCanvases {
            walk(canvas.roots)
            walk(canvas.freeNodes)
        }
    }

    private mutating func mutateMark(summary id: UUID, _ body: (inout MindMapNode) -> Void) -> Bool {
        mutateOwningNode(where: { $0.summaries.contains { $0.id == id } }, body)
    }

    private mutating func mutateMark(boundary id: UUID, _ body: (inout MindMapNode) -> Void) -> Bool {
        mutateOwningNode(where: { $0.boundaries.contains { $0.id == id } }, body)
    }

    /// Files saved before labels and markers were mapped keep those arrays only in
    /// the XMind source bag. Copy them onto the topic once, then refresh the snapshot
    /// so an unedited export still writes the original `content.json`.
    mutating func promoteUnmappedTopicTags() {
        guard var foreign = xmindForeign, !foreign.snapshot.tagsMapped else { return }
        for sheet in foreign.sheets {
            for (key, topic) in sheet.topics {
                guard let id = UUID(uuidString: key) else { continue }
                let labels = XMindTopicTags.labels(in: topic.source)
                let markers = XMindTopicTags.markers(in: topic.source)
                if labels.isEmpty && markers.isEmpty { continue }
                fillImportedTags(id: id, labels: labels, markers: markers)
            }
        }
        foreign.snapshot = XMindMappedSnapshot(document: self)
        xmindForeign = foreign
    }

    private mutating func fillImportedTags(id: UUID, labels: [String], markers: [TopicMarker]) {
        func walk(_ nodes: inout [MindMapNode]) -> Bool {
            for index in nodes.indices {
                if nodes[index].id == id {
                    if nodes[index].labels.isEmpty { nodes[index].labels = labels }
                    if nodes[index].markers.isEmpty { nodes[index].markers = markers }
                    return true
                }
                if walk(&nodes[index].children) { return true }
            }
            return false
        }
        if walk(&roots) || walk(&freeNodes) { return }
        for index in additionalCanvases.indices {
            if walk(&additionalCanvases[index].roots) || walk(&additionalCanvases[index].freeNodes) {
                return
            }
        }
    }

    private mutating func mutateOwningNode(
        where matches: (MindMapNode) -> Bool,
        _ body: (inout MindMapNode) -> Void
    ) -> Bool {
        func walk(_ nodes: inout [MindMapNode]) -> Bool {
            for index in nodes.indices {
                if matches(nodes[index]) {
                    body(&nodes[index])
                    return true
                }
                if walk(&nodes[index].children) { return true }
            }
            return false
        }
        if walk(&roots) || walk(&freeNodes) { return true }
        for index in additionalCanvases.indices {
            if walk(&additionalCanvases[index].roots) || walk(&additionalCanvases[index].freeNodes) {
                return true
            }
        }
        return false
    }

    private func countTopics(_ nodes: [MindMapNode]) -> Int {
        nodes.reduce(0) { partial, node in
            partial + 1 + countTopics(node.children)
        }
    }
}
