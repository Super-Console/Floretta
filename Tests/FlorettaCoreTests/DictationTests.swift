import FlorettaCore
import XCTest

final class DictationTests: XCTestCase {
    func testApplyCreatesOneChildAndReplacesThePlaceholder() {
        let rootID = UUID()
        var document = MindMapDocument(title: "听写", roots: [MindMapNode(id: rootID, text: "中心")])
        var session = MindMapKeyboardSession()
        session.selectedNodeID = rootID

        let result = DictationNodeInput.apply(phrase: "买菜", session: &session, document: &document)

        guard case .newChild(let childID) = result.target else {
            return XCTFail("expected a new child, got \(result.target)")
        }
        XCTAssertTrue(result.replacesPlaceholder)
        XCTAssertEqual(session.mode, .edit)
        XCTAssertEqual(session.selectedNodeID, childID)
        XCTAssertEqual(document.roots.map(\.id), [rootID])
        XCTAssertEqual(document.roots[0].children.map(\.id), [childID])
        XCTAssertEqual(document.node(childID)?.text, "买菜")
        XCTAssertNotEqual(document.node(childID)?.text, MindMapKeyboardSession.newTopicText)
    }

    func testPrepareThenReplacingTheFieldMatchesOneShotApply() {
        let rootID = UUID()
        func fresh() -> (MindMapDocument, MindMapKeyboardSession) {
            var document = MindMapDocument(title: "听写", roots: [MindMapNode(id: rootID, text: "中心")])
            var session = MindMapKeyboardSession()
            session.selectedNodeID = rootID
            return (document, session)
        }

        var typed = fresh()
        let prepared = DictationNodeInput.prepare(session: &typed.1, document: &typed.0)
        guard case .newChild = prepared.target else {
            return XCTFail("expected a new child")
        }
        XCTAssertEqual(typed.0.roots[0].children.map(\.text), [MindMapKeyboardSession.newTopicText])
        typed.1.replaceEditingText("买菜", document: &typed.0)

        var spoken = fresh()
        _ = DictationNodeInput.apply(phrase: "买菜", session: &spoken.1, document: &spoken.0)

        XCTAssertEqual(typed.0.roots[0].children.map(\.text), spoken.0.roots[0].children.map(\.text))
        XCTAssertEqual(typed.1.mode, spoken.1.mode)
        XCTAssertEqual(typed.1.editingText, spoken.1.editingText)
    }

    func testBlankSpeechDoesNotCreateANode() {
        let rootID = UUID()
        var document = MindMapDocument(title: "听写", roots: [MindMapNode(id: rootID, text: "中心")])
        var session = MindMapKeyboardSession()
        session.selectedNodeID = rootID
        let before = document

        XCTAssertEqual(
            DictationNodeInput.apply(phrase: "", session: &session, document: &document).target,
            .unavailable
        )
        XCTAssertEqual(
            DictationNodeInput.apply(phrase: " \n\t ", session: &session, document: &document).target,
            .unavailable
        )
        XCTAssertEqual(document, before)
        XCTAssertEqual(session.mode, .command)
        XCTAssertTrue(document.roots[0].children.isEmpty)
    }

    func testMarkedTextBlocksDictation() {
        let rootID = UUID()
        var document = MindMapDocument(title: "听写", roots: [MindMapNode(id: rootID, text: "中心")])
        var session = MindMapKeyboardSession()
        session.selectedNodeID = rootID
        session.isComposing = true
        let before = document

        XCTAssertEqual(DictationNodeInput.prepare(session: &session, document: &document).target, .unavailable)
        XCTAssertEqual(
            DictationNodeInput.apply(phrase: "买菜", session: &session, document: &document).target,
            .unavailable
        )
        XCTAssertEqual(document, before)
        XCTAssertTrue(document.roots[0].children.isEmpty)
        XCTAssertEqual(session.mode, .command)
    }

    func testOpenEditorAppendsThePhrase() {
        let rootID = UUID()
        var document = MindMapDocument(title: "听写", roots: [MindMapNode(id: rootID, text: "已有")])
        var session = MindMapKeyboardSession()
        session.selectedNodeID = rootID
        session.apply(.beginEdit, document: &document, frames: [])

        let result = DictationNodeInput.apply(phrase: "，补充", session: &session, document: &document)

        XCTAssertEqual(result.target, .currentEditor(rootID))
        XCTAssertFalse(result.replacesPlaceholder)
        XCTAssertEqual(document.roots[0].text, "已有，补充")
        XCTAssertTrue(document.roots[0].children.isEmpty)
        XCTAssertEqual(session.mode, .edit)
    }

    func testSecondPhraseWhileEditingDoesNotCreateAnotherChild() {
        let rootID = UUID()
        var document = MindMapDocument(title: "听写", roots: [MindMapNode(id: rootID, text: "中心")])
        var session = MindMapKeyboardSession()
        session.selectedNodeID = rootID
        _ = DictationNodeInput.apply(phrase: "买菜", session: &session, document: &document)
        let again = DictationNodeInput.prepare(session: &session, document: &document)

        XCTAssertEqual(document.roots[0].children.count, 1)
        guard case .currentEditor = again.target else {
            return XCTFail("expected to stay in the open editor")
        }
        _ = DictationNodeInput.apply(phrase: "和水果", session: &session, document: &document)
        XCTAssertEqual(document.roots[0].children.map(\.text), ["买菜和水果"])
    }

    func testNewlineStaysInsideTheSameNode() {
        let rootID = UUID()
        var document = MindMapDocument(title: "听写", roots: [MindMapNode(id: rootID, text: "中心")])
        var session = MindMapKeyboardSession()
        session.selectedNodeID = rootID

        _ = DictationNodeInput.apply(phrase: "买菜\n做饭", session: &session, document: &document)

        XCTAssertEqual(document.roots[0].children.count, 1)
        XCTAssertEqual(document.roots[0].children[0].text, "买菜\n做饭")
    }

    func testFreeNodeIsEditedAndNotGivenAChild() throws {
        var document = MindMapDocument(title: "听写", roots: [MindMapNode(text: "中心")])
        var session = MindMapKeyboardSession()
        let freeID = try XCTUnwrap(session.addFreeNode(at: MindMapPoint(x: 10, y: 20), text: "自由", document: &document))
        XCTAssertEqual(document.freeNodes.count, 1)

        let result = DictationNodeInput.apply(phrase: "口述", session: &session, document: &document)

        XCTAssertEqual(result.target, .currentEditor(freeID))
        XCTAssertEqual(document.freeNodes.map(\.text), ["自由口述"])
        XCTAssertTrue(document.freeNodes[0].children.isEmpty)
        XCTAssertTrue(document.roots[0].children.isEmpty)
        XCTAssertEqual(document.roots.count, 1)
    }

    func testNothingSelectedDoesNothing() {
        var document = MindMapDocument(title: "听写", roots: [MindMapNode(text: "中心")])
        var session = MindMapKeyboardSession()
        session.selectedNodeID = nil
        let before = document

        XCTAssertEqual(DictationNodeInput.prepare(session: &session, document: &document).target, .unavailable)
        XCTAssertEqual(
            DictationNodeInput.apply(phrase: "买菜", session: &session, document: &document).target,
            .unavailable
        )
        XCTAssertEqual(document, before)
    }

    func testCommittedDictationUndoesLikeATypedTitle() {
        let rootID = UUID()
        var document = MindMapDocument(title: "听写", roots: [MindMapNode(id: rootID, text: "中心")])
        var session = MindMapKeyboardSession()
        session.selectedNodeID = rootID
        let result = DictationNodeInput.apply(phrase: "买菜", session: &session, document: &document)
        guard case .newChild(let childID) = result.target else {
            return XCTFail("expected a new child")
        }

        session.apply(.commitEdit, document: &document, frames: [])
        XCTAssertEqual(session.mode, .command)
        XCTAssertEqual(document.node(childID)?.text, "买菜")

        session.apply(.undo, document: &document, frames: [])
        XCTAssertEqual(document.node(childID)?.text, MindMapKeyboardSession.newTopicText)
        session.apply(.undo, document: &document, frames: [])
        XCTAssertNil(document.node(childID))
        XCTAssertTrue(document.roots[0].children.isEmpty)

        session.apply(.redo, document: &document, frames: [])
        XCTAssertEqual(document.node(childID)?.text, MindMapKeyboardSession.newTopicText)
        session.apply(.redo, document: &document, frames: [])
        XCTAssertEqual(document.node(childID)?.text, "买菜")
        XCTAssertEqual(document.roots[0].id, rootID)
    }

    func testInsertionReplacesUTF16SelectionAndPlaceholder() {
        XCTAssertNil(
            DictationNodeInput.inserted(
                existing: "甲",
                phrase: "",
                utf16Selection: nil,
                replacesPlaceholder: false
            )
        )
        XCTAssertEqual(
            DictationNodeInput.inserted(
                existing: "甲",
                phrase: "乙",
                utf16Selection: nil,
                replacesPlaceholder: false
            ),
            "甲乙"
        )
        XCTAssertEqual(
            DictationNodeInput.inserted(
                existing: MindMapKeyboardSession.newTopicText,
                phrase: "买菜",
                utf16Selection: nil,
                replacesPlaceholder: true
            ),
            "买菜"
        )
        XCTAssertEqual(
            DictationNodeInput.inserted(
                existing: "abcdef",
                phrase: "X",
                utf16Selection: 2..<4,
                replacesPlaceholder: false
            ),
            "abXef"
        )
        let emoji = "甲🙂丙"
        let next = DictationNodeInput.inserted(
            existing: emoji,
            phrase: "乙",
            utf16Selection: 1..<3,
            replacesPlaceholder: false
        )
        XCTAssertEqual(next, "甲乙丙")
        XCTAssertEqual(
            DictationNodeInput.inserted(
                existing: "甲乙",
                phrase: "丙",
                utf16Selection: 50..<60,
                replacesPlaceholder: false
            ),
            "甲乙丙"
        )
    }

    func testStickyDictationEditsTheCard() throws {
        var document = MindMapDocument(title: "听写", roots: [MindMapNode(text: "中心")])
        var session = MindMapKeyboardSession()
        let stickyID = try XCTUnwrap(session.addSticky(at: MindMapPoint(x: 0, y: 0), text: "便签", document: &document))

        let result = DictationNodeInput.apply(phrase: "记得", session: &session, document: &document)

        XCTAssertEqual(result.target, .currentEditor(stickyID))
        XCTAssertEqual(document.stickies.map(\.text), ["便签记得"])
        XCTAssertTrue(document.roots[0].children.isEmpty)
    }
}
