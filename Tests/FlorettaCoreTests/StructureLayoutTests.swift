import FlorettaCore
import XCTest

/// Geometry of the pluggable structures. Every layout places the tree through
/// `LayoutGeometry`, so these tests read frames only — no canvas, no export.
final class StructureLayoutTests: XCTestCase {
    private func logicChart(_ document: MindMapDocument) -> [NodeFrame] {
        LayoutEngine(kind: .logicChart).layout(document)
    }

    private func orgChart(_ document: MindMapDocument) -> [NodeFrame] {
        LayoutEngine(kind: .orgChart).layout(document)
    }

    // MARK: - 逻辑图

    func testLogicChartGrowsRightAndIndentsEveryLevelByTheHorizontalGap() throws {
        let grand = MindMapNode(text: "孙")
        let child = MindMapNode(text: "子", children: [grand])
        let root = MindMapNode(text: "根", children: [child])
        let frames = logicChart(MindMapDocument(title: "logic", roots: [root]))
        XCTAssertEqual(frames.count, 3)
        let rootFrame = try XCTUnwrap(frames.first { $0.id == root.id })
        let childFrame = try XCTUnwrap(frames.first { $0.id == child.id })
        let grandFrame = try XCTUnwrap(frames.first { $0.id == grand.id })
        let gap = LayoutMetrics().horizontalGap
        XCTAssertEqual(rootFrame.frame.minX, 0, accuracy: 0.001)
        XCTAssertEqual(rootFrame.frame.minY, 0, accuracy: 0.001)
        XCTAssertGreaterThan(childFrame.frame.minX, rootFrame.frame.maxX)
        XCTAssertEqual(childFrame.frame.minX - rootFrame.frame.maxX, gap, accuracy: 0.001)
        XCTAssertEqual(grandFrame.frame.minX - childFrame.frame.maxX, gap, accuracy: 0.001)
        XCTAssertEqual(rootFrame.fontSize, 30)
        XCTAssertEqual(childFrame.fontSize, 20)
        XCTAssertEqual(grandFrame.fontSize, 18)
    }

    func testLogicChartStacksSiblingsOneSiblingGapApart() throws {
        let first = MindMapNode(text: "一")
        let second = MindMapNode(text: "这是一段明显更长的二级主题")
        let third = MindMapNode(text: "三")
        let root = MindMapNode(text: "根", children: [first, second, third])
        let frames = logicChart(MindMapDocument(title: "rows", roots: [root]))
        let firstFrame = try XCTUnwrap(frames.first { $0.id == first.id })
        let secondFrame = try XCTUnwrap(frames.first { $0.id == second.id })
        let thirdFrame = try XCTUnwrap(frames.first { $0.id == third.id })
        let rows = [firstFrame, secondFrame, thirdFrame].sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertEqual(Set(rows.map(\.frame.minX)).count, 1)
        XCTAssertEqual(rows[1].frame.minY - rows[0].frame.maxY, LayoutMetrics().siblingGap, accuracy: 0.001)
        XCTAssertEqual(rows[2].frame.minY - rows[1].frame.maxY, LayoutMetrics().siblingGap, accuracy: 0.001)
        XCTAssertGreaterThan(rows[1].frame.width, rows[0].frame.width)
    }

    func testLogicChartCentersTheParentOnTheStackOfItsChildren() throws {
        // One child with five of its own: the child is centered on the root, and
        // the grandchildren stack is centered on the child.
        let child = MindMapNode(text: "子", children: (0..<5).map { MindMapNode(text: "孙\($0)") })
        let root = MindMapNode(text: "根", children: [child])
        let frames = logicChart(MindMapDocument(title: "center", roots: [root]))
        let rootFrame = try XCTUnwrap(frames.first { $0.id == root.id })
        let childFrame = try XCTUnwrap(frames.first { $0.id == child.id })
        XCTAssertEqual(childFrame.frame.midY, rootFrame.frame.midY, accuracy: 0.01)
        let grands = frames.filter { $0.parentID == child.id }.sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertEqual(grands.count, 5)
        let stackTop = grands[0].frame.minY
        let stackBottom = grands[4].frame.maxY
        XCTAssertEqual((stackTop + stackBottom) / 2, childFrame.frame.midY, accuracy: 0.01)

        // Three equal siblings: the root lines up with the middle one.
        let first = MindMapNode(text: "甲")
        let middle = MindMapNode(text: "乙")
        let last = MindMapNode(text: "丙")
        let triple = MindMapNode(text: "根", children: [first, middle, last])
        let rows = logicChart(MindMapDocument(title: "center3", roots: [triple]))
        let tripleFrame = try XCTUnwrap(rows.first { $0.id == triple.id })
        let firstFrame = try XCTUnwrap(rows.first { $0.id == first.id })
        let middleFrame = try XCTUnwrap(rows.first { $0.id == middle.id })
        let lastFrame = try XCTUnwrap(rows.first { $0.id == last.id })
        XCTAssertEqual(tripleFrame.frame.midY, middleFrame.frame.midY, accuracy: 0.01)
        XCTAssertEqual(firstFrame.frame.midY, middleFrame.frame.midY - firstFrame.frame.height - LayoutMetrics().siblingGap, accuracy: 0.01)
        XCTAssertEqual(lastFrame.frame.midY, middleFrame.frame.midY + lastFrame.frame.height + LayoutMetrics().siblingGap, accuracy: 0.01)
    }

    func testLogicChartLinksLeaveTheRightEdgeAndEnterTheLeftEdge() throws {
        let leaf = MindMapNode(text: "子")
        let root = MindMapNode(text: "根", children: [leaf])
        let frames = logicChart(MindMapDocument(title: "links", roots: [root]))
        let rootFrame = try XCTUnwrap(frames.first { $0.id == root.id })
        let leafFrame = try XCTUnwrap(frames.first { $0.id == leaf.id })
        let link = try XCTUnwrap(leafFrame.link)
        XCTAssertEqual(link.start.x, rootFrame.frame.maxX, accuracy: 0.001)
        XCTAssertEqual(link.start.y, rootFrame.frame.midY, accuracy: 0.001)
        XCTAssertEqual(link.end.x, leafFrame.frame.minX, accuracy: 0.001)
        XCTAssertEqual(link.end.y, leafFrame.frame.midY, accuracy: 0.001)
        let dx = link.end.x - link.start.x
        XCTAssertEqual(link.control1.x, link.start.x + dx * 0.5, accuracy: 0.001)
        XCTAssertEqual(link.control1.y, link.start.y, accuracy: 0.001)
        XCTAssertEqual(link.control2.x, link.end.x - dx * 0.5, accuracy: 0.001)
        XCTAssertNil(rootFrame.link)
        XCTAssertEqual(leafFrame.parentID, root.id)
    }

    func testLogicChartCollapsedTopicHidesItsSubtree() {
        let child = MindMapNode(text: "子", children: [MindMapNode(text: "孙")])
        var root = MindMapNode(text: "根", children: [child])
        root.isCollapsed = true
        let frames = logicChart(MindMapDocument(title: "fold", roots: [root]))
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames.first?.id, root.id)
    }

    func testLogicChartPlacesAStoredRootPointAndKeepsTheSubtreeWithIt() throws {
        let child = MindMapNode(text: "子")
        let root = MindMapNode(
            text: "根",
            position: MindMapPoint(x: 120, y: -40),
            children: [child]
        )
        let frames = logicChart(MindMapDocument(title: "manual", roots: [root]))
        let rootFrame = try XCTUnwrap(frames.first { $0.id == root.id })
        let childFrame = try XCTUnwrap(frames.first { $0.id == child.id })
        XCTAssertEqual(rootFrame.origin.x, 120, accuracy: 0.001)
        XCTAssertEqual(rootFrame.origin.y, -40, accuracy: 0.001)
        XCTAssertEqual(childFrame.frame.minX, rootFrame.frame.maxX + LayoutMetrics().horizontalGap, accuracy: 0.001)
        XCTAssertEqual(childFrame.frame.midY, rootFrame.frame.midY, accuracy: 0.001)
    }

    func testLogicChartKeepsFramesFromOverlapping() {
        let root = MindMapNode(text: "根", children: [
            MindMapNode(text: "甲", children: (0..<4).map { MindMapNode(text: "甲\($0)") }),
            MindMapNode(text: "乙", children: (0..<2).map { MindMapNode(text: "乙\($0)") }),
            MindMapNode(text: "丙"),
        ])
        let frames = logicChart(MindMapDocument(title: "no-overlap", roots: [root]))
        XCTAssertEqual(frames.count, 10)
        assertNoOverlap(frames)
        let union = frames.reduce(frames[0].frame) { $0.union($1.frame) }
        XCTAssertEqual(frames[0].frame.midY, union.midY, accuracy: 1)
    }

    func testDocumentStructureDrivesTheEngineAndSurvivesTheCodec() throws {
        let document = MindMapDocument(
            title: "logic",
            roots: [MindMapNode(text: "根")],
            layoutKind: .logicChart
        )
        XCTAssertEqual(LayoutEngine.forDocument(document).kind, .logicChart)
        XCTAssertEqual(LayoutEngine().kind, .bilateral)
        let reopened = try FlorettaCodec.decode(FlorettaCodec.encode(document))
        XCTAssertEqual(reopened.layoutKind, .logicChart)
        XCTAssertEqual(
            LayoutEngine.forDocument(reopened).layout(reopened),
            LayoutEngine(kind: .logicChart).layout(document)
        )
        let plain = try XCTUnwrap(
            String(data: FlorettaCodec.encode(MindMapDocument(title: "plain")), encoding: .utf8)
        )
        XCTAssertFalse(plain.contains("\"layoutKind\""))
        XCTAssertEqual(try FlorettaCodec.decode(Data(plain.utf8)).layoutKind, .bilateral)
    }

    // MARK: - 组织结构图

    func testOrgChartGrowsDownAndIndentsEveryLevelByTheHorizontalGap() throws {
        let grand = MindMapNode(text: "孙")
        let child = MindMapNode(text: "子", children: [grand])
        let root = MindMapNode(text: "根", children: [child])
        let frames = orgChart(MindMapDocument(title: "org", roots: [root]))
        XCTAssertEqual(frames.count, 3)
        let rootFrame = try XCTUnwrap(frames.first { $0.id == root.id })
        let childFrame = try XCTUnwrap(frames.first { $0.id == child.id })
        let grandFrame = try XCTUnwrap(frames.first { $0.id == grand.id })
        let gap = LayoutMetrics().horizontalGap
        XCTAssertEqual(rootFrame.frame.minY, 0, accuracy: 0.001)
        XCTAssertEqual(rootFrame.frame.midX, 0, accuracy: 0.001)
        XCTAssertGreaterThan(childFrame.frame.minY, rootFrame.frame.maxY)
        XCTAssertEqual(childFrame.frame.minY - rootFrame.frame.maxY, gap, accuracy: 0.001)
        XCTAssertEqual(grandFrame.frame.minY - childFrame.frame.maxY, gap, accuracy: 0.001)
        XCTAssertEqual(childFrame.frame.midX, rootFrame.frame.midX, accuracy: 0.001)
        XCTAssertEqual(grandFrame.frame.midX, childFrame.frame.midX, accuracy: 0.001)
    }

    func testOrgChartLaysSiblingsInOneRowOneSiblingGapApart() throws {
        let first = MindMapNode(text: "一")
        let second = MindMapNode(text: "这是一段明显更长的二级主题")
        let third = MindMapNode(text: "三")
        let root = MindMapNode(text: "根", children: [first, second, third])
        let frames = orgChart(MindMapDocument(title: "row", roots: [root]))
        let firstFrame = try XCTUnwrap(frames.first { $0.id == first.id })
        let secondFrame = try XCTUnwrap(frames.first { $0.id == second.id })
        let thirdFrame = try XCTUnwrap(frames.first { $0.id == third.id })
        let row = [firstFrame, secondFrame, thirdFrame].sorted { $0.frame.minX < $1.frame.minX }
        XCTAssertEqual(Set(row.map(\.frame.minY)).count, 1)
        XCTAssertEqual(row[1].frame.minX - row[0].frame.maxX, LayoutMetrics().siblingGap, accuracy: 0.001)
        XCTAssertEqual(row[2].frame.minX - row[1].frame.maxX, LayoutMetrics().siblingGap, accuracy: 0.001)
    }

    func testOrgChartCentersTheParentOverTheRowOfItsChildren() throws {
        let first = MindMapNode(text: "甲")
        let second = MindMapNode(text: "乙")
        let third = MindMapNode(text: "丙")
        let root = MindMapNode(text: "根", children: [first, second, third])
        let frames = orgChart(MindMapDocument(title: "center", roots: [root]))
        let rootFrame = try XCTUnwrap(frames.first { $0.id == root.id })
        let secondFrame = try XCTUnwrap(frames.first { $0.id == second.id })
        let kids = [first, second, third].map { id in frames.first { $0.id == id.id }! }.sorted {
            $0.frame.minX < $1.frame.minX
        }
        XCTAssertEqual((kids[0].frame.minX + kids[2].frame.maxX) / 2, rootFrame.frame.midX, accuracy: 0.01)
        XCTAssertEqual(secondFrame.frame.midX, rootFrame.frame.midX, accuracy: 0.01)
    }

    func testOrgChartLinksLeaveTheBottomEdgeAndEnterTheTopEdge() throws {
        let leaf = MindMapNode(text: "子")
        let root = MindMapNode(text: "根", children: [leaf])
        let frames = orgChart(MindMapDocument(title: "links", roots: [root]))
        let rootFrame = try XCTUnwrap(frames.first { $0.id == root.id })
        let leafFrame = try XCTUnwrap(frames.first { $0.id == leaf.id })
        let link = try XCTUnwrap(leafFrame.link)
        XCTAssertEqual(link.start.x, rootFrame.frame.midX, accuracy: 0.001)
        XCTAssertEqual(link.start.y, rootFrame.frame.maxY, accuracy: 0.001)
        XCTAssertEqual(link.end.x, leafFrame.frame.midX, accuracy: 0.001)
        XCTAssertEqual(link.end.y, leafFrame.frame.minY, accuracy: 0.001)
        let dy = link.end.y - link.start.y
        XCTAssertEqual(link.control1.x, link.start.x, accuracy: 0.001)
        XCTAssertEqual(link.control1.y, link.start.y + dy * 0.5, accuracy: 0.001)
        XCTAssertEqual(link.control2.x, link.end.x, accuracy: 0.001)
        XCTAssertEqual(link.control2.y, link.end.y - dy * 0.5, accuracy: 0.001)
        XCTAssertNil(rootFrame.link)
        XCTAssertEqual(leafFrame.parentID, root.id)
    }

    func testOrgChartCollapsedTopicHidesItsSubtree() {
        let child = MindMapNode(text: "子", children: [MindMapNode(text: "孙")])
        var root = MindMapNode(text: "根", children: [child])
        root.isCollapsed = true
        let frames = orgChart(MindMapDocument(title: "fold", roots: [root]))
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames.first?.id, root.id)
    }

    func testOrgChartPlacesAStoredRootPointAndKeepsTheSubtreeUnderIt() throws {
        let child = MindMapNode(text: "子")
        let root = MindMapNode(
            text: "根",
            position: MindMapPoint(x: 90, y: -30),
            children: [child]
        )
        let frames = orgChart(MindMapDocument(title: "manual", roots: [root]))
        let rootFrame = try XCTUnwrap(frames.first { $0.id == root.id })
        let childFrame = try XCTUnwrap(frames.first { $0.id == child.id })
        XCTAssertEqual(rootFrame.origin.x, 90, accuracy: 0.001)
        XCTAssertEqual(rootFrame.origin.y, -30, accuracy: 0.001)
        XCTAssertEqual(childFrame.frame.minY, rootFrame.frame.maxY + LayoutMetrics().horizontalGap, accuracy: 0.001)
        XCTAssertEqual(childFrame.frame.midX, rootFrame.frame.midX, accuracy: 0.001)
    }

    func testOrgChartKeepsFramesFromOverlapping() {
        let root = MindMapNode(text: "根", children: [
            MindMapNode(text: "甲", children: (0..<4).map { MindMapNode(text: "甲\($0)") }),
            MindMapNode(text: "乙", children: (0..<2).map { MindMapNode(text: "乙\($0)") }),
            MindMapNode(text: "丙"),
        ])
        let frames = orgChart(MindMapDocument(title: "no-overlap", roots: [root]))
        XCTAssertEqual(frames.count, 10)
        assertNoOverlap(frames)
        let deepest = frames.map(\.frame.maxY).max() ?? 0
        XCTAssertEqual(frames.first { $0.id == root.id }?.frame.minY, 0)
        XCTAssertGreaterThan(deepest, 0)
    }

    func testOrgChartRoundTripsThroughTheDocument() throws {
        let document = MindMapDocument(
            title: "org",
            roots: [MindMapNode(text: "根", children: [MindMapNode(text: "子")])],
            layoutKind: .orgChart
        )
        XCTAssertEqual(LayoutEngine.forDocument(document).kind, .orgChart)
        let reopened = try FlorettaCodec.decode(FlorettaCodec.encode(document))
        XCTAssertEqual(reopened.layoutKind, .orgChart)
        XCTAssertEqual(
            LayoutEngine.forDocument(reopened).layout(reopened),
            LayoutEngine(kind: .orgChart).layout(document)
        )
        // The shipped three stay registered. The full set lives in
        // `StructureKindsLayoutTests` so this test does not need an edit every
        // time a structure joins the engine.
        XCTAssertTrue(
            Set(LayoutKind.allCases).isSuperset(of: [.bilateral, .logicChart, .orgChart])
        )
    }

    private func assertNoOverlap(_ frames: [NodeFrame], file: StaticString = #filePath, line: UInt = #line) {
        for left in frames.indices {
            for right in frames.indices where right > left {
                let hit = frames[left].frame.intersection(frames[right].frame)
                XCTAssertFalse(hit.width > 0.5 && hit.height > 0.5, file: file, line: line)
            }
        }
    }
}
