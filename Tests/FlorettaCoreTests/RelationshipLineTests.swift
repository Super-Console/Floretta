import FlorettaCore
import XCTest

final class RelationshipLineTests: XCTestCase {
    private let rootID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let leftID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let rightID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private let hiddenID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    private let freeID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
    private let linkID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
    private let otherLinkID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!

    func testCrossBranchLineKeepsTheStoredRecordAndASeparateCurve() throws {
        var document = branches()
        let stored = try XCTUnwrap(document.linkTopics(from: leftID, to: rightID, title: "对照", id: linkID))
        XCTAssertEqual(stored.sourceID, leftID)
        XCTAssertEqual(stored.targetID, rightID)
        XCTAssertEqual(stored.title, "对照")
        XCTAssertEqual(document.parentID(of: leftID), rootID)
        XCTAssertEqual(document.parentID(of: rightID), rootID)
        XCTAssertNil(document.parentID(of: rootID))

        let frames = LayoutEngine().layout(document)
        let left = try XCTUnwrap(frames.first { $0.id == leftID })
        let right = try XCTUnwrap(frames.first { $0.id == rightID })
        XCTAssertNotNil(left.link)
        XCTAssertNotNil(right.link)
        XCTAssertNil(frames.first { $0.id == rootID }?.link)
        XCTAssertFalse(frames.contains { $0.id == linkID })

        let lines = RelationshipGeometry.lines(in: document, frames: frames)
        let line = try XCTUnwrap(lines.first)
        XCTAssertEqual(lines.map(\.id), [linkID])
        XCTAssertEqual(line.title, "对照")
        XCTAssertEqual(line.sourceID, leftID)
        XCTAssertEqual(line.targetID, rightID)
        XCTAssertEqual(line.curve.color, RelationshipGeometry.ink)
        assertOnEdge(line.curve.start, left.rect)
        assertOnEdge(line.curve.end, right.rect)
        XCTAssertNotEqual(line.curve.start, left.link?.start)
        XCTAssertGreaterThan(hypot(line.curveLabel.x - line.chordLabel.x, line.curveLabel.y - line.chordLabel.y), 8)
        XCTAssertEqual(line.labelSize, RelationshipGeometry.labelSize(title: "对照"))
        XCTAssertEqual(RelationshipGeometry.hit(at: line.curveLabel, in: lines), linkID)
        XCTAssertNil(RelationshipGeometry.hit(at: CGPoint(x: -10_000, y: -10_000), in: lines))

        let again = try FlorettaCodec.decode(try FlorettaCodec.encode(document))
        XCTAssertEqual(again.relationships, [stored])
        XCTAssertEqual(again.formatVersion, 1)
    }

    func testHiddenEndpointIsNotDrawnAndAFreeNodeKeepsNoHierarchyLink() throws {
        var folded = MindMapDocument(
            title: "折",
            roots: [
                MindMapNode(
                    id: rootID,
                    text: "根",
                    isCollapsed: true,
                    children: [
                        MindMapNode(id: leftID, text: "左支"),
                        MindMapNode(id: rightID, text: "右支", children: [MindMapNode(id: hiddenID, text: "藏")]),
                    ]
                ),
            ]
        )
        _ = folded.linkTopics(from: leftID, to: hiddenID, title: "藏着", id: linkID)
        XCTAssertTrue(RelationshipGeometry.lines(in: folded, frames: LayoutEngine().layout(folded)).isEmpty)

        var document = branches()
        document.addFreeNode(text: "自由", at: MindMapPoint(x: 40, y: 320), id: freeID)
        _ = document.linkTopics(from: freeID, to: leftID, title: "浮", id: linkID)
        let frames = LayoutEngine().layout(document)
        XCTAssertNil(frames.first { $0.id == freeID }?.link)
        let lines = RelationshipGeometry.lines(in: document, frames: frames)
        XCTAssertEqual(lines.map(\.id), [linkID])
        XCTAssertEqual(lines.first?.sourceID, freeID)
        XCTAssertEqual(lines.first?.title, "浮")
    }

    func testOverlappingLinesHitTheLaterOne() throws {
        var document = branches()
        _ = document.linkTopics(from: leftID, to: rightID, title: "先", id: linkID)
        _ = document.linkTopics(from: leftID, to: rightID, title: "后", id: otherLinkID)
        let lines = RelationshipGeometry.lines(in: document, frames: LayoutEngine().layout(document))
        XCTAssertEqual(lines.map(\.id), [linkID, otherLinkID])
        let point = try XCTUnwrap(lines.last?.curveLabel)
        XCTAssertEqual(RelationshipGeometry.hit(at: point, in: lines), otherLinkID)
    }

    func testCreateSelectDeleteAndUndoALabeledLine() throws {
        var document = branches()
        var session = MindMapKeyboardSession()
        session.selectedNodeID = leftID
        XCTAssertFalse(session.linkFreeNode(to: rightID, document: &document, title: "不该出现"))
        XCTAssertTrue(document.relationships.isEmpty)

        let created = try XCTUnwrap(session.linkSelectedTopic(to: rightID, document: &document, title: "对照"))
        XCTAssertEqual(created, document.relationships[0].id)
        XCTAssertEqual(document.relationships.map(\.title), ["对照"])
        XCTAssertEqual(session.selectedRelationshipID, created)
        XCTAssertNil(session.selectedNodeID)
        XCTAssertNil(session.selectedStickyID)

        session.apply(.undo, document: &document, frames: [])
        XCTAssertTrue(document.relationships.isEmpty)
        XCTAssertEqual(session.selectedNodeID, leftID)
        XCTAssertNil(session.selectedRelationshipID)
        session.apply(.redo, document: &document, frames: [])
        XCTAssertEqual(document.relationships.map(\.title), ["对照"])
        XCTAssertEqual(session.selectedRelationshipID, created)

        session.selectedNodeID = leftID
        XCTAssertNil(session.selectedRelationshipID)
        XCTAssertNil(session.linkSelectedTopic(to: leftID, document: &document))
        XCTAssertEqual(document.relationships.map(\.title), ["对照"])
        session.selectedRelationshipID = created

        let frames = LayoutEngine().layout(document)
        let line = try XCTUnwrap(RelationshipGeometry.lines(in: document, frames: frames).first)
        XCTAssertEqual(RelationshipGeometry.hit(at: line.curveLabel, in: [line]), created)
        session.selectedRelationshipID = created

        let deleted = session.handle(
            KeyEvent(key: .backspace, modifiers: [], mode: .command, isComposing: false),
            document: &document,
            frames: frames
        )
        XCTAssertEqual(deleted, .deleteSelection)
        XCTAssertTrue(document.relationships.isEmpty)
        XCTAssertEqual(document.topicCount, 3)
        XCTAssertNil(session.selectedRelationshipID)
        session.apply(.undo, document: &document, frames: [])
        XCTAssertEqual(document.relationships.map(\.title), ["对照"])
        XCTAssertEqual(session.selectedRelationshipID, created)
        session.apply(.redo, document: &document, frames: [])
        XCTAssertTrue(document.relationships.isEmpty)
    }

    func testLabelEditIsOneUndoStepAndCancelRestoresIt() throws {
        var document = branches()
        var session = MindMapKeyboardSession()
        session.selectedNodeID = leftID
        let created = try XCTUnwrap(session.linkSelectedTopic(to: rightID, document: &document, title: "对照"))
        session.apply(.beginEdit, document: &document, frames: [])
        XCTAssertEqual(session.mode, .edit)
        XCTAssertEqual(session.editingRelationshipID, created)
        session.replaceEditingText("新标签", document: &document)
        XCTAssertEqual(document.relationship(created)?.title, "新标签")
        session.apply(.commitEdit, document: &document, frames: [])
        XCTAssertEqual(session.mode, .command)
        session.apply(.undo, document: &document, frames: [])
        XCTAssertEqual(document.relationship(created)?.title, "对照")
        XCTAssertEqual(session.selectedRelationshipID, created)
        session.apply(.redo, document: &document, frames: [])
        XCTAssertEqual(document.relationship(created)?.title, "新标签")

        session.selectedRelationshipID = created
        session.apply(.beginEdit, document: &document, frames: [])
        session.replaceEditingText("临时", document: &document)
        session.apply(.cancelEdit, document: &document, frames: [])
        XCTAssertEqual(document.relationship(created)?.title, "新标签")
        XCTAssertEqual(session.mode, .command)
        XCTAssertEqual(session.selectedRelationshipID, created)
    }

    func testDeletingOneLineSelectsTheNeighborAndUndoRestoresTheDeletedLine() throws {
        var document = branches()
        var session = MindMapKeyboardSession()
        session.selectedNodeID = leftID
        let first = try XCTUnwrap(session.linkSelectedTopic(to: rightID, document: &document, title: "一"))
        session.selectedNodeID = leftID
        let second = try XCTUnwrap(session.linkSelectedTopic(to: rootID, document: &document, title: "二"))
        XCTAssertEqual(session.selectedRelationshipID, second)
        session.apply(.deleteSelection, document: &document, frames: [])
        XCTAssertEqual(document.relationships.map(\.id), [first])
        XCTAssertEqual(session.selectedRelationshipID, first)
        session.apply(.undo, document: &document, frames: [])
        XCTAssertEqual(document.relationships.map(\.id), [first, second])
        XCTAssertEqual(document.relationships.map(\.title), ["一", "二"])
        XCTAssertEqual(session.selectedRelationshipID, second)
    }

    func testSelectionIsExclusiveWithTopicsAndStickies() {
        var session = MindMapKeyboardSession()
        session.selectedNodeID = leftID
        session.selectedRelationshipID = linkID
        XCTAssertNil(session.selectedNodeID)
        XCTAssertEqual(session.selectedRelationshipID, linkID)
        session.selectedStickyID = freeID
        XCTAssertNil(session.selectedRelationshipID)
        XCTAssertEqual(session.selectedStickyID, freeID)
        session.selectedRelationshipID = otherLinkID
        XCTAssertNil(session.selectedStickyID)
        XCTAssertNil(session.selectedNodeID)
    }

    private func branches() -> MindMapDocument {
        MindMapDocument(
            title: "关系",
            roots: [
                MindMapNode(
                    id: rootID,
                    text: "根",
                    children: [
                        MindMapNode(id: leftID, text: "左支"),
                        MindMapNode(id: rightID, text: "右支"),
                    ]
                ),
            ]
        )
    }

    private func assertOnEdge(_ point: CGPoint, _ rect: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        let onX = abs(point.x - rect.minX) < 0.8 || abs(point.x - rect.maxX) < 0.8
        let onY = abs(point.y - rect.minY) < 0.8 || abs(point.y - rect.maxY) < 0.8
        let insideX = point.x >= rect.minX - 0.8 && point.x <= rect.maxX + 0.8
        let insideY = point.y >= rect.minY - 0.8 && point.y <= rect.maxY + 0.8
        XCTAssertTrue(insideX && insideY && (onX || onY), "\(point) is not on \(rect)", file: file, line: line)
    }
}
