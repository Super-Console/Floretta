import FlorettaCore
import XCTest

final class KeyboardTests: XCTestCase {
    func testBranchThemeIsOneUndoStepAndLeavesNodeStyle() {
        var session = MindMapKeyboardSession()
        let styled = MindMapNode(
            text: "根",
            style: MindMapNodeStyle(colorHex: "#112233", fillHex: "#112233"),
            children: [MindMapNode(text: "甲"), MindMapNode(text: "乙")]
        )
        var document = MindMapDocument(title: "色", roots: [styled])
        session.mode = .edit
        XCTAssertFalse(session.setBranchTheme("grove", document: &document))
        XCTAssertNil(document.themeID)
        session.mode = .command
        XCTAssertFalse(session.setBranchTheme("not-a-theme", document: &document))
        XCTAssertTrue(session.setBranchTheme("grove", document: &document))
        XCTAssertEqual(document.themeID, "grove")
        XCTAssertEqual(document.roots[0].style?.fillHex, "#112233")
        XCTAssertTrue(session.setBranchTheme("grove", document: &document))
        XCTAssertTrue(session.setBranchTheme("ink", document: &document))
        XCTAssertNil(document.themeID)
        XCTAssertEqual(press(.character("z"), .command, session: &session, document: &document), .undo)
        XCTAssertEqual(document.themeID, "grove")
        XCTAssertEqual(press(.character("z"), .command, session: &session, document: &document), .undo)
        XCTAssertNil(document.themeID)
        XCTAssertEqual(document.roots[0].style, styled.style)
    }

    func testCommandModeMapsStructureKeys() {
        XCTAssertEqual(map(.tab), .createChild)
        XCTAssertEqual(map(.enter), .createSibling)
        XCTAssertNil(map(.enter, .shift))
        XCTAssertEqual(map(.space), .beginEdit)
        XCTAssertNil(map(.escape))
        XCTAssertEqual(map(.delete), .deleteSelection)
        XCTAssertEqual(map(.backspace), .deleteSelection)
        XCTAssertEqual(map(.backspace, .command), .deleteSelection)
        XCTAssertEqual(map(.delete, .command), .deleteSelection)
        XCTAssertEqual(map(.up), .moveSelection(.up))
        XCTAssertEqual(map(.down), .moveSelection(.down))
        XCTAssertEqual(map(.left), .moveSelection(.left))
        XCTAssertEqual(map(.right), .moveSelection(.right))
        XCTAssertEqual(map(.character("z"), .command), .undo)
        XCTAssertEqual(map(.character("Z"), [.command, .shift]), .redo)
        XCTAssertNil(map(.character("z")))
        XCTAssertNil(map(.tab, .command))
        XCTAssertNil(map(.tab, .shift))
        XCTAssertNil(map(.enter, .option))
        XCTAssertNil(map(.up, .option))
        XCTAssertNil(map(.character("z"), .control))
    }

    func testEditModeDisablesCreateAndKeepsNewlineCommitAndCancel() {
        XCTAssertNil(map(.tab, mode: .edit))
        XCTAssertNil(map(.space, mode: .edit))
        XCTAssertNil(map(.delete, mode: .edit))
        XCTAssertNil(map(.backspace, mode: .edit))
        XCTAssertNil(map(.backspace, .command, mode: .edit))
        XCTAssertNil(map(.up, mode: .edit))
        XCTAssertNil(map(.down, mode: .edit))
        XCTAssertNil(map(.left, mode: .edit))
        XCTAssertNil(map(.right, mode: .edit))
        XCTAssertNil(map(.character("z"), .command, mode: .edit))
        XCTAssertNil(map(.character("z"), [.command, .shift], mode: .edit))
        XCTAssertEqual(map(.enter, mode: .edit), .commitEdit)
        XCTAssertNotEqual(map(.enter, mode: .edit), .createSibling)
        XCTAssertEqual(map(.enter, .shift, mode: .edit), .insertNewline)
        XCTAssertEqual(map(.escape, mode: .edit), .cancelEdit)
    }

    func testCompositionSuppressesEveryShortcut() {
        let keys: [(KeyToken, KeyModifiers)] = [
            (.tab, []),
            (.enter, []),
            (.enter, .shift),
            (.space, []),
            (.escape, []),
            (.delete, []),
            (.backspace, []),
            (.backspace, .command),
            (.up, []),
            (.down, []),
            (.left, []),
            (.right, []),
            (.character("z"), .command),
            (.character("z"), [.command, .shift]),
        ]
        for mode in [KeyboardMode.command, KeyboardMode.edit] {
            for (key, modifiers) in keys {
                XCTAssertNil(
                    map(key, modifiers, mode: mode, composing: true),
                    "\(mode) \(key) \(modifiers)"
                )
            }
        }
    }

    func testMarkedChineseTextDoesNotCreateOrDeleteNodes() {
        let rootID = UUID()
        var document = MindMapDocument(title: "中文", roots: [MindMapNode(id: rootID, text: "中心")])
        var session = MindMapKeyboardSession()
        session.selectedNodeID = rootID
        XCTAssertEqual(press(.space, session: &session, document: &document), .beginEdit)
        session.isComposing = true
        session.replaceEditingText("zhongwen", document: &document)
        XCTAssertNil(press(.tab, session: &session, document: &document, composing: true))
        XCTAssertNil(press(.enter, session: &session, document: &document, composing: true))
        XCTAssertNil(press(.backspace, session: &session, document: &document, composing: true))
        XCTAssertNil(press(.delete, session: &session, document: &document, composing: true))
        XCTAssertNil(press(.character("z"), .command, session: &session, document: &document, composing: true))
        XCTAssertEqual(document.roots.count, 1)
        XCTAssertEqual(document.roots[0].children.count, 0)
        XCTAssertEqual(document.roots[0].text, "zhongwen")
        XCTAssertEqual(session.mode, .edit)
        session.isComposing = false
        session.replaceEditingText("中文", document: &document)
        XCTAssertEqual(press(.enter, session: &session, document: &document), .commitEdit)
        XCTAssertEqual(document.roots[0].text, "中文")
        XCTAssertEqual(press(.character("z"), .command, session: &session, document: &document), .undo)
        XCTAssertEqual(document.roots[0].text, "中心")
    }

    func testNearestChildWinsAndCrossingBranchesUsesVerticalDistance() {
        let parent = UUID()
        let close = UUID()
        let farChild = UUID()
        let stranger = UUID()
        let frames = [
            sample(parent, parent: nil, x: 0, y: 100, w: 40, h: 20),
            sample(close, parent: parent, x: 160, y: 90, w: 40, h: 20),
            sample(farChild, parent: parent, x: 140, y: 240, w: 40, h: 20),
            sample(stranger, parent: nil, x: 70, y: 100, w: 30, h: 20),
        ]
        XCTAssertEqual(SelectionNavigator.destination(from: parent, move: .right, frames: frames), close)
        XCTAssertEqual(SelectionNavigator.destination(from: close, move: .left, frames: frames), parent)
        XCTAssertEqual(SelectionNavigator.destination(from: close, move: .down, frames: frames), farChild)
        XCTAssertEqual(SelectionNavigator.destination(from: farChild, move: .up, frames: frames), close)

        let leaf = UUID()
        let near = UUID()
        let distant = UUID()
        let crossing = [
            sample(leaf, parent: nil, x: 0, y: 100, w: 40, h: 20),
            sample(near, parent: nil, x: 220, y: 90, w: 40, h: 20),
            sample(distant, parent: nil, x: 160, y: 260, w: 40, h: 20),
        ]
        XCTAssertEqual(SelectionNavigator.destination(from: leaf, move: .right, frames: crossing), near)
    }

    func testUpDownStayOnSiblings() {
        let parent = UUID()
        let upper = UUID()
        let lower = UUID()
        let cousin = UUID()
        let other = UUID()
        let frames = [
            sample(parent, parent: nil, x: 0, y: 0, w: 40, h: 20),
            sample(other, parent: nil, x: 0, y: 80, w: 40, h: 20),
            sample(upper, parent: parent, x: 120, y: 0, w: 40, h: 20),
            sample(cousin, parent: other, x: 120, y: 40, w: 40, h: 20),
            sample(lower, parent: parent, x: 120, y: 80, w: 40, h: 20),
        ]
        XCTAssertEqual(SelectionNavigator.destination(from: lower, move: .up, frames: frames), upper)
        XCTAssertEqual(SelectionNavigator.destination(from: upper, move: .down, frames: frames), lower)
        XCTAssertNil(SelectionNavigator.destination(from: upper, move: .up, frames: frames))

        let root = UUID()
        let rightUpper = UUID()
        let rightLower = UUID()
        let leftMiddle = UUID()
        let bilateral = [
            sample(root, parent: nil, x: 100, y: 80, w: 40, h: 40),
            sample(rightUpper, parent: root, x: 200, y: 0, w: 40, h: 30),
            sample(leftMiddle, parent: root, x: 0, y: 90, w: 40, h: 20),
            sample(rightLower, parent: root, x: 200, y: 160, w: 40, h: 30),
        ]
        XCTAssertEqual(SelectionNavigator.destination(from: rightUpper, move: .down, frames: bilateral), rightLower)
        XCTAssertEqual(SelectionNavigator.destination(from: rightLower, move: .up, frames: bilateral), rightUpper)
    }

    func testLayoutArrowsMoveBetweenParentAndSide() {
        let rootID = UUID()
        let rightTop = UUID()
        let left = UUID()
        let rightBottom = UUID()
        let root = MindMapNode(
            id: rootID,
            text: "根",
            children: [
                MindMapNode(id: rightTop, text: "右上"),
                MindMapNode(id: left, text: "左"),
                MindMapNode(id: rightBottom, text: "右下"),
            ]
        )
        var document = MindMapDocument(title: "nav", roots: [root])
        let frames = LayoutEngine().layout(document)
        var session = MindMapKeyboardSession()
        session.selectedNodeID = rootID
        session.apply(.moveSelection(.left), document: &document, frames: frames)
        XCTAssertEqual(session.selectedNodeID, left)
        session.apply(.moveSelection(.right), document: &document, frames: frames)
        XCTAssertEqual(session.selectedNodeID, rootID)
        session.apply(.moveSelection(.right), document: &document, frames: frames)
        let rightIDs: Set<UUID> = [rightTop, rightBottom]
        let landed = try! XCTUnwrap(session.selectedNodeID)
        XCTAssertTrue(rightIDs.contains(landed))
        session.apply(.moveSelection(.left), document: &document, frames: frames)
        XCTAssertEqual(session.selectedNodeID, rootID)

        let landedFrame = try! XCTUnwrap(frames.first { $0.id == landed })
        let other = rightIDs.subtracting([landed]).first!
        let otherFrame = try! XCTUnwrap(frames.first { $0.id == other })
        let leftFrame = try! XCTUnwrap(frames.first { $0.id == left })
        let upperY = min(landedFrame.frame.midY, otherFrame.frame.midY)
        let lowerY = max(landedFrame.frame.midY, otherFrame.frame.midY)
        XCTAssertGreaterThan(leftFrame.frame.midY, upperY)
        XCTAssertLessThan(leftFrame.frame.midY, lowerY)
        session.selectedNodeID = landed
        let towardOther: SelectionMove = otherFrame.frame.midY > landedFrame.frame.midY ? .down : .up
        session.apply(.moveSelection(towardOther), document: &document, frames: frames)
        XCTAssertEqual(session.selectedNodeID, other)
    }

    func testTabCreatesChildEntersEditAndUndoRemovesIt() {
        let rootID = UUID()
        var document = MindMapDocument(title: "tab", roots: [MindMapNode(id: rootID, text: "根", isCollapsed: true)])
        var session = MindMapKeyboardSession()
        session.selectedNodeID = rootID
        XCTAssertEqual(press(.tab, session: &session, document: &document), .createChild)
        XCTAssertEqual(session.mode, .edit)
        XCTAssertEqual(document.roots[0].children.count, 1)
        XCTAssertFalse(document.roots[0].isCollapsed)
        XCTAssertEqual(session.selectedNodeID, document.roots[0].children[0].id)
        XCTAssertEqual(session.editingText, MindMapKeyboardSession.newTopicText)
        XCTAssertNil(press(.tab, session: &session, document: &document))
        XCTAssertEqual(document.roots[0].children.count, 1)

        XCTAssertEqual(press(.escape, session: &session, document: &document), .cancelEdit)
        XCTAssertEqual(session.mode, .command)
        XCTAssertEqual(press(.character("z"), .command, session: &session, document: &document), .undo)
        XCTAssertTrue(document.roots[0].children.isEmpty)
        XCTAssertTrue(document.roots[0].isCollapsed)
        XCTAssertEqual(session.selectedNodeID, rootID)
        XCTAssertEqual(press(.character("z"), [.command, .shift], session: &session, document: &document), .redo)
        XCTAssertEqual(document.roots[0].children.count, 1)
        XCTAssertFalse(document.roots[0].isCollapsed)
    }

    func testEnterInsertsSiblingAfterCurrentAndSecondEnterDoesNotWhileEditing() {
        let rootID = UUID()
        let first = UUID()
        let second = UUID()
        let root = MindMapNode(
            id: rootID,
            text: "根",
            children: [MindMapNode(id: first, text: "甲"), MindMapNode(id: second, text: "乙")]
        )
        var document = MindMapDocument(title: "enter", roots: [root])
        var session = MindMapKeyboardSession()
        session.selectedNodeID = first
        XCTAssertEqual(press(.enter, session: &session, document: &document), .createSibling)
        XCTAssertEqual(session.mode, .edit)
        XCTAssertEqual(document.roots[0].children.map(\.id).count, 3)
        XCTAssertEqual(document.roots[0].children[0].id, first)
        XCTAssertEqual(document.roots[0].children[2].id, second)
        XCTAssertEqual(document.roots[0].children[1].id, session.selectedNodeID)
        XCTAssertEqual(press(.enter, session: &session, document: &document), .commitEdit)
        XCTAssertEqual(session.mode, .command)
        XCTAssertEqual(document.roots[0].children.count, 3)
    }

    func testShiftEnterInsertsNewlineOnlyInEditMode() {
        let rootID = UUID()
        var document = MindMapDocument(title: "nl", roots: [MindMapNode(id: rootID, text: "根")])
        var session = MindMapKeyboardSession()
        session.selectedNodeID = rootID
        XCTAssertNil(press(.enter, .shift, session: &session, document: &document))
        XCTAssertEqual(document.roots[0].text, "根")
        XCTAssertEqual(press(.space, session: &session, document: &document), .beginEdit)
        XCTAssertEqual(press(.enter, .shift, session: &session, document: &document), .insertNewline)
        XCTAssertEqual(document.roots[0].text, "根\n")
        XCTAssertEqual(session.editingText, "根\n")
        XCTAssertEqual(session.mode, .edit)
    }

    func testEscapeRestoresOriginalTextAndUndoCoversCommittedText() {
        let rootID = UUID()
        var document = MindMapDocument(title: "text", roots: [MindMapNode(id: rootID, text: "根")])
        var session = MindMapKeyboardSession()
        session.selectedNodeID = rootID
        press(.space, session: &session, document: &document)
        session.replaceEditingText("临时", document: &document)
        session.isComposing = true
        XCTAssertNil(press(.escape, session: &session, document: &document, composing: true))
        XCTAssertEqual(session.mode, .edit)
        XCTAssertEqual(document.roots[0].text, "临时")
        session.isComposing = false
        XCTAssertEqual(press(.escape, session: &session, document: &document), .cancelEdit)
        XCTAssertEqual(document.roots[0].text, "根")
        XCTAssertEqual(session.mode, .command)
        press(.character("z"), .command, session: &session, document: &document)
        XCTAssertEqual(document.roots[0].text, "根")

        press(.space, session: &session, document: &document)
        session.replaceEditingText("改定", document: &document)
        XCTAssertEqual(press(.enter, session: &session, document: &document), .commitEdit)
        XCTAssertEqual(document.roots[0].text, "改定")
        XCTAssertEqual(press(.character("z"), .command, session: &session, document: &document), .undo)
        XCTAssertEqual(document.roots[0].text, "根")
        XCTAssertEqual(press(.character("Z"), [.command, .shift], session: &session, document: &document), .redo)
        XCTAssertEqual(document.roots[0].text, "改定")
    }

    func testDeleteAndBackspaceAreUndoableAndRedoClears() {
        let rootID = UUID()
        let first = UUID()
        let second = UUID()
        let root = MindMapNode(
            id: rootID,
            text: "根",
            children: [MindMapNode(id: first, text: "甲"), MindMapNode(id: second, text: "乙")]
        )
        var document = MindMapDocument(title: "del", roots: [root])
        var session = MindMapKeyboardSession()
        session.selectedNodeID = first
        XCTAssertEqual(press(.backspace, session: &session, document: &document), .deleteSelection)
        XCTAssertEqual(document.roots[0].children.map(\.id), [second])
        XCTAssertEqual(session.selectedNodeID, second)
        XCTAssertEqual(press(.character("z"), .command, session: &session, document: &document), .undo)
        XCTAssertEqual(document.roots[0].children.map(\.id), [first, second])
        XCTAssertEqual(session.selectedNodeID, first)

        session.selectedNodeID = second
        XCTAssertEqual(press(.delete, session: &session, document: &document), .deleteSelection)
        XCTAssertEqual(document.roots[0].children.map(\.id), [first])
        press(.character("z"), .command, session: &session, document: &document)
        press(.enter, session: &session, document: &document)
        press(.escape, session: &session, document: &document)
        press(.character("z"), [.command, .shift], session: &session, document: &document)
        XCTAssertTrue(document.roots[0].children.contains { $0.id == second })
    }

    func testCollapseToggleIsUndoable() {
        let rootID = UUID()
        let child = UUID()
        var document = MindMapDocument(
            title: "fold",
            roots: [MindMapNode(id: rootID, text: "根", children: [MindMapNode(id: child, text: "子")])]
        )
        var session = MindMapKeyboardSession()
        session.selectedNodeID = rootID
        let frames = LayoutEngine().layout(document)
        session.apply(.toggleCollapse, document: &document, frames: frames)
        XCTAssertTrue(document.roots[0].isCollapsed)
        session.apply(.undo, document: &document, frames: frames)
        XCTAssertFalse(document.roots[0].isCollapsed)
        session.apply(.redo, document: &document, frames: frames)
        XCTAssertTrue(document.roots[0].isCollapsed)
        XCTAssertEqual(document.roots[0].children.first?.id, child)
    }

    private func map(
        _ key: KeyToken,
        _ modifiers: KeyModifiers = [],
        mode: KeyboardMode = .command,
        composing: Bool = false
    ) -> MindMapCommand? {
        KeyboardCommandMapper.map(
            KeyEvent(key: key, modifiers: modifiers, mode: mode, isComposing: composing)
        )
    }

    @discardableResult
    private func press(
        _ key: KeyToken,
        _ modifiers: KeyModifiers = [],
        session: inout MindMapKeyboardSession,
        document: inout MindMapDocument,
        composing: Bool? = nil
    ) -> MindMapCommand? {
        let frames = LayoutEngine().layout(document)
        let event = KeyEvent(
            key: key,
            modifiers: modifiers,
            mode: session.mode,
            isComposing: composing ?? session.isComposing
        )
        return session.handle(event, document: &document, frames: frames)
    }

    private func sample(
        _ id: UUID,
        parent: UUID?,
        x: CGFloat,
        y: CGFloat,
        w: CGFloat,
        h: CGFloat
    ) -> NodeFrame {
        NodeFrame(
            id: id,
            text: "",
            origin: CGPoint(x: x, y: y),
            size: CGSize(width: w, height: h),
            depth: parent == nil ? 0 : 1,
            fontSize: 18,
            isRoot: parent == nil,
            parentID: parent,
            fill: .white,
            border: .black,
            textColor: .black,
            cornerRadius: 8,
            link: nil
        )
    }
}
