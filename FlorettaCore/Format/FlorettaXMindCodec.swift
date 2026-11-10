import Foundation

/// `.xmind` (ZIP + `content.json`) in both directions.
///
/// Mapped fields land on `MindMapDocument`. Every other JSON key stays in
/// `xmindForeign` and is written back. When the mapped snapshot is unchanged,
/// `content.json` is the original bytes. A mapped edit rebuilds that file and
/// still copies unknown keys and the other zip entries.
///
/// The first sheet is the document tree. Later sheets are `additionalCanvases`.
/// Free nodes are the root topic's `children.detached`. Nested detached topics
/// stay in the foreign bag. Sticky notes are not topics and are not written.
public enum FlorettaXMindError: Error, Equatable, Sendable {
    case notZip
    case missingContent
    /// Kept so existing switches still compile. Multi-sheet files are imported.
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
        if let foreign = document.xmindForeign {
            do {
                try FlorettaTree.validate(document)
            } catch let error as FlorettaCodecError {
                throw FlorettaXMindError.corrupt(error.localizedDescription)
            }
            let content: Data
            if foreign.snapshot == XMindMappedSnapshot(document: document) {
                content = foreign.contentJSON
            } else {
                content = try XMindRebuild.content(document, foreign: foreign)
            }
            return XMindRebuild.zip(content: content, foreign: foreign)
        }
        return try exportNative(document)
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
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: content)
        } catch {
            throw FlorettaXMindError.corrupt("content.json could not be read.")
        }
        guard let sheetValues = parsed as? [Any] else {
            throw FlorettaXMindError.corrupt("content.json is not a sheet array.")
        }
        if sheetValues.isEmpty {
            throw FlorettaXMindError.corrupt("content.json has no sheet.")
        }
        var files: [String: Data] = [:]
        var opaque: [XMindForeignEntry] = []
        var metadata: Data?
        var manifest: Data?
        for entry in entries {
            switch entry.name {
            case "content.json":
                continue
            case "metadata.json":
                metadata = entry.data
            case "manifest.json":
                manifest = entry.data
            default:
                opaque.append(XMindForeignEntry(name: entry.name, data: entry.data))
                if files[entry.name] == nil {
                    files[entry.name] = entry.data
                }
            }
        }
        var used: Set<UUID> = []
        let imported = try sheetValues.map { try importSheet($0, files: files, used: &used) }
        let primary = imported[0]
        var canvases: [MindMapCanvas] = []
        for sheet in imported.dropFirst() {
            var canvasID = XMindIDs.modelID(sheet.foreign.originalID)
            if used.contains(canvasID) {
                canvasID = XMindIDs.modelID("sheet:" + sheet.foreign.originalID)
            }
            if !used.insert(canvasID).inserted {
                throw FlorettaXMindError.corrupt("Duplicate id \(canvasID.uuidString).")
            }
            canvases.append(MindMapCanvas(
                id: canvasID,
                title: sheet.title,
                roots: sheet.roots,
                freeNodes: sheet.freeNodes,
                relationships: sheet.relationships
            ))
        }
        var document = MindMapDocument(
            title: primary.title,
            roots: primary.roots,
            freeNodes: primary.freeNodes,
            relationships: primary.relationships,
            additionalCanvases: canvases
        )
        document.xmindForeign = XMindForeign(
            contentJSON: content,
            metadataJSON: metadata,
            manifestJSON: manifest,
            entries: opaque,
            snapshot: XMindMappedSnapshot(document: document),
            sheets: imported.map(\.foreign)
        )
        do {
            try FlorettaTree.validate(document)
        } catch let error as FlorettaCodecError {
            throw FlorettaXMindError.corrupt(error.localizedDescription)
        }
        return document
    }

    private static func exportNative(_ document: MindMapDocument) throws -> Data {
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

    private static func encode<T: Encodable>(_ value: T, with encoder: JSONEncoder) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            throw FlorettaXMindError.corrupt("Could not write .xmind JSON.")
        }
    }
}

private struct ImportedSheet {
    var title: String
    var roots: [MindMapNode]
    var freeNodes: [MindMapNode]
    var relationships: [TopicRelationship]
    var foreign: XMindSheetForeign
}

private func importSheet(_ any: Any, files: [String: Data], used: inout Set<UUID>) throws -> ImportedSheet {
    guard let object = try XMindJSON.value(from: any).objectValue else {
        throw FlorettaXMindError.corrupt("A sheet is not an object.")
    }
    guard let rawID = object["id"]?.stringValue, !rawID.isEmpty else {
        throw FlorettaXMindError.corrupt("A sheet is missing an id.")
    }
    let title = try jsonString(object["title"], name: "sheet title") ?? ""
    guard let rootObject = object["rootTopic"]?.objectValue else {
        throw FlorettaXMindError.corrupt("A sheet is missing rootTopic.")
    }
    var topics: [String: XMindTopicForeign] = [:]
    let root = try importTopic(rootObject, files: files, used: &used, depth: 0, acceptDetached: true, topics: &topics)
    var relationships: [TopicRelationship] = []
    var relationshipForeign: [String: XMindRelationshipForeign] = [:]
    for value in try jsonArray(object["relationships"], name: "relationships") {
        guard let relation = value.objectValue else {
            throw FlorettaXMindError.corrupt("A relationship is not an object.")
        }
        guard let relationID = relation["id"]?.stringValue, !relationID.isEmpty else {
            throw FlorettaXMindError.corrupt("A relationship is missing an id.")
        }
        guard let end1 = relation["end1Id"]?.stringValue, let end2 = relation["end2Id"]?.stringValue else {
            throw FlorettaXMindError.corrupt("Relationship \(relationID) is missing an end.")
        }
        let modelID = try claim(XMindIDs.modelID(relationID), used: &used)
        let title = try jsonString(relation["title"], name: "relationship title") ?? ""
        let relationship = TopicRelationship(
            id: modelID,
            sourceID: XMindIDs.modelID(end1),
            targetID: XMindIDs.modelID(end2),
            title: title
        )
        relationships.append(relationship)
        relationshipForeign[modelID.uuidString] = XMindRelationshipForeign(originalID: relationID, source: relation)
    }
    try requireEndpoints(relationships, root: root.node, freeNodes: root.detached)
    return ImportedSheet(
        title: title,
        roots: [root.node],
        freeNodes: root.detached,
        relationships: relationships,
        foreign: XMindSheetForeign(
            originalID: rawID,
            source: object,
            topics: topics,
            relationships: relationshipForeign
        )
    )
}

private struct ImportedTopic {
    var node: MindMapNode
    var detached: [MindMapNode]
}

private func importTopic(
    _ object: XMindJSONObject,
    files: [String: Data],
    used: inout Set<UUID>,
    depth: Int,
    acceptDetached: Bool,
    topics: inout [String: XMindTopicForeign]
) throws -> ImportedTopic {
    if depth > 512 {
        throw FlorettaXMindError.corrupt("Topic is nested too deeply.")
    }
    guard let rawID = object["id"]?.stringValue, !rawID.isEmpty else {
        throw FlorettaXMindError.corrupt("A topic is missing an id.")
    }
    let modelID = try claim(XMindIDs.modelID(rawID), used: &used)
    let title = try jsonString(object["title"], name: "topic title") ?? ""
    let note = try noteText(object["notes"])
    let point = try pointValue(object["position"])
    let children = object["children"]?.objectValue
    let attached = try jsonArray(children?["attached"], name: "children.attached")
    let detachedValues = try jsonArray(children?["detached"], name: "children.detached")
    var childNodes: [MindMapNode] = []
    for child in attached {
        guard let childObject = child.objectValue else {
            throw FlorettaXMindError.corrupt("A topic is not an object.")
        }
        let imported = try importTopic(
            childObject,
            files: files,
            used: &used,
            depth: depth + 1,
            acceptDetached: false,
            topics: &topics
        )
        childNodes.append(imported.node)
    }
    var floating: [MindMapNode] = []
    if acceptDetached {
        for child in detachedValues {
            guard let childObject = child.objectValue else {
                throw FlorettaXMindError.corrupt("A floating topic is not an object.")
            }
            let imported = try importTopic(
                childObject,
                files: files,
                used: &used,
                depth: depth + 1,
                acceptDetached: false,
                topics: &topics
            )
            var node = imported.node
            if node.position == nil {
                node.position = MindMapPoint(x: 0, y: 0)
            }
            floating.append(node)
        }
    }
    let style = XMindStyles.importStyle(object)
    let href = try jsonString(object["href"], name: "href")
    var link: String?
    var ownsHref = false
    var resourceHrefs: [XMindResourceHref] = []
    var attachments = florettaAttachments(object)
    if let href {
        let lowered = href.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") || lowered.hasPrefix("mailto:") {
            link = href
            ownsHref = true
        } else if let zipPath = xapZipPath(href), let data = files[zipPath] {
            let hash = sha256Hex(data)
            let filename = attachmentFilename(title: title, zipPath: zipPath)
            attachments.insert(NodeAttachment(
                sha256: hash,
                fileExtension: AttachmentNames.fileExtension(of: filename),
                byteCount: Int64(data.count),
                filename: filename
            ), at: 0)
            resourceHrefs.append(XMindResourceHref(sha256: hash, href: href, zipPath: zipPath))
            ownsHref = true
        }
    }
    // `acceptDetached` is only the sheet root. Its detached children are free nodes
    // and get a point below when the file omitted one. The root itself keeps the file point.
    let node = MindMapNode(
        id: modelID,
        text: title,
        note: note,
        style: style.style,
        position: point,
        link: link,
        attachments: attachments,
        children: childNodes
    )
    topics[modelID.uuidString] = XMindTopicForeign(
        originalID: rawID,
        source: object,
        styleTokens: style.tokens,
        resourceHrefs: resourceHrefs,
        ownsHref: ownsHref
    )
    return ImportedTopic(node: node, detached: floating)
}

private func claim(_ id: UUID, used: inout Set<UUID>) throws -> UUID {
    if !used.insert(id).inserted {
        throw FlorettaXMindError.corrupt("Duplicate id \(id.uuidString).")
    }
    return id
}

private func requireEndpoints(
    _ relationships: [TopicRelationship],
    root: MindMapNode,
    freeNodes: [MindMapNode]
) throws {
    var known: Set<UUID> = []
    func collect(_ node: MindMapNode) {
        known.insert(node.id)
        node.children.forEach(collect)
    }
    collect(root)
    freeNodes.forEach(collect)
    for relationship in relationships where !known.contains(relationship.sourceID) || !known.contains(relationship.targetID) {
        throw FlorettaXMindError.corrupt(
            "Relationship \(relationship.id.uuidString) points at a missing topic."
        )
    }
}

private func jsonArray(_ value: XMindJSONValue?, name: String) throws -> [XMindJSONValue] {
    guard let value else { return [] }
    guard case .array(let items) = value else {
        throw FlorettaXMindError.corrupt("\(name) is not an array.")
    }
    return items
}

private func jsonString(_ value: XMindJSONValue?, name: String) throws -> String? {
    guard let value, value != .null else { return nil }
    guard let string = value.stringValue else {
        throw FlorettaXMindError.corrupt("\(name) is not a string.")
    }
    return string
}

private func noteText(_ value: XMindJSONValue?) throws -> String {
    guard let value else { return "" }
    guard let notes = value.objectValue else {
        throw FlorettaXMindError.corrupt("notes is not an object.")
    }
    guard let plain = notes["plain"] else { return "" }
    guard let object = plain.objectValue else {
        throw FlorettaXMindError.corrupt("notes.plain is not an object.")
    }
    return try jsonString(object["content"], name: "notes.plain.content") ?? ""
}

private func pointValue(_ value: XMindJSONValue?) throws -> MindMapPoint? {
    guard let value else { return nil }
    guard let object = value.objectValue else {
        throw FlorettaXMindError.corrupt("position is not an object.")
    }
    guard let x = object["x"]?.doubleValue(), let y = object["y"]?.doubleValue(), x.isFinite, y.isFinite else {
        throw FlorettaXMindError.corrupt("position is missing x or y.")
    }
    return MindMapPoint(x: x, y: y)
}

private func florettaAttachments(_ object: XMindJSONObject) -> [NodeAttachment] {
    guard case .array(let items) = object["extensions"] else { return [] }
    var attachments: [NodeAttachment] = []
    for item in items {
        guard let ext = item.objectValue,
              ext["provider"]?.stringValue == FlorettaXMindCodec.attachmentProvider,
              let content = ext["content"]?.objectValue,
              case .array(let files) = content["items"] else { continue }
        for file in files {
            guard let fields = file.objectValue,
                  let sha = fields["sha256"]?.stringValue,
                  let filename = fields["filename"]?.stringValue,
                  let byteCount = fields["byteCount"]?.int64Value() else { continue }
            let extName = fields["fileExtension"]?.stringValue ?? ""
            attachments.append(NodeAttachment(
                sha256: sha,
                fileExtension: extName,
                byteCount: byteCount,
                filename: filename
            ))
        }
    }
    return attachments
}

private func xapZipPath(_ href: String) -> String? {
    let pairs = [("xap:resources/", "resources/"), ("xap:attachments/", "attachments/")]
    let lowered = href.lowercased()
    for (prefix, folder) in pairs where lowered.hasPrefix(prefix) {
        let rest = String(href.dropFirst(prefix.count))
        if rest.isEmpty || rest.contains("..") || rest.contains("\\") || rest.hasPrefix("/") {
            return nil
        }
        return folder + rest
    }
    return nil
}

private func attachmentFilename(title: String, zipPath: String) -> String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty, !trimmed.contains("/"), !(trimmed as NSString).pathExtension.isEmpty {
        return trimmed
    }
    let base = (zipPath as NSString).lastPathComponent
    if !base.isEmpty { return base }
    return "附件.bin"
}

private enum XMindIDs {
    static func modelID(_ raw: String) -> UUID {
        if let uuid = UUID(uuidString: raw) { return uuid }
        let hex = sha256Hex(Data(raw.utf8))
        var bytes = [UInt8]()
        bytes.reserveCapacity(16)
        var index = hex.startIndex
        while bytes.count < 16, index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16) ?? 0)
            index = next
        }
        while bytes.count < 16 { bytes.append(0) }
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

private enum XMindStyles {
    static func importStyle(_ object: XMindJSONObject) -> (style: MindMapNodeStyle?, tokens: XMindStyleTokens) {
        var tokens = XMindStyleTokens()
        guard let properties = object["style"]?.objectValue?["properties"]?.objectValue else {
            return (nil, tokens)
        }
        let line = propertyString(properties["line-color"])
        let fill = propertyString(properties["svg:fill"])
        let text = propertyString(properties["fo:color"])
        let family = propertyString(properties["fo:font-family"])
        let size = propertyString(properties["fo:font-size"])
        let weight = propertyString(properties["fo:font-weight"])
        let fontStyle = propertyString(properties["fo:font-style"])
        let decoration = propertyString(properties["fo:text-decoration"])
        let border = propertyString(properties["border-line-color"])
        let borderWidth = propertyString(properties["border-line-width"])
        let borderPattern = propertyString(properties["border-line-pattern"])
        let fillPattern = propertyString(properties["fill-pattern"])
        let interpretedWeight = weight.flatMap(interpretBold)
        let interpretedStyle = fontStyle.flatMap(interpretItalic)
        let mapped = line != nil || fill != nil || text != nil || family != nil || size.flatMap(points) != nil
            || interpretedWeight != nil || interpretedStyle != nil || decoration != nil || border != nil
            || borderWidth.flatMap(points) != nil || borderPattern != nil || fillPattern != nil
        guard mapped else { return (nil, tokens) }
        let color = line ?? fill ?? "#000000"
        tokens.hadLineColor = line != nil
        tokens.importedColorHex = color
        tokens.lineColor = line
        tokens.fill = fill
        tokens.textColor = text
        tokens.fontFamily = family
        tokens.fontSize = size.flatMap(points) == nil ? nil : size
        tokens.fontWeight = interpretedWeight == nil ? nil : weight
        tokens.fontStyle = interpretedStyle == nil ? nil : fontStyle
        tokens.textDecoration = decoration
        tokens.borderColor = border
        tokens.borderWidth = borderWidth.flatMap(points) == nil ? nil : borderWidth
        tokens.borderPattern = borderPattern
        tokens.fillPattern = fillPattern
        var style = MindMapNodeStyle(colorHex: color)
        style.fillHex = fill
        style.textHex = text
        style.fontDesign = family
        style.fontSize = size.flatMap(points)
        style.bold = interpretedWeight
        style.italic = interpretedStyle
        if decoration != nil {
            style.underline = decoration?.contains("underline")
            style.strikethrough = decoration?.contains("line-through")
        }
        style.borderHex = border
        style.borderWidth = borderWidth.flatMap(points)
        style.borderStyle = borderPattern
        style.fillStyle = fillPattern
        return (style, tokens)
    }
}

private func propertyString(_ value: XMindJSONValue?) -> String? {
    switch value {
    case .string(let text):
        return text
    case .number(let token):
        return token
    case .bool(let flag):
        return flag ? "true" : "false"
    default:
        return nil
    }
}

private func points(_ raw: String) -> Double? {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if text.hasSuffix("pt") || text.hasSuffix("px") {
        text = String(text.dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard let value = Double(text), value.isFinite else { return nil }
    return value
}

private func interpretBold(_ token: String) -> Bool? {
    switch token.lowercased() {
    case "bold", "bolder":
        return true
    case "normal", "lighter":
        return false
    default:
        guard let number = Double(token), number.isFinite, number == number.rounded() else { return nil }
        return number >= 600
    }
}

private func interpretItalic(_ token: String) -> Bool? {
    switch token.lowercased() {
    case "italic", "oblique":
        return true
    case "normal":
        return false
    default:
        return nil
    }
}

private enum XMindRebuild {
    static func content(_ document: MindMapDocument, foreign: XMindForeign) throws -> Data {
        var inputs: [(title: String, roots: [MindMapNode], freeNodes: [MindMapNode], relationships: [TopicRelationship])] = [
            (document.title, document.roots, document.freeNodes, document.relationships),
        ]
        for canvas in document.additionalCanvases {
            inputs.append((canvas.title, canvas.roots, canvas.freeNodes, canvas.relationships))
        }
        var sheets: [XMindJSONValue] = []
        for (index, input) in inputs.enumerated() {
            let sheet = index < foreign.sheets.count ? foreign.sheets[index] : nil
            sheets.append(buildSheet(input, foreign: sheet))
        }
        return Data(XMindJSON.write(.array(sheets)).utf8)
    }

    static func zip(content: Data, foreign: XMindForeign) -> Data {
        var entries = [ZipEntry(name: "content.json", data: content)]
        if let metadata = foreign.metadataJSON {
            entries.append(ZipEntry(name: "metadata.json", data: metadata))
        }
        if let manifest = foreign.manifestJSON {
            entries.append(ZipEntry(name: "manifest.json", data: manifest))
        }
        for entry in foreign.entries where entry.name != "content.json"
            && entry.name != "metadata.json"
            && entry.name != "manifest.json" {
            entries.append(ZipEntry(name: entry.name, data: entry.data))
        }
        return ZipArchive.write(entries)
    }

    private static func buildSheet(
        _ input: (title: String, roots: [MindMapNode], freeNodes: [MindMapNode], relationships: [TopicRelationship]),
        foreign: XMindSheetForeign?
    ) -> XMindJSONValue {
        var object = foreign?.source ?? XMindJSONObject()
        object["id"] = .string(foreign?.originalID ?? UUID().uuidString)
        object["class"] = .string("sheet")
        object["title"] = .string(input.title)
        if object["topicPositioning"] == nil {
            object["topicPositioning"] = .string("free")
        }
        object["rootTopic"] = rootTopic(input.roots, freeNodes: input.freeNodes, foreign: foreign)
        if input.relationships.isEmpty {
            object["relationships"] = nil
        } else {
            object["relationships"] = .array(input.relationships.map { buildRelationship($0, foreign: foreign) })
        }
        return .object(object)
    }

    private static func rootTopic(
        _ roots: [MindMapNode],
        freeNodes: [MindMapNode],
        foreign: XMindSheetForeign?
    ) -> XMindJSONValue {
        if roots.count == 1 {
            return buildTopic(roots[0], detached: freeNodes, foreign: foreign)
        }
        let title = roots.isEmpty ? "Mind Map" : roots[0].text
        var object = XMindJSONObject()
        object["id"] = .string(UUID().uuidString)
        object["class"] = .string("topic")
        object["title"] = .string(title)
        let attached = roots.map { buildTopic($0, detached: nil, foreign: foreign) }
        let detached = freeNodes.map { buildTopic($0, detached: nil, foreign: foreign) }
        object["children"] = childrenValue(source: XMindJSONObject(), attached: attached, detached: detached)
        return .object(object)
    }

    private static func buildTopic(
        _ node: MindMapNode,
        detached: [MindMapNode]?,
        foreign: XMindSheetForeign?
    ) -> XMindJSONValue {
        let topic = foreign?.topics[node.id.uuidString]
        var object = topic?.source ?? XMindJSONObject()
        object["id"] = .string(topic?.originalID ?? node.id.uuidString)
        object["class"] = .string("topic")
        object["title"] = .string(node.text)
        object["position"] = positionValue(source: object, position: node.position)
        object["notes"] = notesValue(source: object, note: node.note)
        applyHref(&object, node: node, topic: topic)
        let attached = node.children.map { buildTopic($0, detached: nil, foreign: foreign) }
        let detachedValues = detached?.map { buildTopic($0, detached: nil, foreign: foreign) }
        object["children"] = childrenValue(source: object, attached: attached, detached: detachedValues)
        object["style"] = styleValue(source: object, style: node.style, tokens: topic?.styleTokens ?? XMindStyleTokens())
        object["extensions"] = extensionsValue(
            source: object,
            attachments: node.attachments,
            hrefs: topic?.resourceHrefs ?? []
        )
        return .object(object)
    }

    private static func buildRelationship(
        _ relationship: TopicRelationship,
        foreign: XMindSheetForeign?
    ) -> XMindJSONValue {
        let stored = foreign?.relationships[relationship.id.uuidString]
        var object = stored?.source ?? XMindJSONObject()
        object["id"] = .string(stored?.originalID ?? relationship.id.uuidString)
        object["class"] = .string("relationship")
        object["end1Id"] = .string(externalID(relationship.sourceID, foreign: foreign))
        object["end2Id"] = .string(externalID(relationship.targetID, foreign: foreign))
        if relationship.title.isEmpty {
            object["title"] = nil
        } else {
            object["title"] = .string(relationship.title)
        }
        return .object(object)
    }

    private static func externalID(_ id: UUID, foreign: XMindSheetForeign?) -> String {
        foreign?.topics[id.uuidString]?.originalID ?? id.uuidString
    }

    private static func positionValue(source: XMindJSONObject, position: MindMapPoint?) -> XMindJSONValue? {
        guard let position else { return nil }
        if let original = source["position"],
           let object = original.objectValue,
           object["x"]?.doubleValue() == position.x,
           object["y"]?.doubleValue() == position.y {
            return original
        }
        var point = XMindJSONObject()
        point["x"] = .number(XMindJSON.token(for: position.x))
        point["y"] = .number(XMindJSON.token(for: position.y))
        return .object(point)
    }

    private static func notesValue(source: XMindJSONObject, note: String) -> XMindJSONValue? {
        let originalContent = source["notes"]?.objectValue?["plain"]?.objectValue?["content"]?.stringValue ?? ""
        if note == originalContent {
            return source["notes"]
        }
        var notes = source["notes"]?.objectValue ?? XMindJSONObject()
        var plain = notes["plain"]?.objectValue ?? XMindJSONObject()
        if note.isEmpty {
            plain["content"] = nil
        } else {
            plain["content"] = .string(note)
        }
        notes["plain"] = plain.isEmpty ? nil : .object(plain)
        return notes.isEmpty ? nil : .object(notes)
    }

    private static func applyHref(_ object: inout XMindJSONObject, node: MindMapNode, topic: XMindTopicForeign?) {
        if let link = node.link, !link.isEmpty {
            object["href"] = .string(link)
            return
        }
        if let href = topic?.resourceHrefs.first(where: { ref in
            node.attachments.contains { $0.sha256 == ref.sha256 }
        })?.href {
            object["href"] = .string(href)
            return
        }
        if topic?.ownsHref == true {
            object["href"] = nil
        }
    }

    private static func childrenValue(
        source: XMindJSONObject,
        attached: [XMindJSONValue],
        detached: [XMindJSONValue]?
    ) -> XMindJSONValue? {
        var children = source["children"]?.objectValue ?? XMindJSONObject()
        children["attached"] = attached.isEmpty ? nil : .array(attached)
        if let detached {
            children["detached"] = detached.isEmpty ? nil : .array(detached)
        }
        return children.isEmpty ? nil : .object(children)
    }

    private static func styleValue(
        source: XMindJSONObject,
        style: MindMapNodeStyle?,
        tokens: XMindStyleTokens
    ) -> XMindJSONValue? {
        guard let style else { return source["style"] }
        var styleObject = source["style"]?.objectValue ?? XMindJSONObject()
        var properties = styleObject["properties"]?.objectValue ?? XMindJSONObject()
        let colorChanged: Bool
        if let imported = tokens.importedColorHex {
            colorChanged = !sameColor(imported, style.colorHex)
        } else {
            colorChanged = true
        }
        if tokens.hadLineColor || colorChanged {
            overlayString(&properties, key: "line-color", token: tokens.lineColor, model: style.colorHex, same: sameColor)
        }
        overlayString(&properties, key: "svg:fill", token: tokens.fill, model: style.fillHex, same: sameColor)
        overlayString(&properties, key: "fo:color", token: tokens.textColor, model: style.textHex, same: sameColor)
        overlayString(&properties, key: "fo:font-family", token: tokens.fontFamily, model: style.fontDesign, same: ==)
        overlayPoints(&properties, key: "fo:font-size", token: tokens.fontSize, model: style.fontSize)
        overlayBool(&properties, key: "fo:font-weight", token: tokens.fontWeight, model: style.bold, interpret: interpretBold, yes: "bold", no: "normal")
        overlayBool(&properties, key: "fo:font-style", token: tokens.fontStyle, model: style.italic, interpret: interpretItalic, yes: "italic", no: "normal")
        overlayDecoration(&properties, token: tokens.textDecoration, underline: style.underline, strikethrough: style.strikethrough)
        overlayString(&properties, key: "border-line-color", token: tokens.borderColor, model: style.borderHex, same: sameColor)
        overlayPoints(&properties, key: "border-line-width", token: tokens.borderWidth, model: style.borderWidth)
        overlayString(&properties, key: "border-line-pattern", token: tokens.borderPattern, model: style.borderStyle, same: ==)
        overlayString(&properties, key: "fill-pattern", token: tokens.fillPattern, model: style.fillStyle, same: ==)
        styleObject["properties"] = properties.isEmpty ? nil : .object(properties)
        return styleObject.isEmpty ? nil : .object(styleObject)
    }

    private static func extensionsValue(
        source: XMindJSONObject,
        attachments: [NodeAttachment],
        hrefs: [XMindResourceHref]
    ) -> XMindJSONValue? {
        let linked = Set(hrefs.map(\.sha256))
        var items: [XMindJSONValue] = []
        if case .array(let existing) = source["extensions"] {
            for item in existing {
                let provider = item.objectValue?["provider"]?.stringValue
                if provider == FlorettaXMindCodec.attachmentProvider { continue }
                items.append(item)
            }
        }
        let plain = attachments.filter { !linked.contains($0.sha256) }
        if !plain.isEmpty {
            items.append(florettaExtension(plain))
        }
        return items.isEmpty ? nil : .array(items)
    }

    private static func florettaExtension(_ attachments: [NodeAttachment]) -> XMindJSONValue {
        let files = attachments.map { item -> XMindJSONValue in
            var object = XMindJSONObject()
            object["sha256"] = .string(item.sha256)
            object["fileExtension"] = .string(item.fileExtension)
            object["byteCount"] = .number(String(item.byteCount))
            object["filename"] = .string(item.filename)
            return .object(object)
        }
        var content = XMindJSONObject()
        content["items"] = .array(files)
        var ext = XMindJSONObject()
        ext["provider"] = .string(FlorettaXMindCodec.attachmentProvider)
        ext["content"] = .object(content)
        return .object(ext)
    }
}

private func overlayString(
    _ properties: inout XMindJSONObject,
    key: String,
    token: String?,
    model: String?,
    same: (String, String) -> Bool
) {
    guard let model else {
        if token != nil { properties[key] = nil }
        return
    }
    if let token, same(token, model) {
        properties[key] = .string(token)
    } else {
        properties[key] = .string(model)
    }
}

private func overlayPoints(_ properties: inout XMindJSONObject, key: String, token: String?, model: Double?) {
    guard let model else {
        if token != nil { properties[key] = nil }
        return
    }
    if let token, points(token) == model {
        properties[key] = .string(token)
    } else {
        properties[key] = .string(canonicalPoints(model))
    }
}

private func overlayBool(
    _ properties: inout XMindJSONObject,
    key: String,
    token: String?,
    model: Bool?,
    interpret: (String) -> Bool?,
    yes: String,
    no: String
) {
    guard let model else {
        if token != nil { properties[key] = nil }
        return
    }
    if let token, interpret(token) == model {
        properties[key] = .string(token)
    } else {
        properties[key] = .string(model ? yes : no)
    }
}

private func overlayDecoration(
    _ properties: inout XMindJSONObject,
    token: String?,
    underline: Bool?,
    strikethrough: Bool?
) {
    let key = "fo:text-decoration"
    if underline == nil && strikethrough == nil {
        if token != nil { properties[key] = nil }
        return
    }
    let underlineFlag = underline ?? false
    let strikeFlag = strikethrough ?? false
    if let token, token.contains("underline") == underlineFlag, token.contains("line-through") == strikeFlag {
        properties[key] = .string(token)
        return
    }
    if underlineFlag && strikeFlag {
        properties[key] = .string("underline line-through")
    } else if underlineFlag {
        properties[key] = .string("underline")
    } else if strikeFlag {
        properties[key] = .string("line-through")
    } else {
        properties[key] = nil
    }
}

private func sameColor(_ token: String, _ model: String) -> Bool {
    token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        == model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

private func canonicalPoints(_ value: Double) -> String {
    if value == value.rounded(), abs(value) < 1e6 {
        return "\(Int(value))pt"
    }
    return "\(value)pt"
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
