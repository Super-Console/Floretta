import Foundation
// swift-corelibs-foundation moved XMLParser into FoundationXML. Apple Foundation
// still exports it. This is module availability, not an operating-system branch.
#if canImport(FoundationXML)
import FoundationXML
#endif

/// OPML 2.0 outlines. Public shape: `opml` / `head` / `title` / `body` / `outline`,
/// with `text` and the common `_note` attribute. Foundation `XMLParser` only.
///
/// Mapped fields land on `MindMapDocument`. Every other attribute and every
/// non-outline element is kept on `opmlForeign` and written back. When the mapped
/// snapshot still matches the import, export returns the original bytes.
public enum FlorettaOPMLError: Equatable, Sendable, Error {
    case notXML
    case missingOPML
    case missingRoot
    case externalEntity
    case tooDeep
    case tooManyNodes
}

public enum FlorettaOPMLCodec {
    public static let maxDepth = 512
    public static let maxNodes = 100_000

    public static func importOutline(_ data: Data) throws -> MindMapDocument {
        try OPMLXMLParser().parse(data)
    }

    public static func export(_ document: MindMapDocument) throws -> Data {
        if let foreign = document.opmlForeign, foreign.snapshot == OPMLMappedSnapshot(document: document) {
            return foreign.sourceXML
        }
        if let foreign = document.opmlForeign {
            return try rebuild(document, foreign: foreign)
        }
        return try renderNative(document)
    }

    private static func renderNative(_ document: MindMapDocument) throws -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<opml version=\"2.0\">\n<head>\n"
        xml += "<title>\(XMLForeignMarkup.escape(document.title))</title>\n</head>\n<body>\n"
        for root in document.roots {
            xml += renderNative(root, indent: 1)
        }
        xml += "</body>\n</opml>\n"
        guard let data = xml.data(using: .utf8) else { throw FlorettaOPMLError.notXML }
        return data
    }

    private static func renderNative(_ node: MindMapNode, indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        var line = "\(pad)<outline text=\"\(XMLForeignMarkup.escape(node.text))\""
        if !node.note.isEmpty {
            line += " _note=\"\(XMLForeignMarkup.escape(node.note))\""
        }
        if let link = node.link, !link.isEmpty {
            line += " url=\"\(XMLForeignMarkup.escape(link))\""
        }
        if node.children.isEmpty {
            return line + "/>\n"
        }
        var body = line + ">\n"
        for child in node.children {
            body += renderNative(child, indent: indent + 1)
        }
        body += "\(pad)</outline>\n"
        return body
    }

    private static func rebuild(_ document: MindMapDocument, foreign: OPMLForeign) throws -> Data {
        let index = Dictionary(uniqueKeysWithValues: foreign.nodes.map { ($0.id, $0) })
        let opmlAttributes = foreign.residue.opmlAttributes.isEmpty
            ? ["version": "2.0"]
            : foreign.residue.opmlAttributes
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<opml\(XMLForeignMarkup.attributeList(opmlAttributes))>\n"
        xml += "<head\(XMLForeignMarkup.attributeList(foreign.residue.headAttributes))>\n"
        xml += renderHead(document, slots: foreign.residue.headSlots)
        xml += "</head>\n"
        xml += "<body\(XMLForeignMarkup.attributeList(foreign.residue.bodyAttributes))>\n"
        xml += renderChildren(
            document.roots,
            slots: foreign.residue.bodySlots,
            indent: 1,
            index: index
        )
        xml += "</body>\n</opml>\n"
        guard let data = xml.data(using: .utf8) else { throw FlorettaOPMLError.notXML }
        return data
    }

    private static func renderHead(_ document: MindMapDocument, slots: [OPMLHeadSlot]) -> String {
        if slots.isEmpty {
            return "<title>\(XMLForeignMarkup.escape(document.title))</title>\n"
        }
        var xml = ""
        var wroteTitle = false
        for slot in slots {
            switch slot {
            case .title:
                xml += "<title>\(XMLForeignMarkup.escape(document.title))</title>\n"
                wroteTitle = true
            case .element(let element):
                xml += XMLForeignMarkup.render(element, indent: 1)
            }
        }
        if !wroteTitle {
            xml += "<title>\(XMLForeignMarkup.escape(document.title))</title>\n"
        }
        return xml
    }

    private static func renderChildren(
        _ children: [MindMapNode],
        slots: [OPMLContentSlot],
        indent: Int,
        index: [UUID: OPMLNodeResidue]
    ) -> String {
        let childIDs = slots.compactMap { slot -> UUID? in
            if case .child(let id) = slot { return id }
            return nil
        }
        var xml = ""
        if children.map(\.id) == childIDs {
            for slot in slots {
                switch slot {
                case .element(let element):
                    xml += XMLForeignMarkup.render(element, indent: indent)
                case .child(let id):
                    if let child = children.first(where: { $0.id == id }) {
                        xml += renderNode(child, indent: indent, index: index)
                    }
                }
            }
            return xml
        }
        for slot in slots {
            if case .element(let element) = slot {
                xml += XMLForeignMarkup.render(element, indent: indent)
            }
        }
        for child in children {
            xml += renderNode(child, indent: indent, index: index)
        }
        return xml
    }

    private static func renderNode(
        _ node: MindMapNode,
        indent: Int,
        index: [UUID: OPMLNodeResidue]
    ) -> String {
        let pad = String(repeating: "  ", count: indent)
        let residue = index[node.id]
        let attributes = attributes(for: node, residue: residue)
        let line = "\(pad)<outline\(XMLForeignMarkup.attributeList(attributes))"
        let slots = residue?.slots ?? []
        let hasElement = slots.contains { slot in
            if case .element = slot { return true }
            return false
        }
        if node.children.isEmpty, !hasElement {
            return line + "/>\n"
        }
        var body = line + ">\n"
        body += renderChildren(node.children, slots: slots, indent: indent + 1, index: index)
        body += "\(pad)</outline>\n"
        return body
    }

    private static func attributes(for node: MindMapNode, residue: OPMLNodeResidue?) -> [String: String] {
        let link = normalizedLink(node.link)
        guard let residue else {
            var attributes = ["text": node.text]
            if !node.note.isEmpty { attributes["_note"] = node.note }
            if let link { attributes["url"] = link }
            return attributes
        }
        let textSame = node.text == residue.importedText
        let noteSame = node.note == residue.importedNote
        let linkSame = link == residue.importedLink
        if textSame, noteSame, linkSame {
            return residue.attributes
        }
        var attributes = residue.attributes
        if !textSame {
            attributes["text"] = node.text
            let originalText = residue.attributes["text"] ?? ""
            if originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !(residue.attributes["title"] ?? "").isEmpty {
                attributes.removeValue(forKey: "title")
            }
        }
        if !noteSame {
            attributes.removeValue(forKey: "title")
            attributes.removeValue(forKey: "note")
            attributes.removeValue(forKey: "_note")
            if !node.note.isEmpty {
                attributes["_note"] = node.note
            }
        }
        if !linkSame {
            if let link {
                attributes["url"] = link
            } else {
                attributes.removeValue(forKey: "url")
            }
        }
        if attributes["text"] == nil {
            attributes["text"] = node.text
        }
        return attributes
    }

    static func normalizedLink(_ link: String?) -> String? {
        guard let link, !link.isEmpty else { return nil }
        return link
    }
}

private final class OPMLXMLParser: NSObject, XMLParserDelegate {
    private final class OpenOutline {
        var id = UUID()
        var attributes: [String: String] = [:]
        var text = ""
        var note = ""
        var link: String?
        var children: [MindMapNode] = []
        var slots: [OPMLContentSlot] = []
    }

    private var nodeStack: [OpenOutline] = []
    private var foreignStack: [XMLForeignBuilder] = []
    private var roots: [MindMapNode] = []
    private var residues: [OPMLNodeResidue] = []
    private var sawOPML = false
    private var opmlAttributes: [String: String] = [:]
    private var headAttributes: [String: String] = [:]
    private var bodyAttributes: [String: String] = [:]
    private var headSlots: [OPMLHeadSlot] = []
    private var bodySlots: [OPMLContentSlot] = []
    private var inHead = false
    private var inTitle = false
    private var title = ""
    private var nodeCount = 0
    private var foreignCount = 0
    private var failure: FlorettaOPMLError?

    func parse(_ data: Data) throws -> MindMapDocument {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        guard parser.parse(), failure == nil else {
            if let failure { throw failure }
            throw FlorettaOPMLError.notXML
        }
        guard sawOPML else { throw FlorettaOPMLError.missingOPML }
        guard !roots.isEmpty else { throw FlorettaOPMLError.missingRoot }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let documentTitle = trimmed.isEmpty ? roots[0].text : trimmed
        let document = MindMapDocument(title: documentTitle, roots: roots)
        return MindMapDocument(
            title: document.title,
            createdAt: document.createdAt,
            modifiedAt: document.modifiedAt,
            roots: document.roots,
            opmlForeign: OPMLForeign(
                sourceXML: data,
                snapshot: OPMLMappedSnapshot(document: document),
                residue: OPMLDocumentResidue(
                    opmlAttributes: opmlAttributes,
                    headAttributes: headAttributes,
                    bodyAttributes: bodyAttributes,
                    headSlots: headSlots,
                    bodySlots: bodySlots,
                    importedTitle: documentTitle
                ),
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
        case "opml":
            sawOPML = true
            opmlAttributes = attributes
        case "head":
            inHead = true
            headAttributes = attributes
        case "body":
            bodyAttributes = attributes
        case "title" where inHead && nodeStack.isEmpty:
            inTitle = true
            title = ""
        case "outline":
            startOutline(attributes, parser: parser)
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
        switch elementName.lowercased() {
        case "head":
            inHead = false
        case "title" where inTitle:
            inTitle = false
            headSlots.append(.title)
        case "outline":
            endOutline()
        default:
            break
        }
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
        if let foreign = foreignStack.last {
            foreign.appendText(string)
        }
        if inTitle {
            title += string
        }
    }

    private func startOutline(_ attributes: [String: String], parser: XMLParser) {
        guard nodeStack.count < FlorettaOPMLCodec.maxDepth else {
            failure = .tooDeep
            parser.abortParsing()
            return
        }
        guard nodeCount < FlorettaOPMLCodec.maxNodes else {
            failure = .tooManyNodes
            parser.abortParsing()
            return
        }
        nodeCount += 1
        let open = OpenOutline()
        open.attributes = attributes
        applyMapped(attributes, to: open)
        nodeStack.append(open)
    }

    private func applyMapped(_ attributes: [String: String], to open: OpenOutline) {
        let text = attributes["text"] ?? ""
        let title = attributes["title"] ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            open.text = title
        } else {
            open.text = text
            let extra = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let primary = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !extra.isEmpty, extra != primary {
                open.note = extra
            }
        }
        let underscore = attributes["_note"] ?? ""
        let plain = attributes["note"] ?? ""
        open.note = merge(open.note, preferred: underscore, alternate: plain)
        if let url = attributes["url"], !url.isEmpty {
            open.link = url
        }
    }

    private func merge(_ existing: String, preferred: String, alternate: String) -> String {
        let first = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
        let second = alternate.trimmingCharacters(in: .whitespacesAndNewlines)
        var note = existing
        for piece in [first, second] where !piece.isEmpty && piece != note && !note.contains(piece) {
            note = note.isEmpty ? piece : note + "\n" + piece
        }
        return note
    }

    private func endOutline() {
        guard let open = nodeStack.popLast() else { return }
        let node = MindMapNode(
            id: open.id,
            text: open.text,
            note: open.note,
            isCollapsed: false,
            link: open.link,
            side: nil,
            children: open.children
        )
        residues.append(OPMLNodeResidue(
            id: node.id,
            importedText: node.text,
            importedNote: node.note,
            importedLink: FlorettaOPMLCodec.normalizedLink(node.link),
            attributes: open.attributes,
            slots: open.slots
        ))
        if let parent = nodeStack.last {
            parent.children.append(node)
            parent.slots.append(.child(node.id))
        } else {
            roots.append(node)
            bodySlots.append(.child(node.id))
        }
    }

    private func startForeign(_ name: String, attributes: [String: String], parser: XMLParser) {
        guard foreignStack.count < FlorettaOPMLCodec.maxDepth else {
            failure = .tooDeep
            parser.abortParsing()
            return
        }
        guard foreignCount < FlorettaOPMLCodec.maxNodes else {
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
        if inTitle {
            return
        }
        if let node = nodeStack.last {
            node.slots.append(.element(element))
            return
        }
        if inHead {
            headSlots.append(.element(element))
            return
        }
        bodySlots.append(.element(element))
    }
}
