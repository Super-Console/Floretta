import FlorettaCore
import XCTest

final class SummaryBoundaryTests: XCTestCase {
    private let rootID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let firstID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private let secondID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    private let thirdID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
    private let summaryID = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
    private let boundaryID = UUID(uuidString: "66666666-6666-4666-8666-666666666666")!

    func testCreateEditRemoveSummaryAndBoundary() throws {
        var document = map()
        XCTAssertFalse(document.canEnclose(rootID))
        XCTAssertNil(document.addSummary(covering: rootID))
        XCTAssertEqual(document.topicCount, 4)

        let summary = try XCTUnwrap(document.addSummary(covering: firstID, id: summaryID))
        XCTAssertEqual(summary.text, "概要")
        XCTAssertEqual(summary.rangeStart, 0)
        XCTAssertEqual(summary.rangeEnd, 0)
        XCTAssertEqual(document.summaryCount, 1)
        XCTAssertEqual(document.topicCount, 4)
        XCTAssertFalse(document.roots[0].children.contains { $0.id == summaryID })

        XCTAssertTrue(document.renameSummary(summaryID, text: "合并"))
        XCTAssertEqual(document.summary(summaryID)?.text, "合并")

        let boundary = try XCTUnwrap(document.addBoundary(under: rootID, rangeStart: 0, rangeEnd: 1, title: "一组", id: boundaryID))
        XCTAssertEqual(boundary.rangeStart, 0)
        XCTAssertEqual(boundary.rangeEnd, 1)
        XCTAssertTrue(document.renameBoundary(boundaryID, title: "改名"))
        XCTAssertEqual(document.boundary(boundaryID)?.title, "改名")

        let roundTrip = try FlorettaCodec.decode(try FlorettaCodec.encode(document))
        XCTAssertEqual(roundTrip.summary(summaryID)?.text, "合并")
        XCTAssertEqual(roundTrip.boundary(boundaryID)?.title, "改名")
        XCTAssertEqual(roundTrip.boundary(boundaryID)?.rangeEnd, 1)

        XCTAssertTrue(document.removeSummary(summaryID))
        XCTAssertNil(document.summary(summaryID))
        XCTAssertTrue(document.removeBoundary(boundaryID))
        XCTAssertEqual(document.boundaryCount, 0)
        XCTAssertNil(document.addSummary(under: rootID, rangeStart: 0, rangeEnd: 9, id: summaryID))
        XCTAssertNil(document.addBoundary(under: rootID, rangeStart: 2, rangeEnd: 1, id: boundaryID))
    }

    func testSelectionCreateEditRemoveUndoAndRedo() {
        var document = map()
        var session = MindMapKeyboardSession()
        session.selectedNodeID = firstID
        let created = session.addSummaryForSelection(document: &document)
        XCTAssertEqual(created, document.roots[0].summaries.first?.id)
        XCTAssertEqual(session.mode, .edit)
        XCTAssertEqual(document.summary(created!)?.text, "概要")
        session.replaceEditingText("收束", document: &document)
        session.apply(.commitEdit, document: &document, frames: [])
        XCTAssertEqual(document.summary(created!)?.text, "收束")
        XCTAssertEqual(session.mode, .command)

        session.apply(.undo, document: &document, frames: [])
        XCTAssertEqual(document.summary(created!)?.text, "概要")
        session.apply(.undo, document: &document, frames: [])
        XCTAssertEqual(document.summaryCount, 0)
        session.apply(.redo, document: &document, frames: [])
        XCTAssertEqual(document.summaryCount, 1)

        session.selectedNodeID = secondID
        let boundary = session.addBoundaryForSelection(document: &document)
        XCTAssertNotNil(boundary)
        XCTAssertEqual(session.selectedBoundaryID, boundary)
        session.apply(.beginEdit, document: &document, frames: [])
        session.replaceEditingText("圈", document: &document)
        session.apply(.commitEdit, document: &document, frames: [])
        XCTAssertEqual(document.boundary(boundary!)?.title, "圈")
        session.selectedBoundaryID = boundary
        session.apply(.deleteSelection, document: &document, frames: [])
        XCTAssertNil(document.boundary(boundary!))
        session.apply(.undo, document: &document, frames: [])
        XCTAssertEqual(document.boundary(boundary!)?.title, "圈")
        session.apply(.redo, document: &document, frames: [])
        XCTAssertEqual(document.boundaryCount, 0)

        session.selectedNodeID = rootID
        XCTAssertNil(session.addSummaryForSelection(document: &document))
        XCTAssertNil(session.addBoundaryForSelection(document: &document))
    }

    func testCancelEditRestoresSummaryText() {
        var document = map()
        var session = MindMapKeyboardSession()
        session.selectedNodeID = firstID
        let created = session.addSummaryForSelection(document: &document)
        session.replaceEditingText("临时", document: &document)
        XCTAssertEqual(document.summary(created!)?.text, "临时")
        session.apply(.cancelEdit, document: &document, frames: [])
        XCTAssertEqual(document.summary(created!)?.text, "概要")
        XCTAssertEqual(session.mode, .command)
    }

    func testRangesFollowInsertedAndRemovedSiblings() throws {
        var document = map()
        XCTAssertNotNil(document.addSummary(under: rootID, rangeStart: 0, rangeEnd: 1, text: "前两个", id: summaryID))
        XCTAssertNotNil(document.addBoundary(under: rootID, rangeStart: 0, rangeEnd: 1, title: "前两个", id: boundaryID))
        let inserted = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!
        XCTAssertTrue(document.insertSibling(MindMapNode(id: inserted, text: "插"), after: firstID))
        XCTAssertEqual(document.roots[0].children.map(\.id), [firstID, inserted, secondID, thirdID])
        XCTAssertEqual(document.summary(summaryID)?.rangeStart, 0)
        XCTAssertEqual(document.summary(summaryID)?.rangeEnd, 2)
        XCTAssertEqual(document.boundary(boundaryID)?.rangeEnd, 2)

        XCTAssertTrue(document.removeNode(secondID))
        XCTAssertEqual(document.summary(summaryID)?.rangeEnd, 1)
        XCTAssertTrue(document.removeNode(firstID))
        XCTAssertTrue(document.removeNode(inserted))
        XCTAssertNil(document.summary(summaryID))
        XCTAssertNil(document.boundary(boundaryID))
        XCTAssertEqual(document.topicCount, 2)
    }

    func testGeometryEnclosesTheCoveredTopics() throws {
        var document = map()
        XCTAssertNotNil(document.addSummary(under: rootID, rangeStart: 0, rangeEnd: 2, text: "三个", id: summaryID))
        XCTAssertNotNil(document.addBoundary(under: rootID, rangeStart: 0, rangeEnd: 2, title: "全", id: boundaryID))
        let frames = LayoutEngine().layout(document)
        let covered = frames.filter { [firstID, secondID, thirdID].contains($0.id) }
        XCTAssertEqual(covered.count, 3)
        let union = covered.dropFirst().reduce(covered[0].rect) { $0.union($1.rect) }
        let summary = try XCTUnwrap(SummaryGeometry.summaries(in: document, frames: frames).first)
        let boundary = try XCTUnwrap(SummaryGeometry.boundaries(in: document, frames: frames).first)
        XCTAssertFalse(summary.topicRect.intersects(union))
        let beside = summary.topicRect.minX >= union.maxX - 0.5 || summary.topicRect.maxX <= union.minX + 0.5
        XCTAssertTrue(beside)
        XCTAssertTrue(boundary.rect.contains(union))
        XCTAssertGreaterThan(boundary.rect.width, union.width)
        XCTAssertEqual(SummaryGeometry.summaryHit(at: CGPoint(x: summary.topicRect.midX, y: summary.topicRect.midY), in: [summary]), summaryID)
        let interior = CGPoint(x: union.midX, y: union.midY)
        XCTAssertNil(SummaryGeometry.boundaryHit(at: interior, in: [boundary]))
        let stroke = CGPoint(x: boundary.rect.minX, y: boundary.rect.midY)
        XCTAssertEqual(SummaryGeometry.boundaryHit(at: stroke, in: [boundary]), boundaryID)
        XCTAssertFalse(frames.contains { $0.id == summaryID || $0.id == boundaryID })
    }

    func testXMindSummaryAndBoundaryRoundTrip() throws {
        var document = map()
        XCTAssertNotNil(document.addSummary(under: rootID, rangeStart: 1, rangeEnd: 2, text: "后两个", id: summaryID))
        XCTAssertNotNil(document.addBoundary(under: rootID, rangeStart: 0, rangeEnd: 0, title: "只包第一个", id: boundaryID))
        let exported = try FlorettaXMindCodec.export(document)
        let imported = try FlorettaXMindCodec.importMap(exported)
        let summary = try XCTUnwrap(imported.summary(summaryID))
        XCTAssertEqual(summary.text, "后两个")
        XCTAssertEqual(summary.rangeStart, 1)
        XCTAssertEqual(summary.rangeEnd, 2)
        XCTAssertEqual(imported.boundary(boundaryID)?.title, "只包第一个")
        XCTAssertEqual(imported.boundary(boundaryID)?.rangeEnd, 0)
        XCTAssertEqual(imported.topicCount, 4)
        XCTAssertFalse(imported.roots[0].children.contains { $0.text == "后两个" })

        var edited = imported
        XCTAssertTrue(edited.renameSummary(summaryID, text: "改过的概要"))
        let again = try FlorettaXMindCodec.importMap(try FlorettaXMindCodec.export(edited))
        XCTAssertEqual(again.summary(summaryID)?.text, "改过的概要")
        XCTAssertEqual(again.boundary(boundaryID)?.title, "只包第一个")
    }

    func testOfficialXMindSummaryRecordsMapToTheSameModel() throws {
        let content = """
        [{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","class":"sheet","title":"图","rootTopic":{"id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","class":"topic","title":"根","summaries":[{"id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","range":"(0,1)","topicId":"dddddddd-dddd-4ddd-8ddd-dddddddddddd"}],"boundaries":[{"id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","range":"(1,1)","title":"边"}],"children":{"attached":[{"id":"ffffffff-ffff-4fff-8fff-ffffffffffff","class":"topic","title":"甲"},{"id":"12121212-1212-4121-8121-121212121212","class":"topic","title":"乙"}],"summary":[{"id":"dddddddd-dddd-4ddd-8ddd-dddddddddddd","class":"topic","title":"合"}]}}}]
        """
        let data = ZipArchive.write([
            ZipEntry(name: "content.json", data: Data(content.utf8)),
            ZipEntry(name: "metadata.json", data: Data(#"{"dataStructureVersion":"2"}"#.utf8)),
        ])
        let imported = try FlorettaXMindCodec.importMap(data)
        XCTAssertEqual(imported.topicCount, 3)
        let summary = try XCTUnwrap(imported.roots[0].summaries.first)
        XCTAssertEqual(summary.text, "合")
        XCTAssertEqual(summary.rangeStart, 0)
        XCTAssertEqual(summary.rangeEnd, 1)
        XCTAssertEqual(summary.id, UUID(uuidString: "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD"))
        let boundary = try XCTUnwrap(imported.roots[0].boundaries.first)
        XCTAssertEqual(boundary.title, "边")
        XCTAssertEqual(boundary.rangeStart, 1)
        XCTAssertEqual(boundary.rangeEnd, 1)
        let unchanged = try FlorettaXMindCodec.export(imported)
        XCTAssertEqual(try entry(unchanged, "content.json"), try entry(data, "content.json"))
        var edited = imported
        XCTAssertTrue(edited.renameSummary(summary.id, text: "改"))
        let exported = try FlorettaXMindCodec.importMap(try FlorettaXMindCodec.export(edited))
        XCTAssertEqual(exported.summary(summary.id)?.text, "改")
        XCTAssertEqual(exported.summary(summary.id)?.rangeEnd, 1)
        XCTAssertEqual(exported.boundary(boundary.id)?.title, "边")
    }

    private func map() -> MindMapDocument {
        MindMapDocument(
            title: "圈",
            roots: [
                MindMapNode(
                    id: rootID,
                    text: "根",
                    children: [
                        MindMapNode(id: firstID, text: "甲"),
                        MindMapNode(id: secondID, text: "乙"),
                        MindMapNode(id: thirdID, text: "丙"),
                    ]
                ),
            ]
        )
    }

    private func entry(_ data: Data, _ name: String) throws -> Data {
        let entries = try ZipArchive.read(data, limits: .standard)
        return try XCTUnwrap(entries.first { $0.name == name }?.data)
    }
}
