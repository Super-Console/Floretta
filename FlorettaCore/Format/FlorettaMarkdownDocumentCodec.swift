import Foundation

/// Failure while opening a `.md` document. Heading and structure errors name the 1-based line.
public enum FlorettaMarkdownDocumentError: Error, Equatable, Sendable {
    case notUTF8
    case unclosedFrontMatter(line: Int)
    case illegalHeading(line: Int, level: Int)
    case unrecognizedLine(line: Int, content: String)
    case oddIndent(line: Int)
    case indentJump(line: Int)
    case orphanBlockquote(line: Int)
    case tooDeep(line: Int)
    case tooManyNodes
    case unclosedHTMLComment(line: Int)
}

extension FlorettaMarkdownDocumentError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notUTF8:
            return "Markdown 不是 UTF-8。"
        case .unclosedFrontMatter(let line):
            return "第 \(line) 行：YAML front-matter 没有结束的 ---。"
        case .illegalHeading(let line, let level):
            return "第 \(line) 行：列表外的 \(level) 级标题不能打开。Markdown 文档只允许一级分区（# ）。"
        case .unrecognizedLine(let line, let content):
            return "第 \(line) 行：无法识别为列表、一级标题或备注：\(content)"
        case .oddIndent(let line):
            return "第 \(line) 行：列表缩进不是 2 个空格的整数倍。"
        case .indentJump(let line):
            return "第 \(line) 行：列表缩进跳级，无法确定父节点。"
        case .orphanBlockquote(let line):
            return "第 \(line) 行：引用没有可附着的节点。"
        case .tooDeep(let line):
            return "第 \(line) 行：嵌套超过 \(FlorettaMarkdownDocumentCodec.maxDepth) 层。"
        case .tooManyNodes:
            return "节点超过 \(FlorettaMarkdownDocumentCodec.maxNodes) 个。"
        case .unclosedHTMLComment(let line):
            return "第 \(line) 行：HTML 注释没有结束。"
        }
    }
}

/// Non-blocking notice from normalizing markers or tabs. Open still succeeds.
public enum FlorettaMarkdownDocumentWarning: Equatable, Sendable {
    /// `*`, `+`, or an ordered marker was read as an unordered node.
    case normalizedListMarker
    /// A tab in list indent or the marker separator was read as two spaces.
    case normalizedTabIndent

    public var message: String {
        switch self {
        case .normalizedListMarker:
            return "已将 *、+ 或有序列表标记规范为无序列表（- ）。"
        case .normalizedTabIndent:
            return "已将 Tab 缩进按 1 个 Tab = 2 个空格规范化。"
        }
    }
}

/// A Markdown document opened into `MindMapDocument`, plus at most one warning of each kind.
public struct FlorettaMarkdownOpenResult: Equatable, Sendable {
    public var document: MindMapDocument
    public var warnings: [FlorettaMarkdownDocumentWarning]

    public init(document: MindMapDocument, warnings: [FlorettaMarkdownDocumentWarning]) {
        self.document = document
        self.warnings = warnings
    }
}

/// Open and save `.md` as a first-class projection of `MindMapDocument`.
///
/// Nested lists are the hierarchy (read `-` / `*` / `+` / `1.`; write only `- ` and 2-space indent).
/// A column-0 `# ` heading is a section root (`isMarkdownSectionHeading`). `##`–`######` outside
/// lists fail the open and include the line number. YAML front matter is stored verbatim on
/// `markdownFrontMatter` and written back unchanged aside from newline normalization.
///
/// A blockquote binds to the node just opened, including a section root, so `note` round-trips.
/// HTML comments are dropped and are not written back. UUID, color, attachment, relationship,
/// position, side, and collapse are not serialized.
///
/// This is not `FlorettaMarkdown`, the optional heading-depth 「导出为…」preset.
public enum FlorettaMarkdownDocumentCodec {
    public static let maxDepth = 512
    public static let maxNodes = 100_000

    public static func open(_ data: Data) throws -> FlorettaMarkdownOpenResult {
        guard let text = String(data: data, encoding: .utf8) else {
            throw FlorettaMarkdownDocumentError.notUTF8
        }
        return try open(text)
    }

    public static func open(_ text: String) throws -> FlorettaMarkdownOpenResult {
        try MarkdownDocumentParser(text: text).parse()
    }

    /// Canonical Markdown projection. Fields the format cannot express are omitted.
    public static func save(_ document: MindMapDocument) -> String {
        let document = document.singleTreeExport()
        var lines: [String] = []
        if let frontMatter = canonicalFrontMatter(document.markdownFrontMatter) {
            lines.append(frontMatter)
            lines.append("")
        }
        for root in document.roots {
            if root.isMarkdownSectionHeading {
                lines.append("# \(inline(root))")
                appendNote(root.note, to: &lines)
                for child in root.children {
                    appendList(child, level: 0, to: &lines)
                }
            } else {
                appendList(root, level: 0, to: &lines)
            }
        }
        guard !lines.isEmpty else { return "" }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func canonicalFrontMatter(_ raw: String?) -> String? {
        guard var text = raw else { return nil }
        text = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        while text.hasSuffix("\n") {
            text.removeLast()
        }
        return text.isEmpty ? nil : text
    }

    private static func appendList(_ node: MindMapNode, level: Int, to lines: inout [String]) {
        let indent = String(repeating: " ", count: level * 2)
        lines.append("\(indent)- \(inline(node))")
        appendNote(node.note, to: &lines)
        for child in node.children {
            appendList(child, level: level + 1, to: &lines)
        }
    }

    private static func appendNote(_ note: String, to lines: inout [String]) {
        if note.isEmpty { return }
        let normalized = note
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        for piece in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            lines.append("> \(piece)")
        }
    }

    private static func inline(_ node: MindMapNode) -> String {
        let text = flattenNewlines(node.text)
        guard let link = node.link?.trimmingCharacters(in: .whitespacesAndNewlines), !link.isEmpty else {
            return text
        }
        let label = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
        let url = link
            .replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: ")", with: "%29")
        return "[\(label)](\(url))"
    }

    private static func flattenNewlines(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

private struct MarkdownDocumentParser {
    private struct Frame {
        var level: Int
        var node: MindMapNode
    }

    private struct Prefix {
        var spaces: Int
        var sawTab: Bool
        var content: String
    }

    private struct ListItem {
        var body: String
        var normalized: Bool
        var sawSeparatorTab: Bool
    }

    private let text: String
    private var lines: [String] = []
    private var frontMatter: String?
    private var stack: [Frame] = []
    private var roots: [MindMapNode] = []
    private var nodeCount = 0
    private var sawMarkerNorm = false
    private var sawTab = false

    init(text: String) {
        self.text = text
    }

    func parse() throws -> FlorettaMarkdownOpenResult {
        var parser = self
        return try parser.parseMutating()
    }

    private mutating func parseMutating() throws -> FlorettaMarkdownOpenResult {
        let bodyStart = try prepare()
        var inComment = false
        var commentStart = 1
        var index = bodyStart
        while index < lines.count {
            let number = index + 1
            let raw = lines[index]
            index += 1
            let visible = stripComments(raw, inComment: &inComment, commentStart: &commentStart, number: number)
            if visible.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            try consume(visible, number: number)
        }
        if inComment {
            throw FlorettaMarkdownDocumentError.unclosedHTMLComment(line: commentStart)
        }
        flush(through: Int.min)
        let title: String
        switch roots.count {
        case 0:
            title = ""
        case 1:
            title = roots[0].text
        default:
            title = "Markdown"
        }
        var warnings: [FlorettaMarkdownDocumentWarning] = []
        if sawMarkerNorm { warnings.append(.normalizedListMarker) }
        if sawTab { warnings.append(.normalizedTabIndent) }
        let document = MindMapDocument(
            title: title,
            roots: roots,
            markdownFrontMatter: frontMatter
        )
        return FlorettaMarkdownOpenResult(document: document, warnings: warnings)
    }

    private mutating func prepare() throws -> Int {
        var normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if normalized.hasPrefix("\u{feff}") {
            normalized.removeFirst()
        }
        if normalized.isEmpty {
            lines = []
            return 0
        }
        lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first, isFrontMatterFence(first) else { return 0 }
        var end = 1
        while end < lines.count {
            if isFrontMatterFence(lines[end]) {
                frontMatter = lines[0...end].joined(separator: "\n")
                return end + 1
            }
            end += 1
        }
        throw FlorettaMarkdownDocumentError.unclosedFrontMatter(line: 1)
    }

    private func isFrontMatterFence(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == "---"
    }

    private func stripComments(
        _ line: String,
        inComment: inout Bool,
        commentStart: inout Int,
        number: Int
    ) -> String {
        var output = ""
        var rest = Substring(line)
        while true {
            if inComment {
                guard let range = rest.range(of: "-->") else { return output }
                rest = rest[range.upperBound...]
                inComment = false
                continue
            }
            guard let range = rest.range(of: "<!--") else {
                output.append(contentsOf: rest)
                return output
            }
            output.append(contentsOf: rest[..<range.lowerBound])
            rest = rest[range.upperBound...]
            commentStart = number
            inComment = true
        }
    }

    private mutating func consume(_ line: String, number: Int) throws {
        let prefix = structuralPrefix(line)
        if prefix.sawTab { sawTab = true }
        let content = prefix.content
        if content.hasPrefix(">") {
            try appendNote(noteText(from: content), line: number)
            return
        }
        if let heading = atxHeading(content) {
            try consumeHeading(heading, prefix: prefix, line: number)
            return
        }
        if let item = listItem(content) {
            if item.sawSeparatorTab { sawTab = true }
            if item.normalized { sawMarkerNorm = true }
            if prefix.spaces % 2 != 0 {
                throw FlorettaMarkdownDocumentError.oddIndent(line: number)
            }
            let linked = singleLink(in: item.body)
            try addList(
                level: prefix.spaces / 2,
                text: linked?.text ?? item.body,
                link: linked?.link,
                line: number
            )
            return
        }
        throw FlorettaMarkdownDocumentError.unrecognizedLine(line: number, content: snippet(content))
    }

    private func structuralPrefix(_ line: String) -> Prefix {
        var spaces = 0
        var sawTabInPrefix = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == " " {
                spaces += 1
            } else if character == "\t" {
                spaces += 2
                sawTabInPrefix = true
            } else {
                break
            }
            index = line.index(after: index)
        }
        return Prefix(spaces: spaces, sawTab: sawTabInPrefix, content: String(line[index...]))
    }

    private struct ATX {
        var level: Int
        var rest: String
    }

    /// `nil` when the line is not an ATX heading of 1...6 hashes (`#######` is not ATX).
    private func atxHeading(_ content: String) -> ATX? {
        var level = 0
        var index = content.startIndex
        while index < content.endIndex, content[index] == "#", level < 6 {
            level += 1
            index = content.index(after: index)
        }
        guard level > 0 else { return nil }
        if index < content.endIndex, content[index] == "#" { return nil }
        return ATX(level: level, rest: String(content[index...]))
    }

    private mutating func consumeHeading(_ heading: ATX, prefix: Prefix, line: Int) throws {
        if (2...6).contains(heading.level) {
            throw FlorettaMarkdownDocumentError.illegalHeading(line: line, level: heading.level)
        }
        let content = prefix.content
        if prefix.spaces != 0 || prefix.sawTab {
            throw FlorettaMarkdownDocumentError.unrecognizedLine(line: line, content: snippet(content))
        }
        guard let first = heading.rest.first, first == " " || first == "\t" else {
            throw FlorettaMarkdownDocumentError.unrecognizedLine(line: line, content: snippet(content))
        }
        if first == "\t" { sawTab = true }
        let text = String(heading.rest.dropFirst()).trimmingCharacters(in: .whitespaces)
        let linked = singleLink(in: text)
        try startSection(text: linked?.text ?? text, link: linked?.link)
    }

    private func listItem(_ content: String) -> ListItem? {
        guard let first = content.first else { return nil }
        if first == "-" || first == "*" || first == "+" {
            let markerEnd = content.index(after: content.startIndex)
            guard markerEnd < content.endIndex else { return nil }
            let separator = content[markerEnd]
            guard separator == " " || separator == "\t" else { return nil }
            let bodyStart = content.index(after: markerEnd)
            let body = String(content[bodyStart...]).trimmingCharacters(in: .whitespaces)
            return ListItem(body: body, normalized: first != "-", sawSeparatorTab: separator == "\t")
        }
        var index = content.startIndex
        var digits = 0
        while index < content.endIndex {
            let character = content[index]
            guard character >= "0", character <= "9" else { break }
            digits += 1
            index = content.index(after: index)
        }
        guard digits > 0, index < content.endIndex, content[index] == "." else { return nil }
        index = content.index(after: index)
        guard index < content.endIndex else { return nil }
        let separator = content[index]
        guard separator == " " || separator == "\t" else { return nil }
        index = content.index(after: index)
        let body = String(content[index...]).trimmingCharacters(in: .whitespaces)
        return ListItem(body: body, normalized: true, sawSeparatorTab: separator == "\t")
    }

    private func noteText(from content: String) -> String {
        var rest = content.dropFirst()
        if rest.first == " " || rest.first == "\t" {
            rest = rest.dropFirst()
        }
        return String(rest)
    }

    private func singleLink(in raw: String) -> (text: String, link: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 4, trimmed.first == "[", trimmed.last == ")" else { return nil }
        var label = ""
        var index = trimmed.index(after: trimmed.startIndex)
        var escaped = false
        while index < trimmed.endIndex {
            let character = trimmed[index]
            if escaped {
                label.append(character)
                escaped = false
                index = trimmed.index(after: index)
                continue
            }
            if character == "\\" {
                escaped = true
                index = trimmed.index(after: index)
                continue
            }
            if character == "]" {
                index = trimmed.index(after: index)
                guard index < trimmed.endIndex, trimmed[index] == "(" else { return nil }
                index = trimmed.index(after: index)
                guard let close = trimmed[index...].firstIndex(of: ")") else { return nil }
                guard trimmed.index(after: close) == trimmed.endIndex else { return nil }
                let url = String(trimmed[index..<close])
                    .replacingOccurrences(of: "%20", with: " ")
                    .replacingOccurrences(of: "%29", with: ")")
                guard !url.isEmpty else { return nil }
                return (label, url)
            }
            label.append(character)
            index = trimmed.index(after: index)
        }
        return nil
    }

    private mutating func appendNote(_ piece: String, line: Int) throws {
        guard !stack.isEmpty else {
            throw FlorettaMarkdownDocumentError.orphanBlockquote(line: line)
        }
        if stack[stack.count - 1].node.note.isEmpty {
            stack[stack.count - 1].node.note = piece
        } else {
            stack[stack.count - 1].node.note += "\n" + piece
        }
    }

    private mutating func startSection(text: String, link: String?) throws {
        flush(through: Int.min)
        let node = try makeNode(text: text, link: link, section: true)
        stack.append(Frame(level: -1, node: node))
    }

    private mutating func addList(level: Int, text: String, link: String?, line: Int) throws {
        if level > FlorettaMarkdownDocumentCodec.maxDepth {
            throw FlorettaMarkdownDocumentError.tooDeep(line: line)
        }
        flush(through: level)
        if let parent = stack.last {
            guard level == parent.level + 1 else {
                throw FlorettaMarkdownDocumentError.indentJump(line: line)
            }
        } else if level != 0 {
            throw FlorettaMarkdownDocumentError.indentJump(line: line)
        }
        let node = try makeNode(text: text, link: link, section: false)
        stack.append(Frame(level: level, node: node))
    }

    private mutating func makeNode(text: String, link: String?, section: Bool) throws -> MindMapNode {
        nodeCount += 1
        if nodeCount > FlorettaMarkdownDocumentCodec.maxNodes {
            throw FlorettaMarkdownDocumentError.tooManyNodes
        }
        return MindMapNode(text: text, link: link, isMarkdownSectionHeading: section)
    }

    private mutating func flush(through level: Int) {
        while let last = stack.last, last.level >= level {
            stack.removeLast()
            if stack.isEmpty {
                roots.append(last.node)
            } else {
                stack[stack.count - 1].node.children.append(last.node)
            }
        }
    }

    private func snippet(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.count <= 80 { return trimmed }
        return String(trimmed.prefix(80))
    }
}
