import Foundation

/// An element the OPML or FreeMind codec does not turn into a topic.
/// `XMLParser` does not report attribute order, so a rebuilt file sorts keys.
/// Text and nested elements keep their source order.
public struct XMLForeignElement: Equatable, Sendable, Codable {
    public var name: String
    public var attributes: [String: String]
    public var nodes: [XMLForeignNode]

    public init(name: String, attributes: [String: String], nodes: [XMLForeignNode]) {
        self.name = name
        self.attributes = attributes
        self.nodes = nodes
    }
}

public indirect enum XMLForeignNode: Equatable, Sendable, Codable {
    case text(String)
    case element(XMLForeignElement)
}

enum XMLForeignMarkup {
    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "\n", with: "&#10;")
            .replacingOccurrences(of: "\r", with: "")
    }

    static func attributeList(_ attributes: [String: String]) -> String {
        guard !attributes.isEmpty else { return "" }
        var text = ""
        for key in attributes.keys.sorted() {
            text += " \(key)=\"\(escape(attributes[key] ?? ""))\""
        }
        return text
    }

    /// One indented line. Mixed content stays inline so a later parse sees the same text nodes.
    static func render(_ element: XMLForeignElement, indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        return pad + inline(element) + "\n"
    }

    private static func inline(_ element: XMLForeignElement) -> String {
        var open = "<\(element.name)\(attributeList(element.attributes))"
        if element.nodes.isEmpty {
            return open + "/>"
        }
        open += ">"
        for node in element.nodes {
            switch node {
            case .text(let text):
                open += escape(text)
            case .element(let child):
                open += inline(child)
            }
        }
        open += "</\(element.name)>"
        return open
    }
}

/// Mutable element under construction. Array storage keeps the value-type tree finite.
final class XMLForeignBuilder {
    let name: String
    let attributes: [String: String]
    private var nodes: [XMLForeignNode] = []
    private var pending = ""

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    func appendText(_ string: String) {
        pending += string
    }

    func appendElement(_ element: XMLForeignElement) {
        flush()
        nodes.append(.element(element))
    }

    func take() -> XMLForeignElement {
        flush()
        return XMLForeignElement(name: name, attributes: attributes, nodes: nodes)
    }

    private func flush() {
        if pending.isEmpty { return }
        nodes.append(.text(pending))
        pending = ""
    }
}
