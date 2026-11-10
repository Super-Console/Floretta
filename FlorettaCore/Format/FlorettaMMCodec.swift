import Foundation
// swift-corelibs-foundation moved XMLParser into FoundationXML. Apple Foundation
// still exports it. This is module availability, not an operating-system branch.
#if canImport(FoundationXML)
import FoundationXML
#endif

/// FreeMind / Freeplane `.mm` XML, written from the public element shape
/// (`map`, `node`, `TEXT`, `richcontent`, `LINK`, `FOLDED`, `POSITION`).
/// No Freeplane source is used.
///
/// Mapped fields land on `MindMapDocument`. Other attributes (`ID`, `CREATED`,
/// colors) and other elements (`icon`, `font`, `edge`, `cloud`, `arrowlink`,
/// `attribute`, `hook`, `encrypted_content`, `richcontent`) stay on `mmForeign`
/// and are written back. When the mapped snapshot still matches the import,
/// export returns the original bytes.
public enum FlorettaMMError: Equatable, Sendable, Error {
    case notXML
    case missingMap
    case missingRoot
    case unknownPosition(String)
    case externalEntity
    case tooDeep
    case tooManyNodes
}

public enum FlorettaMMCodec {
    public static let maxDepth = 512
    public static let maxNodes = 100_000
    static let blockTags: Set<String> = ["p", "div", "li", "h1", "h2", "h3", "h4", "tr"]

    public static func importMap(_ data: Data) throws -> MindMapDocument {
        try MMXMLParser().parse(data)
    }

    public static func export(_ document: MindMapDocument) throws -> Data {
        if let foreign = document.mmForeign, foreign.snapshot == MMMappedSnapshot(document: document) {
            return foreign.sourceXML
        }
        if let foreign = document.mmForeign {
            return try rebuild(document, foreign: foreign)
        }
        return try renderNative(document)
    }

    private static func renderNative(_ document: MindMapDocument) throws -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<map version=\"1.0.1\">\n"
        let roots = document.roots
        if roots.count == 1 {
            xml += renderNative(roots[0], indent: 1)
        } else {
            var wrapper = MindMapNode(text: document.title.isEmpty ? "Mind Map" : document.title)
            wrapper.children = roots
            xml += renderNative(wrapper, indent: 1)
        }
        xml += "</map>\n"
        guard let data = xml.data(using: .utf8) else { throw FlorettaMMError.notXML }
        return data
    }

    private static func renderNative(_ node: MindMapNode, indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        var line = "\(pad)<node TEXT=\"\(XMLForeignMarkup.escape(node.text))\" ID=\"\(mmID(node.id))\""
        if node.isCollapsed {
            line += " FOLDED=\"true\""
        }
        if let side = node.side {
            line += " POSITION=\"\(side.rawValue)\""
        }
        if let link = node.link, !link.isEmpty {
            line += " LINK=\"\(XMLForeignMarkup.escape(link))\""
        }
        var body = ""
        if !node.note.isEmpty {
            body += noteElement(node.note, indent: indent)
        }
        for child in node.children {
            body += renderNative(child, indent: indent + 1)
        }
        if body.isEmpty {
            return line + "/>\n"
        }
        return line + ">\n" + body + "\(pad)</node>\n"
    }

    private static func rebuild(_ document: MindMapDocument, foreign: MMForeign) throws -> Data {
        let index = Dictionary(uniqueKeysWithValues: foreign.nodes.map { ($0.id, $0) })
        let mapAttributes = foreign.residue.mapAttributes.isEmpty
            ? ["version": "1.0.1"]
            : foreign.residue.mapAttributes
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<map\(XMLForeignMarkup.attributeList(mapAttributes))>\n"
        let rootIDs = foreign.residue.slots.compactMap { slot -> UUID? in
            if case .child(let id) = slot { return id }
            return nil
        }
        if document.roots.map(\.id) == rootIDs {
            for slot in foreign.residue.slots {
                switch slot {
                case .element(let element):
                    xml += XMLForeignMarkup.render(element, indent: 1)
                case .child(let id):
                    if let root = document.roots.first(where: { $0.id == id }) {
                        xml += renderNode(root, indent: 1, index: index)
                    }
                }
            }
        } else {
            for slot in foreign.residue.slots {
                if case .element(let element) = slot {
                    xml += XMLForeignMarkup.render(element, indent: 1)
                }
            }
            if document.roots.count == 1 {
                xml += renderNode(document.roots[0], indent: 1, index: index)
            } else {
                var wrapper = MindMapNode(text: document.title.isEmpty ? "Mind Map" : document.title)
                wrapper.children = document.roots
                xml += renderNode(wrapper, indent: 1, index: index)
            }
        }
        xml += "</map>\n"
        guard let data = xml.data(using: .utf8) else { throw FlorettaMMError.notXML }
        return data
    }

    private static func renderNode(
        _ node: MindMapNode,
        indent: Int,
        index: [UUID: MMNodeResidue]
    ) -> String {
        let pad = String(repeating: "  ", count: indent)
        let residue = index[node.id]
        let line = "\(pad)<node\(XMLForeignMarkup.attributeList(attributes(for: node, residue: residue)))"
        let slots = residue?.slots ?? []
        let textSame = residue.map { node.text == $0.importedText } ?? true
        let noteSame = residue.map { node.note == $0.importedNote } ?? node.note.isEmpty
        let childIDs = slots.compactMap { slot -> UUID? in
            if case .child(let id) = slot { return id }
            return nil
        }
        let sameChildren = residue != nil && node.children.map(\.id) == childIDs
        var body = ""
        var noteWritten = false
        func writeNoteIfNeeded() {
            guard !noteSame, !noteWritten, !node.note.isEmpty else { return }
            noteWritten = true
            body += noteElement(node.note, indent: indent)
        }
        func emitElement(_ element: XMLForeignElement) {
            if element.name.caseInsensitiveCompare("richcontent") == .orderedSame {
                let kind = (element.attributes["TYPE"] ?? "").uppercased()
                if kind == "NOTE", !noteSame {
                    writeNoteIfNeeded()
                    return
                }
                let consumed = residue?.nodeRichConsumedIntoNote ?? false
                if kind == "NODE", !textSame || (!noteSame && consumed) {
                    return
                }
            }
            body += XMLForeignMarkup.render(element, indent: indent + 1)
        }
        if sameChildren {
            for slot in slots {
                switch slot {
                case .element(let element):
                    emitElement(element)
                case .child(let id):
                    writeNoteIfNeeded()
                    if let child = node.children.first(where: { $0.id == id }) {
                        body += renderNode(child, indent: indent + 1, index: index)
                    }
                }
            }
        } else {
            for slot in slots {
                if case .element(let element) = slot {
                    emitElement(element)
                }
            }
            for child in node.children {
                writeNoteIfNeeded()
                body += renderNode(child, indent: indent + 1, index: index)
            }
        }
        writeNoteIfNeeded()
        if body.isEmpty {
            return line + "/>\n"
        }
        return line + ">\n" + body + "\(pad)</node>\n"
    }

    private static func attributes(for node: MindMapNode, residue: MMNodeResidue?) -> [String: String] {
        let link = normalizedLink(node.link)
        guard let residue else {
            var attributes = [
                "TEXT": node.text,
                "ID": mmID(node.id),
            ]
            if node.isCollapsed { attributes["FOLDED"] = "true" }
            if let side = node.side { attributes["POSITION"] = side.rawValue }
            if let link { attributes["LINK"] = link }
            return attributes
        }
        let textSame = node.text == residue.importedText
        let noteSame = node.note == residue.importedNote
        let linkSame = link == residue.importedLink
        let foldSame = node.isCollapsed == residue.importedCollapsed
        let sideSame = node.side == residue.importedSide
        if textSame, noteSame, linkSame, foldSame, sideSame {
            return residue.attributes
        }
        var attributes = residue.attributes
        if !textSame {
            attributes["TEXT"] = node.text
        }
        if !foldSame {
            if node.isCollapsed {
                attributes["FOLDED"] = "true"
            } else {
                attributes.removeValue(forKey: "FOLDED")
            }
        }
        if !sideSame {
            if let side = node.side {
                attributes["POSITION"] = side.rawValue
            } else {
                attributes.removeValue(forKey: "POSITION")
            }
        }
        if !linkSame {
            if let link {
                attributes["LINK"] = link
            } else {
                attributes.removeValue(forKey: "LINK")
            }
        }
        if attributes["ID"] == nil {
            attributes["ID"] = residue.originalID ?? mmID(node.id)
        }
        if attributes["TEXT"] == nil {
            attributes["TEXT"] = node.text
        }
        return attributes
    }

    private static func noteElement(_ note: String, indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        return "\(pad)  <richcontent TYPE=\"NOTE\"><html><head></head><body>\(noteHTML(note))</body></html></richcontent>\n"
    }

    private static func noteHTML(_ note: String) -> String {
        note.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "<p>\(XMLForeignMarkup.escape(String($0)))</p>" }
            .joined()
    }

    static func mmID(_ id: UUID) -> String {
        "ID_" + id.uuidString.replacingOccurrences(of: "-", with: "")
    }

    static func normalizedLink(_ link: String?) -> String? {
        guard let link, !link.isEmpty else { return nil }
        return link
    }

    /// `ID_` plus 32 hex digits is the id this codec writes. Other FreeMind ids stay strings.
    static func uuid(fromFreeMindID id: String) -> UUID? {
        guard id.count == 35 else { return nil }
        let prefix = id.prefix(3)
        guard prefix == "ID_" || prefix == "id_" else { return nil }
        let hex = id.dropFirst(3)
        guard hex.allSatisfy(\.isHexDigit) else { return nil }
        let raw = String(hex)
        let formatted = "\(raw.prefix(8))-\(raw.dropFirst(8).prefix(4))-\(raw.dropFirst(12).prefix(4))-\(raw.dropFirst(16).prefix(4))-\(raw.suffix(12))"
        return UUID(uuidString: formatted)
    }

    static func plainText(of element: XMLForeignElement) -> String {
        var raw = ""
        func walk(_ node: XMLForeignElement) {
            if node.name.caseInsensitiveCompare("br") == .orderedSame {
                raw += "\n"
                return
            }
            for child in node.nodes {
                switch child {
                case .text(let text):
                    raw += text
                case .element(let element):
                    walk(element)
                }
            }
            if blockTags.contains(node.name.lowercased()), !raw.hasSuffix("\n") {
                raw += "\n"
            }
        }
        walk(element)
        return squeeze(raw)
    }

    static func squeeze(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

private final class MMXMLParser: NSObject, XMLParserDelegate {
    private final class OpenNode {
        var id = UUID()
        var originalID: String?
        var attributes: [String: String] = [:]
        var text = ""
        var note = ""
        var link: String?
        var folded = false
        var side: MindMapSide?
        var nodeRich = ""
        var hasNodeRich = false
        var children: [MindMapNode] = []
        var slots: [MMContentSlot] = []
    }

    private var nodeStack: [OpenNode] = []
    private var foreignStack: [XMLForeignBuilder] = []
    private var roots: [MindMapNode] = []
    private var residues: [MMNodeResidue] = []
    private var mapSlots: [MMContentSlot] = []
    private var mapAttributes: [String: String] = [:]
    private var sawMap = false
    private var seenIDs: Set<UUID> = []
    private var nodeCount = 0
    private var foreignCount = 0
    private var failure: FlorettaMMError?

    func parse(_ data: Data) throws -> MindMapDocument {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        guard parser.parse(), failure == nil else {
            if let failure { throw failure }
            throw FlorettaMMError.notXML
        }
        guard sawMap else { throw FlorettaMMError.missingMap }
        guard !roots.isEmpty else { throw FlorettaMMError.missingRoot }
        let title = roots.count == 1 ? roots[0].text : "Imported"
        let document = MindMapDocument(title: title, roots: roots)
        return MindMapDocument(
            title: document.title,
            createdAt: document.createdAt,
            modifiedAt: document.modifiedAt,
            roots: document.roots,
            mmForeign: MMForeign(
                sourceXML: data,
                snapshot: MMMappedSnapshot(document: document),
                residue: MMDocumentResidue(mapAttributes: mapAttributes, slots: mapSlots),
                nodes: residues
            )
        )
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String]
    ) {
        if failure != nil { return }
        let attributes = Dictionary(uniqueKeysWithValues: attributes.map { ($0.key, $0.value) })
        if !foreignStack.isEmpty {
            startForeign(elementName, attributes: attributes, parser: parser)
            return
        }
        switch elementName.lowercased() {
        case "map":
            sawMap = true
            mapAttributes = attributes
        case "node":
            startNode(attributes, parser: parser)
        default:
            startForeign(elementName, attributes: attributes, parser: parser)
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if failure != nil { return }
        if !foreignStack.isEmpty {
            endForeign()
            return
        }
        guard elementName.lowercased() == "node" else { return }
        endNode()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        captureText(string)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let string = String(data: CDATABlock, encoding: .utf8) else { return }
        captureText(string)
    }

    func parser(_ parser: XMLParser, foundIgnorableWhitespace whitespaceString: String) {
        captureText(whitespaceString)
    }

    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
        failure = .externalEntity
        parser.abortParsing()
        return nil
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if failure == nil {
            failure = .notXML
        }
    }

    private func captureText(_ string: String) {
        guard failure == nil else { return }
        foreignStack.last?.appendText(string)
    }

    private func startNode(_ attributes: [String: String], parser: XMLParser) {
        guard nodeStack.count < FlorettaMMCodec.maxDepth else {
            failure = .tooDeep
            parser.abortParsing()
            return
        }
        guard nodeCount < FlorettaMMCodec.maxNodes else {
            failure = .tooManyNodes
            parser.abortParsing()
            return
        }
        nodeCount += 1
        let open = OpenNode()
        open.attributes = attributes
        open.text = attributes["TEXT"] ?? ""
        if let rawID = attributes["ID"] {
            open.originalID = rawID
            if let parsed = FlorettaMMCodec.uuid(fromFreeMindID: rawID), seenIDs.insert(parsed).inserted {
                open.id = parsed
            } else if !seenIDs.insert(open.id).inserted {
                open.id = UUID()
                seenIDs.insert(open.id)
            }
        } else {
            seenIDs.insert(open.id)
        }
        if let link = attributes["LINK"], !link.isEmpty {
            open.link = link
        }
        if let folded = attributes["FOLDED"] {
            open.folded = folded.caseInsensitiveCompare("true") == .orderedSame
        }
        if let position = attributes["POSITION"], !position.isEmpty {
            switch position.lowercased() {
            case "left": open.side = .left
            case "right": open.side = .right
            default:
                failure = .unknownPosition(position)
                parser.abortParsing()
                return
            }
        }
        nodeStack.append(open)
    }

    private func endNode() {
        guard let open = nodeStack.popLast() else { return }
        let node = materialize(open)
        residues.append(MMNodeResidue(
            id: node.id,
            importedText: node.text,
            importedNote: node.note,
            importedLink: FlorettaMMCodec.normalizedLink(node.link),
            importedCollapsed: node.isCollapsed,
            importedSide: node.side,
            attributes: open.attributes,
            originalID: open.originalID,
            nodeRichConsumedIntoNote: nodeRichConsumed(open),
            slots: open.slots
        ))
        if let parent = nodeStack.last {
            parent.children.append(node)
            parent.slots.append(.child(node.id))
        } else {
            roots.append(node)
            mapSlots.append(.child(node.id))
        }
    }

    private func nodeRichConsumed(_ open: OpenNode) -> Bool {
        guard open.hasNodeRich else { return false }
        let rich = open.nodeRich.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = open.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return false }
        return !rich.isEmpty && rich != title
    }

    private func materialize(_ open: OpenNode) -> MindMapNode {
        var text = open.text
        var note = open.note
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, open.hasNodeRich {
            text = open.nodeRich
        } else if open.hasNodeRich {
            let rich = open.nodeRich.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !rich.isEmpty, rich != title, !note.contains(rich) {
                note = note.isEmpty ? rich : note + "\n" + rich
            }
        }
        return MindMapNode(
            id: open.id,
            text: text,
            note: note,
            isCollapsed: open.folded,
            link: open.link,
            side: open.side,
            children: open.children
        )
    }

    private func startForeign(_ name: String, attributes: [String: String], parser: XMLParser) {
        guard foreignStack.count < FlorettaMMCodec.maxDepth else {
            failure = .tooDeep
            parser.abortParsing()
            return
        }
        guard foreignCount < FlorettaMMCodec.maxNodes else {
            failure = .tooManyNodes
            parser.abortParsing()
            return
        }
        foreignCount += 1
        foreignStack.append(XMLForeignBuilder(name: name, attributes: attributes))
    }

    private func endForeign() {
        guard let builder = foreignStack.popLast() else { return }
        let element = builder.take()
        if let parent = foreignStack.last {
            parent.appendElement(element)
            return
        }
        if element.name.caseInsensitiveCompare("richcontent") == .orderedSame, let node = nodeStack.last {
            applyRich(element, to: node)
        }
        if let node = nodeStack.last {
            node.slots.append(.element(element))
        } else {
            mapSlots.append(.element(element))
        }
    }

    private func applyRich(_ element: XMLForeignElement, to node: OpenNode) {
        let plain = FlorettaMMCodec.plainText(of: element)
        switch (element.attributes["TYPE"] ?? "").uppercased() {
        case "NODE":
            node.hasNodeRich = true
            node.nodeRich = plain
        case "NOTE":
            node.note = plain
        default:
            break
        }
    }
}
