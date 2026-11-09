import Foundation
// swift-corelibs-foundation moved XMLParser into FoundationXML. Apple Foundation
// still exports it. This is module availability, not an operating-system branch.
#if canImport(FoundationXML)
import FoundationXML
#endif

/// FreeMind / Freeplane `.mm` XML, written from the public element shape
/// (`map`, `node`, `TEXT`, `richcontent`, `LINK`, `FOLDED`, `POSITION`).
/// No Freeplane source is used.
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

    public static func importMap(_ data: Data) throws -> MindMapDocument {
        let parser = MMXMLParser()
        return try parser.parse(data)
    }

    public static func export(_ document: MindMapDocument) throws -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<map version=\"1.0.1\">\n"
        let roots = document.roots
        if roots.count == 1 {
            xml += render(roots[0], indent: 1)
        } else {
            var wrapper = MindMapNode(text: document.title.isEmpty ? "Mind Map" : document.title)
            wrapper.children = roots
            xml += render(wrapper, indent: 1)
        }
        xml += "</map>\n"
        guard let data = xml.data(using: .utf8) else { throw FlorettaMMError.notXML }
        return data
    }

    private static func render(_ node: MindMapNode, indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        var line = "\(pad)<node TEXT=\"\(escape(node.text))\" ID=\"\(mmID(node.id))\""
        if node.isCollapsed {
            line += " FOLDED=\"true\""
        }
        if let side = node.side {
            line += " POSITION=\"\(side.rawValue)\""
        }
        if let link = node.link, !link.isEmpty {
            line += " LINK=\"\(escape(link))\""
        }
        var body = ""
        if !node.note.isEmpty {
            body += "\(pad)  <richcontent TYPE=\"NOTE\"><html><head></head><body>\(noteHTML(node.note))</body></html></richcontent>\n"
        }
        for child in node.children {
            body += render(child, indent: indent + 1)
        }
        if body.isEmpty {
            return line + "/>\n"
        }
        return line + ">\n" + body + "\(pad)</node>\n"
    }

    private static func noteHTML(_ note: String) -> String {
        note.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "<p>\(escape(String($0)))</p>" }
            .joined()
    }

    private static func mmID(_ id: UUID) -> String {
        "ID_" + id.uuidString.replacingOccurrences(of: "-", with: "")
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

private final class MMXMLParser: NSObject, XMLParserDelegate {
    private struct OpenNode {
        var text = ""
        var note = ""
        var link: String?
        var folded = false
        var side: MindMapSide?
        var nodeRich = ""
        var hasNodeRich = false
        var children: [MindMapNode] = []
    }

    private var stack: [OpenNode] = []
    private var roots: [MindMapNode] = []
    private var sawMap = false
    private var inRich = false
    private var richKind = ""
    private var richText = ""
    private var ignoreDepth = 0
    private var nodeCount = 0
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
        return MindMapDocument(title: title, roots: roots)
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
        if inRich {
            if elementName.caseInsensitiveCompare("br") == .orderedSame {
                richText += "\n"
            }
            return
        }
        switch elementName.lowercased() {
        case "map":
            sawMap = true
        case "node":
            guard stack.count < FlorettaMMCodec.maxDepth else {
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
            var node = OpenNode()
            node.text = attributes["TEXT"] ?? ""
            if let link = attributes["LINK"], !link.isEmpty {
                node.link = link
            }
            if let folded = attributes["FOLDED"] {
                node.folded = folded.caseInsensitiveCompare("true") == .orderedSame
            }
            if let position = attributes["POSITION"], !position.isEmpty {
                switch position.lowercased() {
                case "left": node.side = .left
                case "right": node.side = .right
                default:
                    failure = .unknownPosition(position)
                    parser.abortParsing()
                    return
                }
            }
            stack.append(node)
        case "richcontent":
            inRich = true
            richKind = (attributes["TYPE"] ?? "").uppercased()
            richText = ""
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
        if inRich {
            if elementName.caseInsensitiveCompare("richcontent") == .orderedSame {
                finishRich()
                inRich = false
            } else if ["p", "div", "li", "h1", "h2", "h3", "h4", "tr"].contains(elementName.lowercased()) {
                if !richText.hasSuffix("\n") { richText += "\n" }
            }
            return
        }
        guard elementName.lowercased() == "node" else { return }
        guard let open = stack.popLast() else { return }
        let node = materialize(open)
        if stack.isEmpty {
            roots.append(node)
        } else {
            stack[stack.count - 1].children.append(node)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard failure == nil, inRich, ignoreDepth == 0 else { return }
        richText += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard failure == nil, inRich, ignoreDepth == 0 else { return }
        if let string = String(data: CDATABlock, encoding: .utf8) {
            richText += string
        }
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

    private func finishRich() {
        guard var open = stack.last else { return }
        let plain = plainText(richText)
        switch richKind {
        case "NODE":
            open.hasNodeRich = true
            open.nodeRich = plain
        case "NOTE":
            open.note = plain
        default:
            break
        }
        stack[stack.count - 1] = open
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
            text: text,
            note: note,
            isCollapsed: open.folded,
            link: open.link,
            side: open.side,
            children: open.children
        )
    }

    private func plainText(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
