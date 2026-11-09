import FlorettaCore
import Foundation

struct EditBuffer: Equatable, Sendable {
    var nodeID: UUID
    var original: String
    var text: String
}

/// Applies keyboard commands and keeps one undo step per create, delete, committed text edit,
/// and collapse toggle. Typing inside an edit is not its own undo step; Escape restores the
/// text from when editing began and does not push a stack entry.
struct MindMapKeyboardSession {
    static let newTopicText = "新主题"

    var mode: KeyboardMode = .command
    var isComposing = false
    var selectedNodeID: UUID?
    private(set) var edit: EditBuffer?
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var editOrigin: Snapshot?

    var editingText: String { edit?.text ?? "" }

    @discardableResult
    mutating func handle(
        _ event: KeyEvent,
        document: inout MindMapDocument,
        frames: [NodeFrame],
        surface: KeyboardSurface = .canvas
    ) -> MindMapCommand? {
        guard let command = KeyboardCommandMapper.map(event) else { return nil }
        apply(command, document: &document, frames: frames, surface: surface)
        return command
    }

    mutating func apply(
        _ command: MindMapCommand,
        document: inout MindMapDocument,
        frames: [NodeFrame],
        surface: KeyboardSurface = .canvas
    ) {
        switch command {
        case .createChild:
            createChild(document: &document)
        case .createSibling:
            createSibling(document: &document)
        case .insertNewline:
            insertNewline(document: &document)
        case .beginEdit:
            beginEdit(document: document)
        case .commitEdit:
            commitEdit()
        case .cancelEdit:
            cancelEdit(document: &document)
        case .deleteSelection:
            deleteSelection(document: &document)
        case .moveSelection(let move):
            moveSelection(move, frames: frames, surface: surface, document: document)
        case .undo:
            undo(document: &document)
        case .redo:
            redo(document: &document)
        case .toggleCollapse:
            toggleCollapse(document: &document)
        }
    }

    mutating func replaceEditingText(_ text: String, document: inout MindMapDocument) {
        guard mode == .edit, var buffer = edit, buffer.text != text else { return }
        buffer.text = text
        edit = buffer
        _ = document.mutateNode(buffer.nodeID) { $0.text = text }
    }

    private mutating func createChild(document: inout MindMapDocument) {
        guard mode == .command, let parentID = selectedNodeID, document.node(parentID) != nil else { return }
        record(document)
        let child = MindMapNode(text: Self.newTopicText)
        guard document.insertChild(child, under: parentID) else { return }
        _ = document.mutateNode(parentID) { node in
            if node.isCollapsed { node.isCollapsed = false }
        }
        selectedNodeID = child.id
        beginEdit(document: document)
    }

    private mutating func createSibling(document: inout MindMapDocument) {
        guard mode == .command, let id = selectedNodeID, document.node(id) != nil else { return }
        record(document)
        let sibling = MindMapNode(text: Self.newTopicText)
        guard document.insertSibling(sibling, after: id) else { return }
        selectedNodeID = sibling.id
        beginEdit(document: document)
    }

    private mutating func insertNewline(document: inout MindMapDocument) {
        guard mode == .edit, let buffer = edit else { return }
        replaceEditingText(buffer.text + "\n", document: &document)
    }

    private mutating func beginEdit(document: MindMapDocument) {
        guard mode == .command, editOrigin == nil,
              let id = selectedNodeID, let node = document.node(id) else { return }
        editOrigin = capture(document)
        edit = EditBuffer(nodeID: id, original: node.text, text: node.text)
        mode = .edit
    }

    private mutating func commitEdit() {
        guard mode == .edit, let origin = editOrigin else { return }
        if edit?.text != edit?.original {
            undoStack.append(origin)
            redoStack.removeAll()
        }
        editOrigin = nil
        edit = nil
        mode = .command
        isComposing = false
    }

    private mutating func cancelEdit(document: inout MindMapDocument) {
        guard let origin = editOrigin else { return }
        restore(origin, document: &document)
        editOrigin = nil
        isComposing = false
    }

    private mutating func deleteSelection(document: inout MindMapDocument) {
        guard mode == .command, let id = selectedNodeID, document.node(id) != nil else { return }
        let next = document.selectionAfterRemoving(id)
        record(document)
        guard document.removeNode(id) else { return }
        selectedNodeID = next
    }

    private mutating func moveSelection(
        _ move: SelectionMove,
        frames: [NodeFrame],
        surface: KeyboardSurface,
        document: MindMapDocument
    ) {
        guard mode == .command, let id = selectedNodeID else { return }
        let next: UUID?
        switch surface {
        case .canvas:
            next = SelectionNavigator.destination(from: id, move: move, frames: frames)
        case .outline:
            next = OutlineNavigator.destination(from: id, move: move, in: document)
        }
        if let next {
            selectedNodeID = next
        }
    }

    mutating func reorderChildren(
        of parentID: UUID?,
        from source: IndexSet,
        to destination: Int,
        document: inout MindMapDocument
    ) {
        guard mode == .command else { return }
        record(document)
        document.moveChildren(of: parentID, from: source, to: destination)
    }

    @discardableResult
    mutating func reparentNode(
        _ id: UUID,
        to parentID: UUID?,
        at index: Int,
        document: inout MindMapDocument
    ) -> Bool {
        guard mode == .command, document.canReparent(id, to: parentID) else { return false }
        record(document)
        guard document.reparent(id, to: parentID, at: index) else {
            if !undoStack.isEmpty { undoStack.removeLast() }
            return false
        }
        selectedNodeID = id
        return true
    }

    mutating func setCollapsed(_ collapsed: Bool, nodeID: UUID, document: inout MindMapDocument) {
        guard mode == .command, let node = document.node(nodeID), node.isCollapsed != collapsed else { return }
        record(document)
        _ = document.mutateNode(nodeID) { $0.isCollapsed = collapsed }
    }

    private mutating func toggleCollapse(document: inout MindMapDocument) {
        guard mode == .command, let id = selectedNodeID, document.node(id) != nil else { return }
        record(document)
        _ = document.mutateNode(id) { $0.isCollapsed.toggle() }
    }

    private mutating func undo(document: inout MindMapDocument) {
        guard mode == .command, editOrigin == nil, let previous = undoStack.popLast() else { return }
        redoStack.append(capture(document))
        restore(previous, document: &document)
    }

    private mutating func redo(document: inout MindMapDocument) {
        guard mode == .command, editOrigin == nil, let next = redoStack.popLast() else { return }
        undoStack.append(capture(document))
        restore(next, document: &document)
    }

    private mutating func record(_ document: MindMapDocument) {
        undoStack.append(capture(document))
        redoStack.removeAll()
    }

    private func capture(_ document: MindMapDocument) -> Snapshot {
        Snapshot(
            document: document,
            selectedNodeID: selectedNodeID,
            mode: mode,
            edit: edit,
            isComposing: isComposing
        )
    }

    private mutating func restore(_ snapshot: Snapshot, document: inout MindMapDocument) {
        document = snapshot.document
        selectedNodeID = snapshot.selectedNodeID
        mode = snapshot.mode
        edit = snapshot.edit
        isComposing = snapshot.isComposing
    }
}

private struct Snapshot: Equatable {
    var document: MindMapDocument
    var selectedNodeID: UUID?
    var mode: KeyboardMode
    var edit: EditBuffer?
    var isComposing: Bool
}

extension MindMapDocument {
    func node(_ id: UUID) -> MindMapNode? {
        func walk(_ nodes: [MindMapNode]) -> MindMapNode? {
            for node in nodes {
                if node.id == id { return node }
                if let found = walk(node.children) { return found }
            }
            return nil
        }
        return walk(roots)
    }

    @discardableResult
    mutating func mutateNode(_ id: UUID, _ body: (inout MindMapNode) -> Void) -> Bool {
        func walk(_ nodes: inout [MindMapNode]) -> Bool {
            for index in nodes.indices {
                if nodes[index].id == id {
                    body(&nodes[index])
                    return true
                }
                if walk(&nodes[index].children) { return true }
            }
            return false
        }
        return walk(&roots)
    }

    @discardableResult
    mutating func insertChild(_ child: MindMapNode, under parentID: UUID) -> Bool {
        mutateNode(parentID) { $0.children.append(child) }
    }

    @discardableResult
    mutating func insertSibling(_ sibling: MindMapNode, after id: UUID) -> Bool {
        if let index = roots.firstIndex(where: { $0.id == id }) {
            roots.insert(sibling, at: index + 1)
            return true
        }
        func walk(_ nodes: inout [MindMapNode]) -> Bool {
            for index in nodes.indices {
                if let childIndex = nodes[index].children.firstIndex(where: { $0.id == id }) {
                    nodes[index].children.insert(sibling, at: childIndex + 1)
                    return true
                }
                if walk(&nodes[index].children) { return true }
            }
            return false
        }
        return walk(&roots)
    }

    @discardableResult
    mutating func removeNode(_ id: UUID) -> Bool {
        if let index = roots.firstIndex(where: { $0.id == id }) {
            roots.remove(at: index)
            return true
        }
        func walk(_ nodes: inout [MindMapNode]) -> Bool {
            for index in nodes.indices {
                if let childIndex = nodes[index].children.firstIndex(where: { $0.id == id }) {
                    nodes[index].children.remove(at: childIndex)
                    return true
                }
                if walk(&nodes[index].children) { return true }
            }
            return false
        }
        return walk(&roots)
    }

    func selectionAfterRemoving(_ id: UUID) -> UUID? {
        if let index = roots.firstIndex(where: { $0.id == id }) {
            if index + 1 < roots.count { return roots[index + 1].id }
            if index > 0 { return roots[index - 1].id }
            return nil
        }
        func walk(_ nodes: [MindMapNode]) -> UUID? {
            for node in nodes {
                if let childIndex = node.children.firstIndex(where: { $0.id == id }) {
                    if childIndex + 1 < node.children.count { return node.children[childIndex + 1].id }
                    if childIndex > 0 { return node.children[childIndex - 1].id }
                    return node.id
                }
                if let found = walk(node.children) { return found }
            }
            return nil
        }
        return walk(roots)
    }
}
