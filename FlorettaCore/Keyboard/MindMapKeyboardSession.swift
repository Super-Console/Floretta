import Foundation

public enum EditedObject: Equatable, Sendable {
    case node
    case sticky
    case relationship
    case summary
    case boundary
    case region
}

public struct EditBuffer: Equatable, Sendable {
    public var nodeID: UUID
    public var original: String
    public var text: String
    public var object: EditedObject = .node
}

/// Applies keyboard commands and keeps one undo step per create, delete, committed text edit,
/// and collapse toggle. Typing inside an edit is not its own undo step; Escape restores the
/// text from when editing began and does not push a stack entry.
public struct MindMapKeyboardSession {
    public static let newTopicText = "新主题"

    public init() {}

    public var mode: KeyboardMode = .command
    public var isComposing = false
    public var selectedNodeID: UUID? {
        didSet {
            if selectedNodeID != nil {
                selectedStickyID = nil
                selectedRelationshipID = nil
                selectedSummaryID = nil
                selectedBoundaryID = nil
                selectedRegionID = nil
            }
        }
    }
    public var selectedStickyID: UUID? {
        didSet {
            if selectedStickyID != nil {
                selectedNodeID = nil
                selectedRelationshipID = nil
                selectedSummaryID = nil
                selectedBoundaryID = nil
                selectedRegionID = nil
            }
        }
    }
    /// The selected relationship line. Setting it clears the topic and the sticky.
    public var selectedRelationshipID: UUID? {
        didSet {
            if selectedRelationshipID != nil {
                selectedNodeID = nil
                selectedStickyID = nil
                selectedSummaryID = nil
                selectedBoundaryID = nil
                selectedRegionID = nil
            }
        }
    }
    /// The selected summary topic. Setting it clears the topic, sticky, relationship, and boundary.
    public var selectedSummaryID: UUID? {
        didSet {
            if selectedSummaryID != nil {
                selectedNodeID = nil
                selectedStickyID = nil
                selectedRelationshipID = nil
                selectedBoundaryID = nil
                selectedRegionID = nil
            }
        }
    }
    /// The selected boundary. Setting it clears the other selections.
    public var selectedBoundaryID: UUID? {
        didSet {
            if selectedBoundaryID != nil {
                selectedNodeID = nil
                selectedStickyID = nil
                selectedRelationshipID = nil
                selectedSummaryID = nil
                selectedRegionID = nil
            }
        }
    }
    /// The selected canvas region. Setting it clears the other selections.
    /// The region is not a topic, so this does not select a parent.
    public var selectedRegionID: UUID? {
        didSet {
            if selectedRegionID != nil {
                selectedNodeID = nil
                selectedStickyID = nil
                selectedRelationshipID = nil
                selectedSummaryID = nil
                selectedBoundaryID = nil
            }
        }
    }
    private(set) var edit: EditBuffer?
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var editOrigin: Snapshot?
    /// One snapshot for a drag or resize that updates the document many times.
    private var pendingChange: Snapshot?

    public var editingText: String { edit?.text ?? "" }

    /// Set while the relationship label is the text being edited.
    public var editingRelationshipID: UUID? {
        guard mode == .edit, edit?.object == .relationship else { return nil }
        return edit?.nodeID
    }

    /// Set while the summary topic text is being edited.
    public var editingSummaryID: UUID? {
        guard mode == .edit, edit?.object == .summary else { return nil }
        return edit?.nodeID
    }

    /// Set while the boundary title is being edited.
    public var editingBoundaryID: UUID? {
        guard mode == .edit, edit?.object == .boundary else { return nil }
        return edit?.nodeID
    }

    /// Set while the region label is being edited.
    public var editingRegionID: UUID? {
        guard mode == .edit, edit?.object == .region else { return nil }
        return edit?.nodeID
    }

    @discardableResult
    public mutating func handle(
        _ event: KeyEvent,
        document: inout MindMapDocument,
        frames: [NodeFrame],
        surface: KeyboardSurface = .canvas
    ) -> MindMapCommand? {
        guard let command = KeyboardCommandMapper.map(event) else { return nil }
        apply(command, document: &document, frames: frames, surface: surface)
        return command
    }

    public mutating func apply(
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

    public mutating func replaceEditingText(_ text: String, document: inout MindMapDocument) {
        guard mode == .edit, var buffer = edit, buffer.text != text else { return }
        buffer.text = text
        edit = buffer
        switch buffer.object {
        case .node:
            _ = document.mutateNode(buffer.nodeID) { $0.text = text }
        case .sticky:
            _ = document.replaceStickyText(buffer.nodeID, with: text)
        case .relationship:
            _ = document.renameRelationship(buffer.nodeID, title: text)
        case .summary:
            _ = document.renameSummary(buffer.nodeID, text: text)
        case .boundary:
            _ = document.renameBoundary(buffer.nodeID, title: text)
        case .region:
            _ = document.replaceRegionLabel(buffer.nodeID, with: text)
        }
    }

    private mutating func createChild(document: inout MindMapDocument) {
        guard mode == .command, let parentID = selectedNodeID, document.node(parentID) != nil else { return }
        guard !document.isInFreeNodeTree(parentID) else { return }
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
        guard !document.isInFreeNodeTree(id) else { return }
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
        guard mode == .command, editOrigin == nil, pendingChange == nil else { return }
        if let stickyID = selectedStickyID, selectedNodeID == nil, let sticky = document.sticky(stickyID) {
            editOrigin = capture(document)
            edit = EditBuffer(nodeID: stickyID, original: sticky.text, text: sticky.text, object: .sticky)
            mode = .edit
            return
        }
        if let relationshipID = selectedRelationshipID,
           selectedNodeID == nil,
           let relationship = document.relationship(relationshipID) {
            editOrigin = capture(document)
            edit = EditBuffer(
                nodeID: relationshipID,
                original: relationship.title,
                text: relationship.title,
                object: .relationship
            )
            mode = .edit
            return
        }
        if let summaryID = selectedSummaryID,
           selectedNodeID == nil,
           let summary = document.summary(summaryID) {
            editOrigin = capture(document)
            edit = EditBuffer(
                nodeID: summaryID,
                original: summary.text,
                text: summary.text,
                object: .summary
            )
            mode = .edit
            return
        }
        if let boundaryID = selectedBoundaryID,
           selectedNodeID == nil,
           let boundary = document.boundary(boundaryID) {
            editOrigin = capture(document)
            edit = EditBuffer(
                nodeID: boundaryID,
                original: boundary.title,
                text: boundary.title,
                object: .boundary
            )
            mode = .edit
            return
        }
        if let regionID = selectedRegionID,
           selectedNodeID == nil,
           let region = document.region(regionID) {
            editOrigin = capture(document)
            edit = EditBuffer(
                nodeID: regionID,
                original: region.label,
                text: region.label,
                object: .region
            )
            mode = .edit
            return
        }
        guard let id = selectedNodeID, let node = document.node(id) else { return }
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
        guard mode == .command else { return }
        if let stickyID = selectedStickyID, document.sticky(stickyID) != nil {
            let next = document.stickySelection(afterRemoving: stickyID)
            record(document)
            guard document.removeSticky(stickyID) else { return }
            selectedStickyID = next
            return
        }
        if let relationshipID = selectedRelationshipID {
            guard document.relationship(relationshipID) != nil else {
                selectedRelationshipID = nil
                return
            }
            let next = document.relationshipSelection(afterRemoving: relationshipID)
            record(document)
            guard document.removeRelationship(relationshipID) else {
                if !undoStack.isEmpty { undoStack.removeLast() }
                return
            }
            selectedRelationshipID = next
            return
        }
        if let summaryID = selectedSummaryID {
            guard document.summary(summaryID) != nil else {
                selectedSummaryID = nil
                return
            }
            let next = document.summarySelection(afterRemoving: summaryID)
            record(document)
            guard document.removeSummary(summaryID) else {
                if !undoStack.isEmpty { undoStack.removeLast() }
                return
            }
            selectedSummaryID = next
            return
        }
        if let boundaryID = selectedBoundaryID {
            guard document.boundary(boundaryID) != nil else {
                selectedBoundaryID = nil
                return
            }
            let next = document.boundarySelection(afterRemoving: boundaryID)
            record(document)
            guard document.removeBoundary(boundaryID) else {
                if !undoStack.isEmpty { undoStack.removeLast() }
                return
            }
            selectedBoundaryID = next
            return
        }
        if let regionID = selectedRegionID {
            guard document.region(regionID) != nil else {
                selectedRegionID = nil
                return
            }
            let next = document.regionSelection(afterRemoving: regionID)
            record(document)
            guard document.removeRegion(regionID) else {
                if !undoStack.isEmpty { undoStack.removeLast() }
                return
            }
            selectedRegionID = next
            return
        }
        guard let id = selectedNodeID, document.node(id) != nil else { return }
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

    public mutating func reorderChildren(
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
    public mutating func reparentNode(
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

    public mutating func setCollapsed(_ collapsed: Bool, nodeID: UUID, document: inout MindMapDocument) {
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
        if pendingChange != nil {
            commitStickyChange(document: document)
        }
        guard mode == .command, editOrigin == nil, let previous = undoStack.popLast() else { return }
        redoStack.append(capture(document))
        restore(previous, document: &document)
    }

    private mutating func redo(document: inout MindMapDocument) {
        if pendingChange != nil {
            commitStickyChange(document: document)
        }
        guard mode == .command, editOrigin == nil, let next = redoStack.popLast() else { return }
        undoStack.append(capture(document))
        restore(next, document: &document)
    }

    /// Places a free node and selects it. One undo step. Does not insert it into `roots`.
    @discardableResult
    public mutating func addFreeNode(
        at position: MindMapPoint,
        text: String = "自由节点",
        document: inout MindMapDocument
    ) -> UUID? {
        guard mode == .command else { return nil }
        record(document)
        let id = document.addFreeNode(text: text, at: position)
        selectedNodeID = id
        return id
    }

    /// Places a sticky and selects it. One undo step. The card is not inserted into `roots` or `freeNodes`.
    @discardableResult
    public mutating func addSticky(
        at origin: MindMapPoint,
        color: StickyColor = .yellow,
        text: String = "便签",
        width: Double = StickyLimits.defaultWidth,
        height: Double = StickyLimits.defaultHeight,
        document: inout MindMapDocument
    ) -> UUID? {
        guard mode == .command, editOrigin == nil, pendingChange == nil else { return nil }
        record(document)
        guard let id = document.addSticky(text: text, color: color, at: origin, width: width, height: height) else {
            if !undoStack.isEmpty { undoStack.removeLast() }
            return nil
        }
        selectedStickyID = id
        return id
    }

    /// One undo step for a finished move. A drag that calls `placeSticky` many times should use
    /// `beginStickyChange` / `commitStickyChange` instead, so the whole gesture is one step.
    @discardableResult
    public mutating func moveSticky(
        _ id: UUID,
        to origin: MindMapPoint,
        document: inout MindMapDocument
    ) -> Bool {
        guard mode == .command, editOrigin == nil, pendingChange == nil, document.sticky(id) != nil else { return false }
        if document.sticky(id)?.origin == origin { return true }
        record(document)
        guard document.moveSticky(id, to: origin) else {
            if !undoStack.isEmpty { undoStack.removeLast() }
            return false
        }
        selectedStickyID = id
        return true
    }

    @discardableResult
    public mutating func resizeSticky(
        _ id: UUID,
        width: Double,
        height: Double,
        document: inout MindMapDocument
    ) -> Bool {
        guard mode == .command, editOrigin == nil, pendingChange == nil, let current = document.sticky(id) else {
            return false
        }
        let clampedWidth = StickyLimits.clampWidth(width)
        let clampedHeight = StickyLimits.clampHeight(height)
        if current.width == clampedWidth, current.height == clampedHeight { return true }
        record(document)
        guard document.resizeSticky(id, width: width, height: height) else {
            if !undoStack.isEmpty { undoStack.removeLast() }
            return false
        }
        selectedStickyID = id
        return true
    }

    /// Places a region and selects it. One undo step. Nodes are not reparented.
    @discardableResult
    public mutating func addRegion(
        at origin: MindMapPoint,
        label: String = "专区",
        document: inout MindMapDocument
    ) -> UUID? {
        guard mode == .command, editOrigin == nil, pendingChange == nil else { return nil }
        record(document)
        guard let id = document.addRegion(label: label, at: origin) else {
            if !undoStack.isEmpty { undoStack.removeLast() }
            return nil
        }
        selectedRegionID = id
        return id
    }

    /// Remembers the document once, before a drag or resize updates a region on each movement.
    public mutating func beginRegionChange(document: MindMapDocument) {
        guard mode == .command, editOrigin == nil, pendingChange == nil else { return }
        pendingChange = capture(document)
    }

    /// Pushes one undo step when the gesture changed the document.
    public mutating func commitRegionChange(document: MindMapDocument) {
        guard let origin = pendingChange else { return }
        pendingChange = nil
        if origin.document != document {
            undoStack.append(origin)
            redoStack.removeAll()
        }
    }

    @discardableResult
    public mutating func setRegionLength(
        _ value: Double,
        axis: CanvasRegionAxis,
        id: UUID,
        document: inout MindMapDocument
    ) -> Bool {
        guard mode == .command, editOrigin == nil, pendingChange == nil, let current = document.region(id) else {
            return false
        }
        let next = CanvasRegionGeometry.typed(
            width: current.width,
            height: current.height,
            axis: axis,
            value: value,
            locked: current.aspectLocked
        )
        if current.width == next.width, current.height == next.height { return true }
        record(document)
        guard document.placeRegion(id, origin: current.origin, width: next.width, height: next.height) else {
            if !undoStack.isEmpty { undoStack.removeLast() }
            return false
        }
        selectedRegionID = id
        return true
    }

    @discardableResult
    public mutating func setRegionAspectLocked(
        _ locked: Bool,
        id: UUID,
        document: inout MindMapDocument
    ) -> Bool {
        guard mode == .command, editOrigin == nil, pendingChange == nil, let current = document.region(id) else {
            return false
        }
        if current.aspectLocked == locked { return true }
        record(document)
        guard document.setRegionAspectLocked(id, locked) else {
            if !undoStack.isEmpty { undoStack.removeLast() }
            return false
        }
        selectedRegionID = id
        return true
    }

    @discardableResult
    public mutating func setRegionStroke(
        _ width: Double,
        id: UUID,
        document: inout MindMapDocument
    ) -> Bool {
        guard mode == .command, editOrigin == nil, pendingChange == nil, let current = document.region(id) else {
            return false
        }
        let clamped = CanvasRegionLimits.clampStroke(width)
        if current.strokeWidth == clamped { return true }
        record(document)
        guard document.setRegionStrokeWidth(id, width) else {
            if !undoStack.isEmpty { undoStack.removeLast() }
            return false
        }
        selectedRegionID = id
        return true
    }

    /// Fits the region to node frames it already contains. One undo step.
    /// The frames are not written back onto the nodes.
    @discardableResult
    public mutating func fitRegion(
        _ id: UUID,
        frames: [NodeFrame],
        document: inout MindMapDocument
    ) -> Bool {
        guard mode == .command, editOrigin == nil, pendingChange == nil, let current = document.region(id) else {
            return false
        }
        guard let placement = CanvasRegionGeometry.fitted(current, around: frames.map(\.frame)) else { return false }
        if current.origin == placement.origin, current.width == placement.width, current.height == placement.height {
            return true
        }
        record(document)
        guard document.placeRegion(id, origin: placement.origin, width: placement.width, height: placement.height) else {
            if !undoStack.isEmpty { undoStack.removeLast() }
            return false
        }
        selectedRegionID = id
        return true
    }

    /// Turns the region into a 1:1 ellipse and locks the aspect. One undo step.
    @discardableResult
    public mutating func makeRegionCircle(_ id: UUID, document: inout MindMapDocument) -> Bool {
        guard mode == .command, editOrigin == nil, pendingChange == nil, let current = document.region(id) else {
            return false
        }
        let placement = CanvasRegionGeometry.circle(current)
        let unchanged = current.shape == .ellipse
            && current.aspectLocked
            && current.origin == placement.origin
            && current.width == placement.width
            && current.height == placement.height
        if unchanged { return true }
        record(document)
        guard document.makeRegionCircle(id) else {
            if !undoStack.isEmpty { undoStack.removeLast() }
            return false
        }
        selectedRegionID = id
        return true
    }

    /// One undo step. Stores the preset id only. Branch colors stay computed from that id.
    @discardableResult
    public mutating func setBranchTheme(_ id: String, document: inout MindMapDocument) -> Bool {
        guard mode == .command, editOrigin == nil, pendingChange == nil else { return false }
        guard MapThemeCatalog.all.contains(where: { $0.id == id }) else { return false }
        let stored = MapThemeCatalog.persistedID(id)
        if document.themeID == stored { return true }
        record(document)
        document.themeID = stored
        return true
    }

    @discardableResult
    public mutating func setStickyColor(
        _ color: StickyColor,
        id: UUID,
        document: inout MindMapDocument
    ) -> Bool {
        guard mode == .command, editOrigin == nil, pendingChange == nil, document.sticky(id) != nil else { return false }
        if document.sticky(id)?.color == color { return true }
        record(document)
        guard document.recolorSticky(id, color: color) else {
            if !undoStack.isEmpty { undoStack.removeLast() }
            return false
        }
        selectedStickyID = id
        return true
    }

    @discardableResult
    public mutating func deleteSticky(_ id: UUID, document: inout MindMapDocument) -> Bool {
        guard mode == .command, editOrigin == nil, pendingChange == nil, document.sticky(id) != nil else { return false }
        let next = document.stickySelection(afterRemoving: id)
        record(document)
        guard document.removeSticky(id) else {
            if !undoStack.isEmpty { undoStack.removeLast() }
            return false
        }
        if selectedStickyID == id {
            selectedStickyID = next
        }
        return true
    }

    /// Remembers the document once, before a drag or resize updates it on each movement.
    public mutating func beginStickyChange(document: MindMapDocument) {
        guard mode == .command, editOrigin == nil, pendingChange == nil else { return }
        pendingChange = capture(document)
    }

    /// Pushes one undo step when the gesture changed the document.
    public mutating func commitStickyChange(document: MindMapDocument) {
        guard let origin = pendingChange else { return }
        pendingChange = nil
        if origin.document != document {
            undoStack.append(origin)
            redoStack.removeAll()
        }
    }

    /// Connects the selected topic to any other topic and selects the new line.
    /// One undo step. The canvas draws `TopicRelationship`; this method does not store a second curve.
    @discardableResult
    public mutating func linkSelectedTopic(
        to targetID: UUID,
        document: inout MindMapDocument,
        title: String = ""
    ) -> UUID? {
        guard mode == .command, editOrigin == nil, pendingChange == nil else { return nil }
        guard let sourceID = selectedNodeID, document.node(sourceID) != nil else { return nil }
        record(document)
        guard let relationship = document.linkTopics(from: sourceID, to: targetID, title: title) else {
            if !undoStack.isEmpty { undoStack.removeLast() }
            return nil
        }
        selectedRelationshipID = relationship.id
        return relationship.id
    }

    /// Covers the selected topic with a summary topic and selects that summary for editing.
    /// One undo step. Roots and free nodes have no parent range, so they are refused.
    @discardableResult
    public mutating func addSummaryForSelection(document: inout MindMapDocument) -> UUID? {
        guard mode == .command, editOrigin == nil, pendingChange == nil else { return nil }
        guard let childID = selectedNodeID, document.canEnclose(childID) else { return nil }
        record(document)
        guard let summary = document.addSummary(covering: childID) else {
            if !undoStack.isEmpty { undoStack.removeLast() }
            return nil
        }
        selectedSummaryID = summary.id
        beginEdit(document: document)
        return summary.id
    }

    /// Draws a boundary around the selected topic and selects it. One undo step.
    @discardableResult
    public mutating func addBoundaryForSelection(document: inout MindMapDocument) -> UUID? {
        guard mode == .command, editOrigin == nil, pendingChange == nil else { return nil }
        guard let childID = selectedNodeID, document.canEnclose(childID) else { return nil }
        record(document)
        guard let boundary = document.addBoundary(covering: childID) else {
            if !undoStack.isEmpty { undoStack.removeLast() }
            return nil
        }
        selectedBoundaryID = boundary.id
        return boundary.id
    }

    /// Connects the selected free node to any other topic. One undo step.
    /// The free node stays selected, matching callers that delete that node next.
    @discardableResult
    public mutating func linkFreeNode(
        to targetID: UUID,
        document: inout MindMapDocument,
        title: String = ""
    ) -> Bool {
        guard mode == .command, let sourceID = selectedNodeID, document.isFreeNode(sourceID) else { return false }
        record(document)
        guard document.linkTopics(from: sourceID, to: targetID, title: title) != nil else {
            if !undoStack.isEmpty { undoStack.removeLast() }
            return false
        }
        return true
    }

    /// One undo step for a label or marker edit. A no-op does not touch the stack.
    @discardableResult
    public mutating func updateTopicTags(
        _ id: UUID,
        document: inout MindMapDocument,
        _ body: (inout MindMapNode) -> Void
    ) -> Bool {
        guard mode == .command, editOrigin == nil, pendingChange == nil else { return false }
        var copy = document
        guard copy.mutateNode(id, body) else { return false }
        if copy == document { return true }
        record(document)
        document = copy
        return true
    }

    /// Drops edit undo and redo. A snapshot rollback replaces the whole document.
    /// Those stacks cannot represent that, and undoing them would restore the
    /// pre-rollback map in memory only. The previous map stays in the sidecar.
    public mutating func discardEditHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
        edit = nil
        editOrigin = nil
        pendingChange = nil
        mode = .command
        isComposing = false
    }

    private mutating func record(_ document: MindMapDocument) {
        undoStack.append(capture(document))
        redoStack.removeAll()
    }

    private func capture(_ document: MindMapDocument) -> Snapshot {
        Snapshot(
            document: document,
            selectedNodeID: selectedNodeID,
            selectedStickyID: selectedStickyID,
            selectedRelationshipID: selectedRelationshipID,
            selectedSummaryID: selectedSummaryID,
            selectedBoundaryID: selectedBoundaryID,
            selectedRegionID: selectedRegionID,
            mode: mode,
            edit: edit,
            isComposing: isComposing
        )
    }

    private mutating func restore(_ snapshot: Snapshot, document: inout MindMapDocument) {
        document = snapshot.document
        selectedNodeID = snapshot.selectedNodeID
        selectedStickyID = snapshot.selectedStickyID
        selectedRelationshipID = snapshot.selectedRelationshipID
        selectedSummaryID = snapshot.selectedSummaryID
        selectedBoundaryID = snapshot.selectedBoundaryID
        selectedRegionID = snapshot.selectedRegionID
        mode = snapshot.mode
        edit = snapshot.edit
        isComposing = snapshot.isComposing
    }
}

private struct Snapshot: Equatable {
    var document: MindMapDocument
    var selectedNodeID: UUID?
    var selectedStickyID: UUID?
    var selectedRelationshipID: UUID?
    var selectedSummaryID: UUID?
    var selectedBoundaryID: UUID?
    var selectedRegionID: UUID?
    var mode: KeyboardMode
    var edit: EditBuffer?
    var isComposing: Bool
}

public extension MindMapDocument {
    public func node(_ id: UUID) -> MindMapNode? {
        func walk(_ nodes: [MindMapNode]) -> MindMapNode? {
            for node in nodes {
                if node.id == id { return node }
                if let found = walk(node.children) { return found }
            }
            return nil
        }
        return walk(roots) ?? walk(freeNodes)
    }

    @discardableResult
    public mutating func mutateNode(_ id: UUID, _ body: (inout MindMapNode) -> Void) -> Bool {
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
        if walk(&roots) { return true }
        return walk(&freeNodes)
    }

    @discardableResult
    public mutating func insertChild(_ child: MindMapNode, under parentID: UUID) -> Bool {
        if isInFreeNodeTree(parentID) { return false }
        return mutateNode(parentID) { parent in
            let previous = parent.children.map(\.id)
            parent.children.append(child)
            parent.realignMarks(previousChildIDs: previous)
        }
    }

    @discardableResult
    public mutating func insertSibling(_ sibling: MindMapNode, after id: UUID) -> Bool {
        if isInFreeNodeTree(id) { return false }
        if let index = roots.firstIndex(where: { $0.id == id }) {
            roots.insert(sibling, at: index + 1)
            return true
        }
        func walk(_ nodes: inout [MindMapNode]) -> Bool {
            for index in nodes.indices {
                if let childIndex = nodes[index].children.firstIndex(where: { $0.id == id }) {
                    let previous = nodes[index].children.map(\.id)
                    nodes[index].children.insert(sibling, at: childIndex + 1)
                    nodes[index].realignMarks(previousChildIDs: previous)
                    return true
                }
                if walk(&nodes[index].children) { return true }
            }
            return false
        }
        return walk(&roots)
    }

    @discardableResult
    public mutating func removeNode(_ id: UUID) -> Bool {
        let doomed = idsInSubtree(id)
        let removed: Bool
        if let index = roots.firstIndex(where: { $0.id == id }) {
            roots.remove(at: index)
            removed = true
        } else if let index = freeNodes.firstIndex(where: { $0.id == id }) {
            freeNodes.remove(at: index)
            removed = true
        } else if removeNestedTopic(id, from: &roots) {
            removed = true
        } else {
            removed = removeNestedTopic(id, from: &freeNodes)
        }
        guard removed else { return false }
        if !doomed.isEmpty {
            relationships.removeAll { doomed.contains($0.sourceID) || doomed.contains($0.targetID) }
        }
        return true
    }

    public func selectionAfterRemoving(_ id: UUID) -> UUID? {
        if let index = roots.firstIndex(where: { $0.id == id }) {
            if index + 1 < roots.count { return roots[index + 1].id }
            if index > 0 { return roots[index - 1].id }
            return freeNodes.first?.id
        }
        if let index = freeNodes.firstIndex(where: { $0.id == id }) {
            if index + 1 < freeNodes.count { return freeNodes[index + 1].id }
            if index > 0 { return freeNodes[index - 1].id }
            return roots.first?.id
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
        return walk(roots) ?? walk(freeNodes)
    }

    private func idsInSubtree(_ id: UUID) -> Set<UUID> {
        func collect(_ node: MindMapNode) -> Set<UUID>? {
            if node.id == id {
                var ids: Set<UUID> = []
                func walk(_ node: MindMapNode) {
                    ids.insert(node.id)
                    node.children.forEach(walk)
                }
                walk(node)
                return ids
            }
            for child in node.children {
                if let found = collect(child) { return found }
            }
            return nil
        }
        for node in roots + freeNodes {
            if let found = collect(node) { return found }
        }
        return []
    }
}

private func removeNestedTopic(_ id: UUID, from nodes: inout [MindMapNode]) -> Bool {
    for index in nodes.indices {
        if let childIndex = nodes[index].children.firstIndex(where: { $0.id == id }) {
            let previous = nodes[index].children.map(\.id)
            nodes[index].children.remove(at: childIndex)
            nodes[index].realignMarks(previousChildIDs: previous)
            return true
        }
        if removeNestedTopic(id, from: &nodes[index].children) { return true }
    }
    return false
}
