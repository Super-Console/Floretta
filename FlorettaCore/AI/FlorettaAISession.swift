import Foundation

/// Which public address a file uses. Markdown paths are unstable. `.floretta` UUIDs are the file identity.
public enum FlorettaAIMode: Equatable, Sendable {
    case markdown
    case floretta
}

/// Where a `.floretta` was opened from. Save uses the same container the open path used.
public enum FlorettaAIContainer: Equatable, Sendable {
    case markdown
    case florettaZip
    case florettaLegacy
}

/// Fields an AI may ask to read or write.
/// Markdown mode only persists `text`, `note`, and `link`.
public enum FlorettaAIField: Equatable, Sendable {
    case text
    case note
    case link
    case color
    case style
    case attachment
    case relationship
    case position
    case side
    case isCollapsed

    public static func parse(_ raw: String) -> FlorettaAIField? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "text": return .text
        case "note": return .note
        case "link": return .link
        case "color", "colour": return .color
        case "style": return .style
        case "attachment", "attachments": return .attachment
        case "relationship", "relationships": return .relationship
        case "position": return .position
        case "side": return .side
        case "isCollapsed", "collapsed": return .isCollapsed
        default: return nil
        }
    }
}

/// Copy aligned with `MarkdownModePolicy` / the Markdown-mode strip.
/// `side` has no separate control sentence in the UI; it uses the same 「无法保存」 pattern.
public enum FlorettaMarkdownRefusal {
    public static let color = "Markdown 模式无法保存颜色"
    public static let attachment = "Markdown 模式无法保存附件"
    public static let relationship = "Markdown 模式无法保存关系线"
    public static let position = "Markdown 模式无法保存自由位置"
    public static let side = "Markdown 模式无法保存左右侧"
    public static let collapsed = "Markdown 模式无法保存折叠态"

    public static func message(for field: FlorettaAIField) -> String? {
        switch field {
        case .text, .note, .link:
            return nil
        case .color, .style:
            return color
        case .attachment:
            return attachment
        case .relationship:
            return relationship
        case .position:
            return position
        case .side:
            return side
        case .isCollapsed:
            return collapsed
        }
    }
}

public enum FlorettaAIError: Error, Equatable, LocalizedError {
    case message(String)
    case refused(String)

    public var errorDescription: String? {
        switch self {
        case .message(let text), .refused(let text):
            return text
        }
    }
}

/// One opened project. Path lookup and edits share `MindMapDocument`; there is no second tree.
public struct FlorettaAISession: Equatable, Sendable {
    public var document: MindMapDocument
    public var mode: FlorettaAIMode
    public var container: FlorettaAIContainer
    public var markdownWarnings: [FlorettaMarkdownDocumentWarning]

    public init(
        document: MindMapDocument,
        mode: FlorettaAIMode,
        container: FlorettaAIContainer,
        markdownWarnings: [FlorettaMarkdownDocumentWarning] = []
    ) {
        self.document = document
        self.mode = mode
        self.container = container
        self.markdownWarnings = markdownWarnings
    }

    /// Public address of a topic. Markdown returns a path and never a UUID. `.floretta` returns the UUID.
    public func address(of id: UUID) -> String? {
        switch mode {
        case .markdown:
            return document.nodePath(of: id)?.description
        case .floretta:
            guard document.node(id) != nil else { return nil }
            return id.uuidString
        }
    }

    public func get(_ field: FlorettaAIField, at raw: String) throws -> String {
        try refuseMarkdown(field)
        let id = try requireTopic(raw)
        guard let node = document.node(id) else {
            throw FlorettaAIError.message("找不到节点。")
        }
        return try read(field, node)
    }

    @discardableResult
    public mutating func set(_ field: FlorettaAIField, at raw: String, value: String) throws -> String {
        try refuseMarkdown(field)
        let id = try requireTopic(raw)
        try write(field, id: id, value: value)
        touch()
        return try requireAddress(id)
    }

    /// Appends a child. `raw == "root"` appends a root. Returns the new public address.
    @discardableResult
    public mutating func insertChild(
        under raw: String,
        text: String = "",
        note: String = "",
        link: String? = nil,
        id: UUID = UUID()
    ) throws -> String {
        try ensureFreshID(id)
        let node = makeNode(id: id, text: text, note: note, link: link)
        let parent = try parse(raw)
        switch parent {
        case .forest:
            document.roots.append(node)
        case .topic(let parentID):
            guard document.insertChild(node, under: parentID) else {
                throw FlorettaAIError.message("不能在这个节点下插入子节点。")
            }
        }
        touch()
        return try requireAddress(id)
    }

    /// Inserts a sibling immediately after `raw`. Returns the new public address.
    @discardableResult
    public mutating func insertSibling(
        after raw: String,
        text: String = "",
        note: String = "",
        link: String? = nil,
        id: UUID = UUID()
    ) throws -> String {
        try ensureFreshID(id)
        let anchor = try requireTopic(raw)
        let node = makeNode(id: id, text: text, note: note, link: link)
        guard document.insertSibling(node, after: anchor) else {
            throw FlorettaAIError.message("不能在这个节点后面插入同级。")
        }
        touch()
        return try requireAddress(id)
    }

    public mutating func delete(at raw: String) throws {
        let id = try requireTopic(raw)
        guard document.removeNode(id) else {
            throw FlorettaAIError.message("找不到要删除的节点。")
        }
        touch()
    }

    /// Moves `from` under `to`. `to == "root"` makes it a root.
    /// `index` is the sibling index after the node has been lifted. Nil appends.
    /// The Markdown path of the moved node changes; the `.floretta` UUID does not.
    @discardableResult
    public mutating func move(from rawFrom: String, to rawTo: String, index: Int? = nil) throws -> String {
        let id = try requireTopic(rawFrom)
        let parent = try parse(rawTo)
        let parentID: UUID?
        switch parent {
        case .forest:
            parentID = nil
        case .topic(let destination):
            if destination == id {
                throw FlorettaAIError.message("不能把节点移到自己下面。")
            }
            parentID = destination
        }
        if document.isInFreeNodeTree(id) {
            throw FlorettaAIError.message("自由节点不在 root 路径上，不能按树移动。")
        }
        if let parentID, document.isDescendant(parentID, of: id) || parentID == id {
            throw FlorettaAIError.message("不能把节点移到自己或自己的子孙下面。")
        }
        guard document.canReparent(id, to: parentID) else {
            throw FlorettaAIError.message("不能移动这个节点。")
        }
        let destinationCount: Int
        if let parentID, let parentNode = document.node(parentID) {
            destinationCount = parentNode.children.count
        } else {
            destinationCount = document.roots.count
        }
        let slot = index ?? destinationCount
        guard slot >= 0 else {
            throw FlorettaAIError.message("移动下标不能是负数。")
        }
        guard document.reparent(id, to: parentID, at: slot) else {
            throw FlorettaAIError.message("不能移动这个节点。")
        }
        touch()
        return try requireAddress(id)
    }

    /// One topic per line. Markdown lines are paths. `.floretta` lines are UUIDs.
    /// `depth` is the number of path segments to include, counting a root as 1. Nil lists the whole tree.
    public func tree(depth: Int? = nil) -> String {
        if let depth, depth < 1 { return "" }
        var lines: [String] = []
        switch mode {
        case .markdown:
            appendPaths(document.roots, prefix: [], depth: depth, into: &lines)
        case .floretta:
            appendUUIDs(document.roots, level: 0, depth: depth, into: &lines)
            appendFreeNodes(depth: depth, into: &lines)
            if !document.additionalCanvases.isEmpty {
                lines.append("additionalSheets\t\(document.additionalCanvases.count)")
            }
            if !document.stickies.isEmpty {
                lines.append("stickies\t\(document.stickies.count)")
            }
            if !document.regions.isEmpty {
                lines.append("regions\t\(document.regions.count)")
            }
        }
        if lines.isEmpty { return "" }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Heading-depth share export. This is `FlorettaMarkdown.export`, not the `.md` open/save codec.
    public func exportHeadingMarkdown() -> String {
        FlorettaMarkdown.export(document)
    }

    /// Nested-list document projection. Same bytes `FlorettaMarkdownDocumentCodec.save` writes.
    public func exportDocumentMarkdown() -> String {
        FlorettaMarkdownDocumentCodec.save(document)
    }

    private enum Target: Equatable {
        case forest
        case topic(UUID)
    }

    private func parse(_ raw: String) throws -> Target {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "root" { return .forest }
        switch mode {
        case .markdown:
            if let path = FlorettaNodePath.parse(text) {
                if path.isForest { return .forest }
                return .topic(try document.node(at: path).id)
            }
            if UUID(uuidString: text) != nil {
                throw FlorettaAIError.message(
                    "Markdown 模式没有稳定节点 UUID。临时 UUID 不能当作路径。请用 root/3/1，并在插入、删除或移动后重算。"
                )
            }
            throw FlorettaAIError.message(
                "无法解析路径 \"\(text)\"。Markdown 路径形如 root/3/1，从 0 起，root 是 document.roots。"
            )
        case .floretta:
            if text.hasPrefix("root/") || FlorettaNodePath.parse(text) != nil {
                throw FlorettaAIError.message(
                    ".floretta 用稳定 UUID 寻址。\(text) 是会失效的路径，不能当作 UUID 的别名。"
                )
            }
            guard let id = UUID(uuidString: text) else {
                throw FlorettaAIError.message(
                    "无法解析地址 \"\(text)\"。.floretta 节点用 UUID，森林父级用 root。"
                )
            }
            guard document.node(id) != nil else {
                throw FlorettaAIError.message("找不到节点 \(id.uuidString)。")
            }
            return .topic(id)
        }
    }

    private func requireTopic(_ raw: String) throws -> UUID {
        switch try parse(raw) {
        case .forest:
            throw FlorettaAIError.message("root 是 document.roots 整片森林，不是一个节点。")
        case .topic(let id):
            return id
        }
    }

    private func requireAddress(_ id: UUID) throws -> String {
        guard let address = address(of: id) else {
            throw FlorettaAIError.message("节点不在当前文档的公开地址上。")
        }
        return address
    }

    private func refuseMarkdown(_ field: FlorettaAIField) throws {
        guard mode == .markdown, let message = FlorettaMarkdownRefusal.message(for: field) else { return }
        throw FlorettaAIError.refused(message)
    }

    private func read(_ field: FlorettaAIField, _ node: MindMapNode) throws -> String {
        switch field {
        case .text:
            return node.text
        case .note:
            return node.note
        case .link:
            return node.link ?? ""
        case .color:
            return node.style?.colorHex ?? ""
        case .style:
            return node.style?.fillHex ?? ""
        case .attachment:
            return node.attachments.map { "\($0.filename)\t\($0.byteCount)\t\($0.sha256)" }.joined(separator: "\n")
        case .relationship:
            return document.relationships
                .filter { $0.sourceID == node.id || $0.targetID == node.id }
                .map { "\($0.id.uuidString)\t\($0.sourceID.uuidString)\t\($0.targetID.uuidString)\t\($0.title)" }
                .joined(separator: "\n")
        case .position:
            guard let position = node.position else { return "" }
            return "\(position.x),\(position.y)"
        case .side:
            return node.side?.rawValue ?? ""
        case .isCollapsed:
            return node.isCollapsed ? "true" : "false"
        }
    }

    private mutating func write(_ field: FlorettaAIField, id: UUID, value: String) throws {
        switch field {
        case .text:
            guard document.mutateNode(id, { $0.text = value }) else { throw missing(id) }
        case .note:
            guard document.mutateNode(id, { $0.note = value }) else { throw missing(id) }
        case .link:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard document.mutateNode(id, { $0.link = trimmed.isEmpty ? nil : trimmed }) else { throw missing(id) }
        case .color:
            let hex = try hexColor(value)
            guard document.mutateNode(id, { node in
                if var style = node.style {
                    style.colorHex = hex
                    node.style = style
                } else {
                    node.style = MindMapNodeStyle(colorHex: hex)
                }
            }) else { throw missing(id) }
        case .style:
            let hex = try hexColor(value)
            guard document.mutateNode(id, { node in
                if var style = node.style {
                    style.fillHex = hex
                    node.style = style
                } else {
                    node.style = MindMapNodeStyle(colorHex: hex, fillHex: hex)
                }
            }) else { throw missing(id) }
        case .attachment:
            throw FlorettaAIError.message("附件字节属于 .floretta 容器，不能当作节点字段写入。")
        case .relationship:
            try writeRelationship(from: id, value: value)
        case .position:
            try writePosition(id: id, value: value)
        case .side:
            try writeSide(id: id, value: value)
        case .isCollapsed:
            let flag = try collapsedFlag(value)
            guard document.mutateNode(id, { $0.isCollapsed = flag }) else { throw missing(id) }
        }
    }

    private mutating func writeRelationship(from sourceID: UUID, value: String) throws {
        let parts = value.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let targetText = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let targetID = UUID(uuidString: targetText) else {
            throw FlorettaAIError.message("关系线的值要是目标节点的 UUID。")
        }
        let title = parts.count > 1 ? parts[1] : ""
        guard document.linkTopics(from: sourceID, to: targetID, title: title) != nil else {
            throw FlorettaAIError.message("不能连接这两个节点。")
        }
    }

    private mutating func writePosition(id: UUID, value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            guard document.mutateNode(id, { $0.position = nil }) else { throw missing(id) }
            return
        }
        let parts = trimmed.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, let x = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let y = Double(parts[1].trimmingCharacters(in: .whitespaces)),
              x.isFinite, y.isFinite else {
            throw FlorettaAIError.message("位置要写成 x,y。")
        }
        guard document.mutateNode(id, { $0.position = MindMapPoint(x: x, y: y) }) else { throw missing(id) }
    }

    private mutating func writeSide(id: UUID, value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let side: MindMapSide?
        if trimmed.isEmpty {
            side = nil
        } else if let parsed = MindMapSide(rawValue: trimmed) {
            side = parsed
        } else {
            throw FlorettaAIError.message("左右侧只能是 left、right，或留空清除。")
        }
        guard document.mutateNode(id, { $0.side = side }) else { throw missing(id) }
    }

    private func collapsedFlag(_ value: String) throws -> Bool {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1":
            return true
        case "false", "0":
            return false
        default:
            throw FlorettaAIError.message("折叠态只能是 true 或 false。")
        }
    }

    private func hexColor(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard BranchColor(hex: trimmed) != nil else {
            throw FlorettaAIError.message("颜色要是 #RRGGBB。")
        }
        var raw = trimmed
        if raw.hasPrefix("#") { raw.removeFirst() }
        return "#" + raw.uppercased()
    }

    private func missing(_ id: UUID) -> FlorettaAIError {
        .message("找不到节点 \(id.uuidString)。")
    }

    private func ensureFreshID(_ id: UUID) throws {
        if document.containsIdentifier(id) {
            throw FlorettaAIError.message("节点 id 已存在。")
        }
    }

    private func makeNode(id: UUID, text: String, note: String, link: String?) -> MindMapNode {
        let trimmed = link?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = (trimmed?.isEmpty == false) ? trimmed : nil
        return MindMapNode(id: id, text: text, note: note, link: stored)
    }

    private mutating func touch() {
        document.modifiedAt = Date()
    }

    private func appendPaths(
        _ nodes: [MindMapNode],
        prefix: [Int],
        depth: Int?,
        into lines: inout [String]
    ) {
        if let depth, prefix.count >= depth { return }
        for (index, node) in nodes.enumerated() {
            let path = FlorettaNodePath(indexes: prefix + [index])
            lines.append(line(address: path.description, text: node.text, indent: prefix.count * 2))
            appendPaths(node.children, prefix: path.indexes, depth: depth, into: &lines)
        }
    }

    private func appendUUIDs(
        _ nodes: [MindMapNode],
        level: Int,
        depth: Int?,
        into lines: inout [String]
    ) {
        if let depth, level >= depth { return }
        for node in nodes {
            lines.append(line(address: node.id.uuidString, text: node.text, indent: level * 2))
            appendUUIDs(node.children, level: level + 1, depth: depth, into: &lines)
        }
    }

    private func appendFreeNodes(depth: Int?, into lines: inout [String]) {
        if let depth, depth < 1 { return }
        for node in document.freeNodes where document.nodePath(of: node.id) == nil {
            lines.append("free\t\(node.id.uuidString)\t\(shown(node.text))")
        }
    }

    private func line(address: String, text: String, indent: Int) -> String {
        String(repeating: " ", count: indent) + address + "\t" + shown(text)
    }

    private func shown(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
    }
}
