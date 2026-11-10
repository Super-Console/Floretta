import Foundation

/// A 0-based path into `MindMapDocument.roots`.
///
/// `root` is the forest. `root/3/1` is the 2nd child of the 4th root.
/// Indexes match sibling order. They are not stable across insert, delete, or move.
/// This is the public address for a Markdown document. It is not a UUID alias.
public struct FlorettaNodePath: Equatable, Sendable, CustomStringConvertible {
    public var indexes: [Int]

    public init(indexes: [Int]) {
        self.indexes = indexes
    }

    public var isForest: Bool { indexes.isEmpty }

    public var description: String {
        if indexes.isEmpty { return "root" }
        return "root/" + indexes.map(String.init).joined(separator: "/")
    }

    /// `root` or `root/<i>/<j>/...`. Each index is a decimal integer without a sign or leading zero.
    public static func parse(_ raw: String) -> FlorettaNodePath? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = text.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let head = parts.first, head == "root" else { return nil }
        if parts.count == 1 { return FlorettaNodePath(indexes: []) }
        var indexes: [Int] = []
        for part in parts.dropFirst() {
            guard let value = Int(part), value >= 0, String(value) == part else { return nil }
            indexes.append(value)
        }
        return FlorettaNodePath(indexes: indexes)
    }
}

public extension MindMapDocument {
    /// Path of a topic in `roots`. Free nodes, stickies, and other sheets are not on this path.
    public func nodePath(of id: UUID) -> FlorettaNodePath? {
        struct Frame {
            var nodes: [MindMapNode]
            var index: Int
            var prefix: [Int]
        }
        var stack = [Frame(nodes: roots, index: 0, prefix: [])]
        while !stack.isEmpty {
            if stack[stack.count - 1].index >= stack[stack.count - 1].nodes.count {
                stack.removeLast()
                continue
            }
            let index = stack[stack.count - 1].index
            let node = stack[stack.count - 1].nodes[index]
            let path = stack[stack.count - 1].prefix + [index]
            stack[stack.count - 1].index += 1
            if node.id == id {
                return FlorettaNodePath(indexes: path)
            }
            if !node.children.isEmpty {
                stack.append(Frame(nodes: node.children, index: 0, prefix: path))
            }
        }
        return nil
    }

    /// The topic at `path`. `root` itself is the forest and throws.
    public func node(at path: FlorettaNodePath) throws -> MindMapNode {
        if path.isForest {
            throw FlorettaAIError.message("root 是 document.roots 整片森林，不是一个节点。")
        }
        var nodes = roots
        var found: MindMapNode?
        for index in path.indexes {
            guard nodes.indices.contains(index) else {
                throw FlorettaAIError.message(
                    "路径 \(path.description) 不存在。插入、删除或移动之后兄弟下标会变，请按当前树重算，不要沿用旧路径。"
                )
            }
            found = nodes[index]
            nodes = nodes[index].children
        }
        guard let found else {
            throw FlorettaAIError.message("路径 \(path.description) 不存在。")
        }
        return found
    }
}
