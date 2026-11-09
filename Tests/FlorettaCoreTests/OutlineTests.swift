import FlorettaCore
import XCTest

final class OutlineTests: XCTestCase {
    func testRenameUpdatesTheSharedNodeText() {
        let rootID = UUID()
        var document = MindMapDocument(title: "sync", roots: [MindMapNode(id: rootID, text: "旧")])
        var session = MindMapKeyboardSession()
        session.selectedNodeID = rootID
        session.apply(.beginEdit, document: &document, frames: [])
        session.replaceEditingText("新名字", document: &document)
        XCTAssertEqual(document.node(rootID)?.text, "新名字")
        XCTAssertEqual(OutlineNavigator.visibleIDs(in: document), [rootID])
        XCTAssertEqual(session.selectedNodeID, rootID)
    }

    func testCanvasAddAppearsInTheOutline() {
        let rootID = UUID()
        var document = MindMapDocument(title: "add", roots: [MindMapNode(id: rootID, text: "根")])
        var session = MindMapKeyboardSession()
        session.selectedNodeID = rootID
        let command = session.handle(
            KeyEvent(key: .tab, modifiers: [], mode: .command, isComposing: false),
            document: &document,
            frames: [],
            surface: .outline
        )
        XCTAssertEqual(command, .createChild)
        let childID = document.roots[0].children[0].id
        XCTAssertEqual(session.selectedNodeID, childID)
        XCTAssertEqual(OutlineNavigator.visibleIDs(in: document), [rootID, childID])
    }

    func testReorderKeepsParentAndLayoutFollowsOrder() {
        let rootID = UUID()
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let root = MindMapNode(
            id: rootID,
            text: "根",
            children: [
                MindMapNode(id: first, text: "甲"),
                MindMapNode(id: second, text: "乙"),
                MindMapNode(id: third, text: "丙"),
            ]
        )
        var document = MindMapDocument(title: "order", roots: [root])
        var session = MindMapKeyboardSession()
        session.reorderChildren(of: rootID, from: IndexSet(integer: 2), to: 0, document: &document)
        XCTAssertEqual(document.roots[0].children.map(\.id), [third, first, second])
        XCTAssertEqual(document.parentID(of: third), rootID)
        let frames = LayoutEngine().layout(document)
        let rootFrame = frames.first { $0.id == rootID }!
        let moved = frames.first { $0.id == third }!
        XCTAssertGreaterThan(moved.frame.minX, rootFrame.frame.maxX)
        session.apply(.undo, document: &document, frames: [])
        XCTAssertEqual(document.roots[0].children.map(\.id), [first, second, third])
    }

    func testReparentMovesTheEdgeAndRejectsDescendants() {
        let rootID = UUID()
        let left = UUID()
        let right = UUID()
        let grand = UUID()
        let root = MindMapNode(
            id: rootID,
            text: "根",
            children: [
                MindMapNode(id: left, text: "左", children: [MindMapNode(id: grand, text: "孙")]),
                MindMapNode(id: right, text: "右"),
            ]
        )
        var document = MindMapDocument(title: "move", roots: [root])
        var session = MindMapKeyboardSession()
        XCTAssertTrue(session.reparentNode(grand, to: right, at: 0, document: &document))
        XCTAssertEqual(document.parentID(of: grand), right)
        XCTAssertTrue(document.node(left)?.children.isEmpty == true)
        XCTAssertEqual(document.node(right)?.children.map(\.id), [grand])
        XCTAssertFalse(document.isCollapsed(right))
        XCTAssertFalse(session.reparentNode(rootID, to: grand, at: 0, document: &document))
        XCTAssertEqual(document.parentID(of: grand), right)
    }

    func testOutlineArrowsMoveSelectionWithoutReordering() {
        let rootID = UUID()
        let first = UUID()
        let grand = UUID()
        let second = UUID()
        let root = MindMapNode(
            id: rootID,
            text: "根",
            children: [
                MindMapNode(id: first, text: "甲", children: [MindMapNode(id: grand, text: "孙")]),
                MindMapNode(id: second, text: "乙"),
            ]
        )
        var document = MindMapDocument(title: "keys", roots: [root])
        var session = MindMapKeyboardSession()
        session.selectedNodeID = rootID
        XCTAssertEqual(move(.down, session: &session, document: &document), first)
        XCTAssertEqual(move(.right, session: &session, document: &document), grand)
        XCTAssertEqual(move(.down, session: &session, document: &document), second)
        XCTAssertEqual(move(.left, session: &session, document: &document), rootID)
        XCTAssertEqual(document.roots[0].children.map(\.id), [first, second])

        session.selectedNodeID = first
        session.setCollapsed(true, nodeID: first, document: &document)
        XCTAssertEqual(OutlineNavigator.visibleIDs(in: document), [rootID, first, second])
        XCTAssertNil(OutlineNavigator.destination(from: first, move: .right, in: document))
        XCTAssertEqual(move(.down, session: &session, document: &document), second)
    }

    func testComposingSuppressesOutlineShortcuts() {
        let rootID = UUID()
        var document = MindMapDocument(title: "ime", roots: [MindMapNode(id: rootID, text: "根")])
        var session = MindMapKeyboardSession()
        session.selectedNodeID = rootID
        session.mode = .edit
        session.isComposing = true
        let event = KeyEvent(key: .tab, modifiers: [], mode: .edit, isComposing: true)
        XCTAssertNil(KeyboardCommandMapper.map(event))
        XCTAssertNil(session.handle(event, document: &document, frames: [], surface: .outline))
        XCTAssertTrue(document.roots[0].children.isEmpty)
        XCTAssertEqual(session.selectedNodeID, rootID)
    }

    func testCollapseHidesDescendantsAndKeepsTheRest() {
        var branches: [MindMapNode] = []
        for index in 0..<39 {
            let grandchildren = (0..<25).map { MindMapNode(text: "叶\(index)-\($0)") }
            branches.append(MindMapNode(text: "支\(index)", children: grandchildren))
        }
        let root = MindMapNode(text: "根", children: branches)
        var document = MindMapDocument(title: "fold", roots: [root])
        let total = 1 + 39 + 39 * 25
        XCTAssertEqual(OutlineNavigator.visibleIDs(in: document).count, total)
        let firstBranch = document.roots[0].children[0].id
        let siblingGrandcount = document.roots[0].children[1].children.count
        var session = MindMapKeyboardSession()
        session.setCollapsed(true, nodeID: firstBranch, document: &document)
        XCTAssertEqual(document.node(firstBranch)?.children.count, 25)
        XCTAssertEqual(document.roots[0].children[1].children.count, siblingGrandcount)
        XCTAssertEqual(OutlineNavigator.visibleIDs(in: document).count, total - 25)
        XCTAssertFalse(OutlineNavigator.visibleIDs(in: document).contains(document.node(firstBranch)!.children[0].id))
    }

    private func move(
        _ direction: SelectionMove,
        session: inout MindMapKeyboardSession,
        document: inout MindMapDocument
    ) -> UUID? {
        let event = KeyEvent(key: token(direction), modifiers: [], mode: .command, isComposing: false)
        _ = session.handle(event, document: &document, frames: [], surface: .outline)
        return session.selectedNodeID
    }

    private func token(_ move: SelectionMove) -> KeyToken {
        switch move {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        }
    }
}

private extension MindMapDocument {
    func isCollapsed(_ id: UUID) -> Bool {
        node(id)?.isCollapsed ?? true
    }
}
