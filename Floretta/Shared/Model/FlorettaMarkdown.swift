import Foundation

/// Markdown export of a mind map. Headings follow outline depth.
/// Notes are blockquotes. Links use `[text](url)`. Import is not this batch.
enum FlorettaMarkdown {
    static func export(_ document: MindMapDocument) -> String {
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
}
