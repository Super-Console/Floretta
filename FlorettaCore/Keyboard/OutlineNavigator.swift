import Foundation

/// Visible outline order for the shared document tree.
/// Collapsed nodes stay in the list; their descendants do not.
/// Walking this list does not copy node subtrees.
public enum OutlineNavigator {
    public static func visibleIDs(in document: MindMapDocument) -> [UUID] {
        var ids: [UUID] = []
        func walk(_ nodes: [MindMapNode]) {
            for node in nodes {
                ids.append(node.id)
                if !node.isCollapsed {
                    walk(node.children)
                }
            }
        }
        walk(document.roots)
        for node in document.freeNodes {
            ids.append(node.id)
        }
        return ids
    }

    public static func destination(from id: UUID, move: SelectionMove, in document: MindMapDocument) -> UUID? {
        guard document.node(id) != nil else { return nil }
        switch move {
        case .up, .down:
            let ids = visibleIDs(in: document)
            guard let index = ids.firstIndex(of: id) else { return nil }
            let next = move == .up ? index - 1 : index + 1
            guard ids.indices.contains(next) else { return nil }
            return ids[next]
        case .left:
            return document.parentID(of: id)
        case .right:
            if document.isInFreeNodeTree(id) { return nil }
            guard let node = document.node(id), !node.isCollapsed, let first = node.children.first else {
                return nil
            }
            return first.id
        }
    }
}

public extension MindMapDocument {
    public func parentID(of id: UUID) -> UUID? {
        func walk(_ nodes: [MindMapNode], parent: UUID?) -> UUID? {
            for node in nodes {
                if node.id == id { return parent }
                if let found = walk(node.children, parent: node.id) { return found }
            }
            return nil
        }
        return walk(roots, parent: nil)
    }

    public func isDescendant(_ id: UUID, of ancestor: UUID) -> Bool {
        guard let root = node(ancestor) else { return false }
        func walk(_ node: MindMapNode) -> Bool {
            for child in node.children {
                if child.id == id || walk(child) { return true }
            }
            return false
        }
        return walk(root)
    }

    public func canReparent(_ id: UUID, to parentID: UUID?) -> Bool {
        guard node(id) != nil else { return false }
        if isInFreeNodeTree(id) { return false }
        guard let parentID else { return true }
        if isInFreeNodeTree(parentID) { return false }
        if parentID == id { return false }
        if isDescendant(parentID, of: id) { return false }
        return node(parentID) != nil
    }

    /// `onMove` within one parent. `parentID == nil` reorders roots.
    public mutating func moveChildren(of parentID: UUID?, from source: IndexSet, to destination: Int) {
        func reorder(_ children: inout [MindMapNode]) {
            guard !source.isEmpty else { return }
            let moving = source.sorted().map { children[$0] }
            for index in source.sorted(by: >) {
                children.remove(at: index)
            }
            var insertAt = destination
            for index in source where index < destination {
                insertAt -= 1
            }
            insertAt = min(max(insertAt, 0), children.count)
            children.insert(contentsOf: moving, at: insertAt)
        }
        if let parentID {
            if isInFreeNodeTree(parentID) { return }
            _ = mutateNode(parentID) { reorder(&$0.children) }
        } else {
            reorder(&roots)
        }
    }

    @discardableResult
    public mutating func reparent(_ id: UUID, to parentID: UUID?, at index: Int) -> Bool {
        guard canReparent(id, to: parentID) else { return false }
        guard let extracted = extractNode(id) else { return false }
        if let parentID {
            return mutateNode(parentID) { parent in
                let insertAt = min(max(index, 0), parent.children.count)
                parent.children.insert(extracted, at: insertAt)
                parent.isCollapsed = false
            }
        }
        let insertAt = min(max(index, 0), roots.count)
        roots.insert(extracted, at: insertAt)
        return true
    }

    private mutating func extractNode(_ id: UUID) -> MindMapNode? {
        if let index = roots.firstIndex(where: { $0.id == id }) {
            return roots.remove(at: index)
        }
        func walk(_ nodes: inout [MindMapNode]) -> MindMapNode? {
            for index in nodes.indices {
                if let childIndex = nodes[index].children.firstIndex(where: { $0.id == id }) {
                    return nodes[index].children.remove(at: childIndex)
                }
                if let found = walk(&nodes[index].children) {
                    return found
                }
            }
            return nil
        }
        return walk(&roots)
    }
}
