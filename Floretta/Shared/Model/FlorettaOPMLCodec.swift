import FlorettaCore
import Foundation

/// OPML 2.0 outlines. Public shape: `opml` / `head` / `title` / `body` / `outline`,
/// with `text` and the common `_note` attribute. Foundation `XMLParser` only.
enum FlorettaOPMLError: Equatable, Sendable, Error {
    case notXML
    case missingOPML
    case missingRoot
    case externalEntity
    case tooDeep
    case tooManyNodes
}

enum FlorettaOPMLCodec {
    static let maxDepth = 512
    static let maxNodes = 100_000

    static func importOutline(_ data: Data) throws -> MindMapDocument {
        try OPMLXMLParser().parse(data)
    }

    static func export(_ document: MindMapDocument) throws -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<opml version=\"2.0\">\n<head>\n"
        xml += "<title>\(escape(document.title))</title>\n</head>\n<body>\n"
        for root in document.roots {
            xml += render(root, indent: 1)
        }
        xml += "</body>\n</opml>\n"
        guard let data = xml.data(using: .utf8) else { throw FlorettaOPMLError.notXML }
        return data
    }

    private static func render(_ node: MindMapNode, indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        var line = "\(pad)<outline text=\"\(escape(node.text))\""
        if !node.note.isEmpty {
            line += " _note=\"\(escape(node.note))\""
        }
        if let link = node.link, !link.isEmpty {
            line += " url=\"\(escape(link))\""
        }
        if node.children.isEmpty {
            return line + "/>\n"
        }
        var body = line + ">\n"
        for child in node.children {
            body += render(child, indent: indent + 1)
        }
        body += "\(pad)</outline>\n"
        return body
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "\n", with: "&#10;")
            .replacingOccurrences(of: "\r", with: "")
    }
}

private final class OPMLXMLParser: NSObject, XMLParserDelegate {
    private struct OpenOutline {
        var text = ""
        var note = ""
        var link: String?
        var children: [MindMapNode] = []
    }

    private var stack: [OpenOutline] = []
    private var roots: [MindMapNode] = []
    private var sawOPML = false
    private var inHead = false
    private var inTitle = false
    private var title = ""
    private var ignoreDepth = 0
    private var nodeCount = 0
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
        let documentTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return MindMapDocument(
            title: documentTitle.isEmpty ? roots[0].text : documentTitle,
            roots: roots
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
        if ignoreDepth > 0 {
            ignoreDepth += 1
            return
        }
        switch elementName.lowercased() {
        case "opml":
            sawOPML = true
        case "head":
            inHead = true
        case "title":
            if inHead {
                inTitle = true
                title = ""
            } else {
                ignoreDepth = 1
            }
        case "body":
            break
        case "outline":
            guard stack.count < FlorettaOPMLCodec.maxDepth else {
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
            stack.append(outline(from: attributes))
        default:
            ignoreDepth = 1
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if failure != nil { return }
        if ignoreDepth > 0 {
            ignoreDepth -= 1
            return
        }
        switch elementName.lowercased() {
        case "head":
            inHead = false
        case "title":
            inTitle = false
        case "outline":
            guard let open = stack.popLast() else { return }
            let node = MindMapNode(
                text: open.text,
                note: open.note,
                isCollapsed: false,
                link: open.link,
                side: nil,
                children: open.children
            )
            if stack.isEmpty {
                roots.append(node)
            } else {
                stack[stack.count - 1].children.append(node)
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard failure == nil, inTitle, ignoreDepth == 0 else { return }
        title += string
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

    private func outline(from attributes: [String: String]) -> OpenOutline {
        var open = OpenOutline()
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
        return open
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
}
