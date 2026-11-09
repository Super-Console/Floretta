import Foundation

/// Optional 「导出为…」preset. Heading depth (`#`, `##`, `###`) follows outline depth.
/// Notes are blockquotes. Links use `[text](url)`.
/// Import reads this same heading shape. Any other non-empty line is an error.
///
/// This is not open/save for `.md` documents. That projection is
/// `FlorettaMarkdownDocumentCodec` (nested `- ` lists, H1 sections only).
public enum FlorettaMarkdownError: Error, Equatable, LocalizedError {
    case notUTF8
    case empty
    case unsupportedLine(String)

    public var errorDescription: String? {
        switch self {
        case .notUTF8:
            return "Markdown 不是 UTF-8。"
        case .empty:
            return "Markdown 里没有标题。"
        case .unsupportedLine(let line):
            return "Markdown 里有无法对应导图的一行：\(line)"
        }
    }
}

public enum FlorettaMarkdown {
    public static func export(_ document: MindMapDocument) -> String {
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
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var roots: [MindMapNode] = []
        var stack: [HeadingItem] = []

        func close(through depth: Int) {
            while let last = stack.last, last.depth >= depth {
                let done = stack.removeLast()
                if var parent = stack.popLast() {
                    parent.node.children.append(done.node)
                    stack.append(parent)
                } else {
                    roots.append(done.node)
                }
            }
        }

        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if let note = noteText(line) {
                guard var current = stack.popLast() else {
                    throw FlorettaMarkdownError.unsupportedLine(snippet(line))
                }
                if current.node.note.isEmpty {
                    current.node.note = note
                } else {
                    current.node.note += "\n" + note
                }
                stack.append(current)
                continue
            }
            guard let parsedHeading = markdownHeading(line) else {
                throw FlorettaMarkdownError.unsupportedLine(snippet(line))
            }
            close(through: parsedHeading.depth)
            let parsed = parseHeadingText(parsedHeading.text)
            let node = MindMapNode(text: parsed.text, link: parsed.link)
            stack.append(HeadingItem(depth: parsedHeading.depth, node: node))
        }
        close(through: 1)
        guard !roots.isEmpty else { throw FlorettaMarkdownError.empty }
        let title = roots.count == 1 ? roots[0].text : "Markdown"
        return MindMapDocument(title: title, roots: roots)
    }

    private struct HeadingItem {
        var depth: Int
        var node: MindMapNode
    }

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
        let text = String(line[index...])
        guard !text.isEmpty else { return nil }
        return (depth, text)
    }

    private static func noteText(_ line: String) -> String? {
        guard line.hasPrefix(">") else { return nil }
        let rest = line.dropFirst()
        if rest.hasPrefix(" ") { return String(rest.dropFirst()) }
        return String(rest)
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
