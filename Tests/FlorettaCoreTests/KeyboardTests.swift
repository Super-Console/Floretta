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

    func testEachColorPresetApplyIsOneUndoOfBranchColorBackgroundAndLineWidth() throws {
        let paintedStyle = MindMapNodeStyle(colorHex: "#112233", fillHex: "#ED0DB8", borderWidth: 4)
        for preset in MapColorPresetCatalog.all {
            var session = MindMapKeyboardSession()
            let first = MindMapNode(text: "甲")
            let grandchild = MindMapNode(text: "孙")
            let second = MindMapNode(text: "乙", children: [grandchild])
            let painted = MindMapNode(text: "丙", style: paintedStyle)
            let root = MindMapNode(text: "根", children: [first, second, painted])
            var document = MindMapDocument(title: "色", roots: [root])
            document.themeID = "grove"
            let beforeLight = LayoutEngine().layout(document, scheme: .light)
            let beforeDark = LayoutEngine().layout(document, scheme: .dark)
            let beforePaper = MapThemeCatalog.appearance(
                themeID: document.themeID,
                scheme: .dark,
                fallback: .standard
            )
            XCTAssertNil(beforePaper.canvasBackground)
            XCTAssertNil(beforePaper.linkStroke)
            let beforeFirst = try XCTUnwrap(beforeLight.first { $0.id == first.id })
            let beforeGrand = try XCTUnwrap(beforeLight.first { $0.id == grandchild.id })
            XCTAssertGreaterThan(try XCTUnwrap(beforeFirst.link).lineWidth, try XCTUnwrap(beforeGrand.link).lineWidth)

            session.mode = .edit
            XCTAssertFalse(session.setBranchTheme(preset.id, document: &document))
            XCTAssertEqual(document.themeID, "grove")
            session.mode = .command
            XCTAssertFalse(session.setBranchTheme("not-a-preset", document: &document))
            XCTAssertEqual(document.themeID, "grove")

            XCTAssertTrue(session.setBranchTheme(preset.id, document: &document))
            XCTAssertEqual(document.themeID, preset.id)
            XCTAssertEqual(document.roots[0].children[2].style, paintedStyle)
            XCTAssertTrue(session.setBranchTheme(preset.id, document: &document))

            for scheme in [MapColorScheme.light, MapColorScheme.dark] {
                let frames = LayoutEngine().layout(document, scheme: scheme)
                let appearance = MapThemeCatalog.appearance(
                    themeID: document.themeID,
                    scheme: scheme,
                    fallback: .standard
                )
                XCTAssertEqual(appearance.canvasBackground, preset.canvasBackground)
                XCTAssertEqual(appearance.linkStroke, preset.lineWidth)
                XCTAssertEqual(appearance.palette.colors, preset.branchColors)
                let firstFrame = try XCTUnwrap(frames.first { $0.id == first.id })
                let secondFrame = try XCTUnwrap(frames.first { $0.id == second.id })
                let grandFrame = try XCTUnwrap(frames.first { $0.id == grandchild.id })
                let paintedFrame = try XCTUnwrap(frames.first { $0.id == painted.id })
                XCTAssertEqual(firstFrame.fill, preset.branchColors[0])
                XCTAssertEqual(firstFrame.link?.color, firstFrame.fill)
                XCTAssertEqual(firstFrame.link?.lineWidth, preset.lineWidth)
                XCTAssertEqual(firstFrame.borderWidth, preset.lineWidth)
                XCTAssertEqual(secondFrame.fill, preset.branchColors[1])
                XCTAssertEqual(secondFrame.link?.lineWidth, preset.lineWidth)
                XCTAssertEqual(grandFrame.link?.lineWidth, preset.lineWidth)
                XCTAssertEqual(grandFrame.link?.color, secondFrame.link?.color)
                XCTAssertEqual(paintedFrame.fill, try XCTUnwrap(BranchColor(hex: "#ED0DB8")))
                XCTAssertEqual(paintedFrame.borderWidth, 4)
                XCTAssertNotEqual(firstFrame.fill, beforeFirst.fill)
                XCTAssertNotEqual(firstFrame.link?.lineWidth, beforeFirst.link?.lineWidth)
            }

            let saved = try FlorettaCodec.decode(try FlorettaCodec.encode(document))
            XCTAssertEqual(saved.themeID, preset.id)
            XCTAssertEqual(saved.formatVersion, 1)
            XCTAssertEqual(
                LayoutEngine().layout(saved, scheme: .light).first { $0.id == first.id }?.fill,
                preset.branchColors[0]
            )

            XCTAssertEqual(press(.character("z"), .command, session: &session, document: &document), .undo)
            XCTAssertEqual(document.themeID, "grove")
            XCTAssertEqual(document.roots[0].children[2].style, paintedStyle)
            XCTAssertEqual(LayoutEngine().layout(document, scheme: .light), beforeLight)
            XCTAssertEqual(LayoutEngine().layout(document, scheme: .dark), beforeDark)
            let restored = MapThemeCatalog.appearance(themeID: document.themeID, scheme: .dark, fallback: .standard)
            XCTAssertEqual(restored.canvasBackground, beforePaper.canvasBackground)
            XCTAssertEqual(restored.linkStroke, beforePaper.linkStroke)
            XCTAssertEqual(restored.palette, beforePaper.palette)
            XCTAssertEqual(press(.character("z"), .command, session: &session, document: &document), .undo)
            XCTAssertEqual(document.themeID, "grove")
            XCTAssertEqual(LayoutEngine().layout(document, scheme: .light), beforeLight)
        }
    }

    func testCommandModeMapsStructureKeys() {
        XCTAssertEqual(map(.tab), .createChild)
        XCTAssertEqual(map(.enter), .createSibling)
        XCTAssertEqual(map(.enter, .shift), .createSiblingBefore)
        XCTAssertEqual(map(.enter, .command), .createParent)
        XCTAssertEqual(map(.space), .beginEdit)
        XCTAssertEqual(map(.f2), .beginEdit)
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
        XCTAssertEqual(map(.character("y"), .command), .redo)
        XCTAssertEqual(map(.character("a"), .command), .selectAllTopics)
        XCTAssertEqual(map(.character("a"), [.command, .shift]), .selectAllSiblings)
        XCTAssertEqual(map(.character("a"), [.command, .option]), .selectAllChildren)
        XCTAssertEqual(map(.enter, .option), .openProperties)
        XCTAssertEqual(map(.character("r"), .command), .jumpToCentralTopic)
        XCTAssertEqual(map(.character("+")), .expandBranch)
        XCTAssertEqual(map(.character("-")), .collapseBranch)
        XCTAssertEqual(map(.character("*")), .expandAll)
        XCTAssertEqual(map(.character("/")), .collapseAll)
        XCTAssertEqual(map(.up, .option), .moveTopic(.up))
        XCTAssertEqual(map(.down, .option), .moveTopic(.down))
        XCTAssertEqual(map(.character("l"), [.command, .shift]), .showShortcutHelp)
        XCTAssertNil(map(.character("z")))
        XCTAssertNil(map(.tab, .command))
        XCTAssertNil(map(.tab, .shift))
        XCTAssertNil(map(.character("z"), .control))
        XCTAssertNil(map(.character("+"), .command))
        XCTAssertNil(map(.character("-"), .command))
        XCTAssertTrue(XMindShortcutCatalog.conflicts().isEmpty)
    }

    func testEditModeDisablesCreateAndMapsEnterToNewlineAndCancel() {
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
        XCTAssertEqual(map(.enter, mode: .edit), .insertNewline)
        XCTAssertNotEqual(map(.enter, mode: .edit), .createSibling)
        XCTAssertEqual(map(.enter, .shift, mode: .edit), .insertNewline)
        XCTAssertNotEqual(map(.enter, .shift, mode: .edit), .createSiblingBefore)
        XCTAssertEqual(map(.escape, mode: .edit), .cancelEdit)
        XCTAssertNil(map(.f2, mode: .edit))
        XCTAssertNil(map(.character("+"), mode: .edit))
        XCTAssertNil(map(.character("-"), mode: .edit))
        XCTAssertNil(map(.character("*"), mode: .edit))
        XCTAssertNil(map(.character("/"), mode: .edit))
        XCTAssertNil(map(.enter, .command, mode: .edit))
        XCTAssertNil(map(.enter, .option, mode: .edit))
        XCTAssertNil(map(.character("a"), [.command, .shift], mode: .edit))
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
            (.character("y"), .command),
            (.f2, []),
            (.character("+"), []),
            (.character("-"), []),
            (.character("*"), []),
            (.character("/"), []),
            (.enter, .command),
            (.enter, .option),
            (.character("a"), [.command, .shift]),
            (.character("a"), [.command, .option]),
            (.character("r"), .command),
            (.character("l"), [.command, .shift]),
            (.up, .option),
            (.down, .option),
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
        XCTAssertNil(press(.space, session: &session, document: &document, composing: true))
        XCTAssertNil(press(.tab, session: &session, document: &document, composing: true))
        XCTAssertNil(press(.enter, session: &session, document: &document, composing: true))
        XCTAssertNil(press(.character("+"), session: &session, document: &document, composing: true))
        XCTAssertNil(press(.character("-"), session: &session, document: &document, composing: true))
        XCTAssertNil(press(.character("*"), session: &session, document: &document, composing: true))
        XCTAssertNil(press(.character("/"), session: &session, document: &document, composing: true))
        XCTAssertNil(press(.backspace, session: &session, document: &document, composing: true))
        XCTAssertNil(press(.delete, session: &session, document: &document, composing: true))
        XCTAssertNil(press(.character("z"), .command, session: &session, document: &document, composing: true))
        XCTAssertEqual(document.roots.count, 1)
        XCTAssertEqual(document.roots[0].children.count, 0)
        XCTAssertEqual(document.roots[0].text, "zhongwen")
        XCTAssertEqual(session.mode, .edit)
        session.isComposing = false
        session.replaceEditingText("中文", document: &document)
        XCTAssertEqual(press(.enter, session: &session, document: &document), .insertNewline)
        XCTAssertEqual(document.roots[0].text, "中文\n")
        XCTAssertEqual(session.mode, .edit)
        session.apply(.commitEdit, document: &document, frames: [])
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

    func testEnterCreatesSiblingInCommandModeAndNewlineWhileEditing() {
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
        XCTAssertEqual(press(.enter, session: &session, document: &document), .insertNewline)
        XCTAssertEqual(session.mode, .edit)
        XCTAssertEqual(document.roots[0].children.count, 3)
        XCTAssertTrue(document.node(session.selectedNodeID!)!.text.hasSuffix("\n"))
    }

    func testEnterAndShiftEnterInsertNewlinesOnlyInEditMode() {
        let rootID = UUID()
        var document = MindMapDocument(title: "nl", roots: [MindMapNode(id: rootID, text: "根")])
        var session = MindMapKeyboardSession()
        session.selectedNodeID = rootID
        XCTAssertEqual(press(.enter, .shift, session: &session, document: &document), .createSiblingBefore)
        XCTAssertEqual(session.mode, .edit)
        session.apply(.cancelEdit, document: &document, frames: [])
        _ = document.removeNode(session.selectedNodeID ?? UUID())
        session.selectedNodeID = rootID
        session.mode = .command
        XCTAssertEqual(press(.space, session: &session, document: &document), .beginEdit)
        XCTAssertEqual(press(.enter, session: &session, document: &document), .insertNewline)
        XCTAssertEqual(document.roots[0].text, "根\n")
        XCTAssertEqual(session.editingText, "根\n")
        XCTAssertEqual(session.mode, .edit)
        XCTAssertEqual(press(.enter, .shift, session: &session, document: &document), .insertNewline)
        XCTAssertEqual(document.roots[0].text, "根\n\n")
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
        XCTAssertEqual(press(.enter, session: &session, document: &document), .insertNewline)
        XCTAssertEqual(document.roots[0].text, "改定\n")
        session.apply(.commitEdit, document: &document, frames: [])
        XCTAssertEqual(press(.character("z"), .command, session: &session, document: &document), .undo)
        XCTAssertEqual(document.roots[0].text, "根")
        XCTAssertEqual(press(.character("Z"), [.command, .shift], session: &session, document: &document), .redo)
        XCTAssertEqual(document.roots[0].text, "改定\n")
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

    func testSpaceEntersEditAndF2DoesTheSame() {
        let rootID = UUID()
        var document = MindMapDocument(title: "空格", roots: [MindMapNode(id: rootID, text: "中心")])
        var session = MindMapKeyboardSession()
        session.selectedNodeID = rootID
        XCTAssertEqual(press(.space, session: &session, document: &document), .beginEdit)
        XCTAssertEqual(session.mode, .edit)
        session.apply(.cancelEdit, document: &document, frames: [])
        XCTAssertEqual(session.mode, .command)
        XCTAssertEqual(press(.f2, session: &session, document: &document), .beginEdit)
        XCTAssertEqual(session.mode, .edit)
    }

    func testShiftEnterInsertsSiblingBeforeAndCommandEnterInsertsParent() {
        let rootID = UUID()
        let childID = UUID()
        var document = MindMapDocument(
            title: "结构",
            roots: [MindMapNode(id: rootID, text: "中心", children: [MindMapNode(id: childID, text: "甲")])]
        )
        var session = MindMapKeyboardSession()
        session.selectedNodeID = childID
        XCTAssertEqual(press(.enter, .shift, session: &session, document: &document), .createSiblingBefore)
        XCTAssertEqual(document.roots[0].children.map(\.text), [MindMapKeyboardSession.newTopicText, "甲"])
        XCTAssertEqual(session.mode, .edit)
        session.apply(.commitEdit, document: &document, frames: [])
        session.selectedNodeID = childID
        XCTAssertEqual(press(.enter, .command, session: &session, document: &document), .createParent)
        XCTAssertEqual(document.roots[0].children.count, 2)
        XCTAssertEqual(document.roots[0].children[1].text, MindMapKeyboardSession.newTopicText)
        XCTAssertEqual(document.roots[0].children[1].children.map(\.text), ["甲"])
        XCTAssertEqual(session.selectedNodeID, document.roots[0].children[1].id)
        XCTAssertEqual(session.mode, .edit)
    }

    func testSelectSiblingsChildrenAndAllTopics() {
        let rootID = UUID()
        let first = UUID()
        let second = UUID()
        let grandchild = UUID()
        var document = MindMapDocument(
            title: "选择",
            roots: [MindMapNode(
                id: rootID,
                text: "中心",
                children: [
                    MindMapNode(id: first, text: "甲", children: [MindMapNode(id: grandchild, text: "孙")]),
                    MindMapNode(id: second, text: "乙"),
                ]
            )]
        )
        var session = MindMapKeyboardSession()
        session.selectedNodeID = first
        XCTAssertEqual(press(.character("a"), [.command, .shift], session: &session, document: &document), .selectAllSiblings)
        XCTAssertEqual(session.selectedNodeIDs, [first, second])
        XCTAssertEqual(session.selectedNodeID, first)
        XCTAssertEqual(press(.character("a"), [.command, .option], session: &session, document: &document), .selectAllChildren)
        XCTAssertEqual(session.selectedNodeIDs, [grandchild])
        XCTAssertEqual(session.selectedNodeID, grandchild)
        session.selectedNodeID = first
        XCTAssertEqual(press(.character("a"), .command, session: &session, document: &document), .selectAllTopics)
        XCTAssertEqual(session.selectedNodeIDs, [rootID, first, second, grandchild])
    }

    func testJumpExpandCollapseAndMoveTopic() {
        let rootID = UUID()
        let first = UUID()
        let second = UUID()
        var document = MindMapDocument(
            title: "折叠",
            roots: [MindMapNode(
                id: rootID,
                text: "中心",
                children: [
                    MindMapNode(id: first, text: "甲", children: [MindMapNode(text: "孙")]),
                    MindMapNode(id: second, text: "乙"),
                ]
            )]
        )
        var session = MindMapKeyboardSession()
        session.selectedNodeID = first
        XCTAssertEqual(press(.character("-"), session: &session, document: &document), .collapseBranch)
        XCTAssertTrue(document.node(first)?.isCollapsed ?? false)
        XCTAssertEqual(press(.character("+"), session: &session, document: &document), .expandBranch)
        XCTAssertFalse(document.node(first)?.isCollapsed ?? true)
        XCTAssertEqual(press(.character("/"), session: &session, document: &document), .collapseAll)
        XCTAssertTrue(document.node(rootID)?.isCollapsed ?? false)
        XCTAssertTrue(document.node(first)?.isCollapsed ?? false)
        XCTAssertEqual(press(.character("*"), session: &session, document: &document), .expandAll)
        XCTAssertFalse(document.node(rootID)?.isCollapsed ?? true)
        XCTAssertFalse(document.node(first)?.isCollapsed ?? true)
        XCTAssertEqual(press(.down, .option, session: &session, document: &document), .moveTopic(.down))
        XCTAssertEqual(document.roots[0].children.map(\.id), [second, first])
        XCTAssertEqual(press(.up, .option, session: &session, document: &document), .moveTopic(.up))
        XCTAssertEqual(document.roots[0].children.map(\.id), [first, second])
        XCTAssertEqual(press(.character("r"), .command, session: &session, document: &document), .jumpToCentralTopic)
        XCTAssertEqual(session.selectedNodeID, rootID)
        XCTAssertEqual(press(.character("l"), [.command, .shift], session: &session, document: &document), .showShortcutHelp)
        XCTAssertEqual(press(.enter, .option, session: &session, document: &document), .openProperties)
    }

    func testSpaceEnterTabMainPaths() {
        let rootID = UUID()
        var document = MindMapDocument(title: "主路径", roots: [MindMapNode(id: rootID, text: "中心")])
        var session = MindMapKeyboardSession()
        session.selectedNodeID = rootID
        XCTAssertEqual(press(.space, session: &session, document: &document), .beginEdit)
        XCTAssertEqual(session.mode, .edit)
        XCTAssertEqual(press(.enter, session: &session, document: &document), .insertNewline)
        XCTAssertEqual(document.roots[0].text, "中心\n")
        session.apply(.commitEdit, document: &document, frames: [])
        XCTAssertEqual(session.mode, .command)
        XCTAssertEqual(press(.enter, session: &session, document: &document), .createSibling)
        XCTAssertEqual(document.roots.map(\.text), ["中心\n", MindMapKeyboardSession.newTopicText])
        session.apply(.commitEdit, document: &document, frames: [])
        session.selectedNodeID = rootID
        XCTAssertEqual(press(.tab, session: &session, document: &document), .createChild)
        XCTAssertEqual(document.roots[0].children.map(\.text), [MindMapKeyboardSession.newTopicText])
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
