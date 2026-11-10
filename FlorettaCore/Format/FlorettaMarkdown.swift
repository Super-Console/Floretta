import Foundation

/// Optional 「导出为…」preset. Heading depth (`#`, `##`, `###`) follows outline depth.
/// Notes are blockquotes. Links use `[text](url)`.
///
/// Import reads that heading shape and also nested lists (`-`, `*`, `+`, `1.`).
/// A list item hangs under the current heading, or forms its own tree when no heading is open.
/// Deeper indent is a child; the same indent is a sibling. Export still writes headings only,
/// so a list outline round-trips as headings. Any other non-empty line is an error and names its line.
///
/// This is not open/save for `.md` documents. That projection is
/// `FlorettaMarkdownDocumentCodec` (nested `- ` lists, H1 sections only).
/// Free nodes are not written: Markdown has no floating topic, and they must not become children.
/// Sticky notes are not topics and are not written. List markers are not attachments.
public enum FlorettaMarkdownError: Error, Equatable, LocalizedError {
    case notUTF8
    case empty
    case unsupportedLine(line: Int, content: String)
    case orphanNote(line: Int)
    case tooDeep(line: Int)
    case tooManyNodes

    public var errorDescription: String? {
        switch self {
        case .notUTF8:
            return "Markdown 不是 UTF-8。"
        case .empty:
            return "Markdown 里没有标题或列表。"
        case .unsupportedLine(let line, let content):
            return "第 \(line) 行：无法对应导图：\(content)"
        case .orphanNote(let line):
            return "第 \(line) 行：引用没有可附着的节点。"
        case .tooDeep(let line):
            return "第 \(line) 行：嵌套超过 \(FlorettaMarkdown.maxDepth) 层。"
        case .tooManyNodes:
            return "节点超过 \(FlorettaMarkdown.maxNodes) 个。"
        }
    }
}

public enum FlorettaMarkdown {
    /// Same ceilings as the other outline importers. Deeper than this cannot be encoded.
    public static let maxDepth = 512
    public static let maxNodes = 100_000

    public static func export(_ document: MindMapDocument) -> String {
        let document = document.singleTreeExport()
        var lines: [String] = []
        func walk(_ nodes: [MindMapNode], depth: Int) {
            for node in nodes {
                let marks = String(repeating: "#", count: max(depth, 1))
                lines.append("\(marks) \(heading(node))")
                if !node.note.isEmpty {
                    for line in node.note.split(separator: "\n", omittingEmptySubsequences: false) {
                        lines.append("> \(line)")
                    }
                }
                lines.append("")
                walk(node.children, depth: depth + 1)
            }
        }
        walk(document.roots, depth: 1)
        return lines.joined(separator: "\n")
    }

    private static func heading(_ node: MindMapNode) -> String {
        let text = node.text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
        guard let link = node.link, !link.isEmpty else { return text }
        let label = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
        let url = link.replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: ")", with: "%29")
        return "[\(label)](\(url))"
    }

    public static func importOutline(_ data: Data) throws -> MindMapDocument {
        guard let text = String(data: data, encoding: .utf8) else {
            throw FlorettaMarkdownError.notUTF8
        }
        return try importOutline(text)
    }

    public static func importOutline(_ text: String) throws -> MindMapDocument {
        try OutlineParser(text: text).parse()
    }

    private struct OutlineFrame {
        /// ATX hash count. Nil for a list item, so a later heading is never placed under a bullet.
        var hashDepth: Int?
        /// Marker column. Nil for a heading. A larger indent is a child; an equal indent is a sibling.
        var indent: Int?
        var node: MindMapNode
        var treeDepth: Int
    }

    /// Headings and lists share one stack. Export still emits headings, so either shape
    /// re-imports to the same text, notes, links, and parent/child order.
    private struct OutlineParser {
        private let text: String
        private var roots: [MindMapNode] = []
        private var stack: [OutlineFrame] = []
        private var nodeCount = 0

        init(text: String) {
            self.text = text
        }

        func parse() throws -> MindMapDocument {
            var parser = self
            return try parser.parseMutating()
        }

        private mutating func parseMutating() throws -> MindMapDocument {
            var normalized = text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            if normalized.hasPrefix("\u{feff}") {
                normalized.removeFirst()
            }
            let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for (offset, line) in lines.enumerated() {
                let number = offset + 1
                if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                if let note = noteText(line) {
                    try appendNote(note, line: number)
                    continue
                }
                if let heading = markdownHeading(line) {
                    try pushHeading(heading, line: number)
                    continue
                }
                if let item = listItem(line) {
                    try pushList(item, line: number)
                    continue
                }
                throw FlorettaMarkdownError.unsupportedLine(line: number, content: snippet(line))
            }
            closeHeadings(through: 1)
            guard !roots.isEmpty else { throw FlorettaMarkdownError.empty }
            let title = roots.count == 1 ? roots[0].text : "Markdown"
            return MindMapDocument(title: title, roots: roots)
        }

        private mutating func appendNote(_ note: String, line: Int) throws {
            guard !stack.isEmpty else { throw FlorettaMarkdownError.orphanNote(line: line) }
            if stack[stack.count - 1].node.note.isEmpty {
                stack[stack.count - 1].node.note = note
            } else {
                stack[stack.count - 1].node.note += "\n" + note
            }
        }

        private mutating func pushHeading(_ heading: (depth: Int, text: String), line: Int) throws {
            closeLists()
            closeHeadings(through: heading.depth)
            let parsed = parseHeadingText(heading.text)
            let node = try makeNode(text: parsed.text, link: parsed.link, line: line)
            stack.append(
                OutlineFrame(
                    hashDepth: heading.depth,
                    indent: nil,
                    node: node,
                    treeDepth: (stack.last?.treeDepth ?? 0) + 1
                )
            )
        }

        private mutating func pushList(_ item: (indent: Int, text: String), line: Int) throws {
            closeLists(atIndent: item.indent)
            let parsed = parseHeadingText(item.text)
            let node = try makeNode(text: parsed.text, link: parsed.link, line: line)
            stack.append(
                OutlineFrame(
                    hashDepth: nil,
                    indent: item.indent,
                    node: node,
                    treeDepth: (stack.last?.treeDepth ?? 0) + 1
                )
            )
        }

        private mutating func makeNode(text: String, link: String?, line: Int) throws -> MindMapNode {
            let treeDepth = (stack.last?.treeDepth ?? 0) + 1
            if treeDepth > FlorettaMarkdown.maxDepth {
                throw FlorettaMarkdownError.tooDeep(line: line)
            }
            if nodeCount >= FlorettaMarkdown.maxNodes {
                throw FlorettaMarkdownError.tooManyNodes
            }
            nodeCount += 1
            return MindMapNode(text: text, link: link)
        }

        /// A heading closes every open bullet first, then headings at the same or deeper hash level.
        private mutating func closeLists(atIndent indent: Int = Int.min) {
            while let last = stack.last, let lastIndent = last.indent, lastIndent >= indent {
                stack.removeLast()
                attach(last.node)
            }
        }

        private mutating func closeHeadings(through depth: Int) {
            closeLists()
            while let last = stack.last, let hashDepth = last.hashDepth, hashDepth >= depth {
                stack.removeLast()
                attach(last.node)
            }
        }

        private mutating func attach(_ node: MindMapNode) {
            if stack.isEmpty {
                roots.append(node)
            } else {
                stack[stack.count - 1].node.children.append(node)
            }
        }
    }

    /// Column-0 ATX only. `# ` with nothing after the separator is an empty topic so a blank
    /// list item can round-trip through the heading export. `#######` stays a heading: export
    /// writes one `#` per tree level and does not stop at 6.
    private static func markdownHeading(_ line: String) -> (depth: Int, text: String)? {
        var depth = 0
        var index = line.startIndex
        while index < line.endIndex, line[index] == "#" {
            depth += 1
            index = line.index(after: index)
        }
        guard depth > 0, index < line.endIndex else { return nil }
        guard line[index] == " " || line[index] == "\t" else { return nil }
        index = line.index(after: index)
        return (depth, String(line[index...]))
    }

    /// `-` / `*` / `+` / `1.` after the indent, then a space or tab. The marker is not kept.
    /// One tab in the indent counts as two spaces, same as the document codec. Body whitespace is trimmed.
    private static func listItem(_ line: String) -> (indent: Int, text: String)? {
        var indent = 0
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == " " {
                indent += 1
            } else if character == "\t" {
                indent += 2
            } else {
                break
            }
            index = line.index(after: index)
        }
        guard index < line.endIndex else { return nil }
        let marker = line[index]
        if marker == "-" || marker == "*" || marker == "+" {
            index = line.index(after: index)
            guard index < line.endIndex else { return nil }
            let separator = line[index]
            guard separator == " " || separator == "\t" else { return nil }
            index = line.index(after: index)
            let body = String(line[index...]).trimmingCharacters(in: .whitespaces)
            return (indent, body)
        }
        var digits = 0
        while index < line.endIndex, line[index] >= "0", line[index] <= "9" {
            digits += 1
            index = line.index(after: index)
        }
        guard digits > 0, index < line.endIndex, line[index] == "." else { return nil }
        index = line.index(after: index)
        guard index < line.endIndex else { return nil }
        let separator = line[index]
        guard separator == " " || separator == "\t" else { return nil }
        index = line.index(after: index)
        let body = String(line[index...]).trimmingCharacters(in: .whitespaces)
        return (indent, body)
    }

    /// A blockquote is a note on the node just opened, including one indented to sit under a list item.
    private static func noteText(_ line: String) -> String? {
        var index = line.startIndex
        while index < line.endIndex, line[index] == " " || line[index] == "\t" {
            index = line.index(after: index)
        }
        guard index < line.endIndex, line[index] == ">" else { return nil }
        index = line.index(after: index)
        if index < line.endIndex, line[index] == " " || line[index] == "\t" {
            index = line.index(after: index)
        }
        return String(line[index...])
    }

    private static func parseHeadingText(_ raw: String) -> (text: String, link: String?) {
        guard raw.first == "[" else { return (raw, nil) }
        var label = ""
        var index = raw.index(after: raw.startIndex)
        var escaped = false
        while index < raw.endIndex {
            let character = raw[index]
            if escaped {
                label.append(character)
                escaped = false
                index = raw.index(after: index)
                continue
            }
            if character == "\\" {
                escaped = true
                index = raw.index(after: index)
                continue
            }
            if character == "]" {
                let after = raw.index(after: index)
                guard after < raw.endIndex, raw[after] == "(", raw.last == ")" else {
                    return (raw, nil)
                }
                let urlStart = raw.index(after: after)
                let urlEnd = raw.index(before: raw.endIndex)
                guard urlStart <= urlEnd else { return (raw, nil) }
                let url = String(raw[urlStart..<urlEnd])
                    .replacingOccurrences(of: "%20", with: " ")
                    .replacingOccurrences(of: "%29", with: ")")
                return (label, url.isEmpty ? nil : url)
            }
            label.append(character)
            index = raw.index(after: index)
        }
        return (raw, nil)
    }

    private static func snippet(_ line: String) -> String {
        if line.count <= 80 { return line }
        return String(line.prefix(80))
    }
}
