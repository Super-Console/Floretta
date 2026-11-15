import FlorettaCore
import XCTest

/// Geometry of the 1.0.22 structures (时间轴 / 鱼骨图 / 树型表格 / 矩阵图).
/// Every layout places the tree through `LayoutGeometry`, so these tests read
/// frames only: no canvas, no exporter.
final class StructureKindsLayoutTests: XCTestCase {
    private func timeline(_ document: MindMapDocument) -> [NodeFrame] {
        LayoutEngine(kind: .timeline).layout(document)
    }

    // MARK: - 时间轴

    func testTimelineCentersTheRootOnTheSpineAndAlternatesFirstLevelTopics() throws {
        let events = (0..<4).map { MindMapNode(text: "节点\($0)") }
        let root = MindMapNode(text: "时间轴", children: events)
        let frames = timeline(MindMapDocument(title: "timeline", roots: [root]))
        XCTAssertEqual(frames.count, 5)
        let rootFrame = try XCTUnwrap(frames.first { $0.id == root.id })
        let spine = rootFrame.frame.midY
        let gap = LayoutMetrics().horizontalGap
        let placed = try events.enumerated().map { index, event in
            (index, try XCTUnwrap(frames.first { $0.id == event.id }))
        }
        // Even siblings sit above the spine, odd siblings below it.
        for (index, frame) in placed {
            if index % 2 == 0 {
                XCTAssertEqual(spine - frame.frame.maxY, gap, accuracy: 0.001)
            } else {
                XCTAssertEqual(frame.frame.minY - spine, gap, accuracy: 0.001)
            }
        }
    }

    func testTimelineAdvancesFirstLevelTopicsAlongTheSpineInSiblingOrder() throws {
        var cursor: CGFloat = 0
        let events = (0..<5).map { MindMapNode(text: "第\($0)个节点") }
        let root = MindMapNode(text: "轴", children: events)
        let frames = timeline(MindMapDocument(title: "order", roots: [root]))
        let rootFrame = try XCTUnwrap(frames.first { $0.id == root.id })
        let xs = try events.map { event in
            try XCTUnwrap(frames.first { $0.id == event.id }).frame.minX
        }
        for (index, x) in xs.enumerated() {
            XCTAssertGreaterThan(x, cursor)
            cursor = x
        }
        XCTAssertGreaterThanOrEqual(xs[0], rootFrame.frame.maxX)
    }

    func testTimelineIndentsDeeperLevelsOneHorizontalGapAndCentersChildren() throws {
        let grand = MindMapNode(text: "孙")
        let child = MindMapNode(text: "子", children: [grand])
        let second = MindMapNode(text: "次")
        let root = MindMapNode(text: "轴", children: [child, second])
        let frames = timeline(MindMapDocument(title: "indent", roots: [root]))
        let childFrame = try XCTUnwrap(frames.first { $0.id == child.id })
        let grandFrame = try XCTUnwrap(frames.first { $0.id == grand.id })
        // The first event is above the spine, so its branch grows upward.
        XCTAssertEqual(childFrame.frame.minY - grandFrame.frame.maxY, LayoutMetrics().horizontalGap, accuracy: 0.001)
        XCTAssertEqual(grandFrame.frame.midX, childFrame.frame.midX, accuracy: 0.001)
    }

    func testTimelineStacksABranchOneSiblingGapApartOnOneCentreLine() throws {
        let kids = (0..<3).map { MindMapNode(text: "分支\($0)") }
        let event = MindMapNode(text: "事件", children: kids)
        let root = MindMapNode(text: "轴", children: [event])
        let frames = timeline(MindMapDocument(title: "stack", roots: [root]))
        let rows = try kids.map { kid in
            try XCTUnwrap(frames.first { $0.id == kid.id })
        }.sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertEqual(Set(rows.map(\.frame.midX)).count, 1)
        XCTAssertEqual(rows[1].frame.minY - rows[0].frame.maxY, LayoutMetrics().siblingGap, accuracy: 0.001)
        XCTAssertEqual(rows[2].frame.minY - rows[1].frame.maxY, LayoutMetrics().siblingGap, accuracy: 0.001)
        // Stacking grows away from the spine: the whole pile ends above the event.
        let eventFrame = try XCTUnwrap(frames.first { $0.id == event.id })
        XCTAssertEqual(
            eventFrame.frame.minY - rows[2].frame.maxY,
            LayoutMetrics().horizontalGap,
            accuracy: 0.001
        )
    }

    func testTimelineLinksStartOnTheSpineAndRunStraightToTheTopic() throws {
        let kid = MindMapNode(text: "分支")
        let event = MindMapNode(text: "事件", children: [kid])
        let root = MindMapNode(text: "轴", children: [event])
        let frames = timeline(MindMapDocument(title: "links", roots: [root]))
        let rootFrame = try XCTUnwrap(frames.first { $0.id == root.id })
        let spine = rootFrame.frame.midY
        let eventFrame = try XCTUnwrap(frames.first { $0.id == event.id })
        let link = try XCTUnwrap(eventFrame.link)
        // The anchor is on the axis itself, which is what makes the spine read as
        // one straight line without a second drawing primitive.
        XCTAssertEqual(link.start.y, spine, accuracy: 0.001)
        XCTAssertEqual(link.start.x, eventFrame.frame.midX, accuracy: 0.001)
        XCTAssertEqual(link.end.y, eventFrame.frame.minY, accuracy: 0.001)
        XCTAssertEqual(link.control1.x, link.start.x, accuracy: 0.001)
        XCTAssertEqual(link.control2.x, link.end.x, accuracy: 0.001)
        // Every control point shares the topic's centre line, so the spike to the
        // spine is a straight vertical, not a curve.
        XCTAssertEqual(link.point(at: 0.5).x, link.start.x, accuracy: 0.001)
        XCTAssertNil(rootFrame.link)
        XCTAssertEqual(eventFrame.parentID, root.id)

        let kidFrame = try XCTUnwrap(frames.first { $0.id == kid.id })
        let kidLink = try XCTUnwrap(kidFrame.link)
        XCTAssertEqual(kidLink.start.x, eventFrame.frame.midX, accuracy: 0.001)
        XCTAssertEqual(kidLink.start.y, eventFrame.frame.minY, accuracy: 0.001)
        XCTAssertEqual(kidFrame.parentID, event.id)
    }

    func testTimelineCollapsedTopicHidesItsSubtreeAndItsTail() {
        let event = MindMapNode(text: "事件", children: [MindMapNode(text: "分支")])
        var root = MindMapNode(text: "轴", children: [event, MindMapNode(text: "另一个")])
        root.isCollapsed = true
        let frames = timeline(MindMapDocument(title: "fold", roots: [root]))
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames.first?.id, root.id)
    }

    func testTimelinePlacesAStoredRootPointAndKeepsTheSpineOnIt() throws {
        let event = MindMapNode(text: "事件")
        let root = MindMapNode(
            text: "轴",
            position: MindMapPoint(x: 140, y: -60),
            children: [event]
        )
        let frames = timeline(MindMapDocument(title: "manual", roots: [root]))
        let rootFrame = try XCTUnwrap(frames.first { $0.id == root.id })
        let eventFrame = try XCTUnwrap(frames.first { $0.id == event.id })
        XCTAssertEqual(rootFrame.origin.x, 140, accuracy: 0.001)
        XCTAssertEqual(rootFrame.origin.y, -60, accuracy: 0.001)
        XCTAssertEqual(eventFrame.link?.start.y ?? 0, rootFrame.frame.midY, accuracy: 0.001)
        XCTAssertEqual(rootFrame.frame.midY - eventFrame.frame.maxY, LayoutMetrics().horizontalGap, accuracy: 0.001)
    }

    func testTimelineKeepsThirtyTopicsFromOverlapping() {
        let root = MindMapNode(text: "2024 复盘", children: [
            MindMapNode(text: "一月", children: (0..<3).map { MindMapNode(text: "一月的事项\($0)") }),
            MindMapNode(text: "二月", children: (0..<2).map { MindMapNode(text: "二月的事项\($0)") }),
            MindMapNode(text: "三月"),
            MindMapNode(text: "四月", children: [MindMapNode(text: "四月的事项")]),
            MindMapNode(text: "五月"),
            MindMapNode(text: "六月", children: (0..<2).map { MindMapNode(text: "六月的事项\($0)") }),
            MindMapNode(text: "七月"),
        ])
        let frames = timeline(MindMapDocument(title: "big", roots: [root]))
        XCTAssertEqual(frames.count, 16)
        assertNoOverlap(frames)

        let wide = MindMapNode(text: "全年", children: (0..<8).map { index in
            MindMapNode(text: "第\(index)季度", children: (0..<3).map { MindMapNode(text: "事项\(index)-\($0)") })
        })
        let wideFrames = timeline(MindMapDocument(title: "wide", roots: [wide]))
        XCTAssertEqual(wideFrames.count, 33)
        assertNoOverlap(wideFrames)
    }

    func testTimelineJoinsTheStructureRegistry() {
        XCTAssertEqual(LayoutKind.timeline.displayNameKey, "layout.timeline")
        XCTAssertEqual(LayoutKind.timeline.makeLayout(geometry: geometry()).kind, .timeline)
    }

    // MARK: - 鱼骨图

    func testFishboneRunsEveryRibAtFortyFiveDegreesAndAlternatesSides() throws {
        let ribs = (0..<4).map { MindMapNode(text: "原因\($0)") }
        let root = MindMapNode(text: "问题", children: ribs)
        let frames = fishbone(MindMapDocument(title: "fish", roots: [root]))
        let rootFrame = try XCTUnwrap(frames.first { $0.id == root.id })
        let spine = rootFrame.frame.midY
        for (index, rib) in ribs.enumerated() {
            let frame = try XCTUnwrap(frames.first { $0.id == rib.id })
            let rise = frame.frame.midY - spine
            // Even ribs go up, odd ribs go down.
            XCTAssertEqual(rise < 0, index % 2 == 0)
            // The head leaves the spine at 45°: the drop equals the run, and the
            // run is one gap past the largest half of the box.
            let run = LayoutMetrics().horizontalGap + max(frame.frame.width, frame.frame.height) / 2
            XCTAssertEqual(abs(rise), run, accuracy: 0.001)
            XCTAssertLessThan(abs(rise), run + 0.002)
        }
    }

    func testFishboneRunsDeeperTopicsAlongTheSameRib() throws {
        let grand = MindMapNode(text: "孙")
        let kid = MindMapNode(text: "子", children: [grand])
        let root = MindMapNode(text: "问题", children: [kid])
        let frames = fishbone(MindMapDocument(title: "rib", roots: [root]))
        let kidFrame = try XCTUnwrap(frames.first { $0.id == kid.id })
        let grandFrame = try XCTUnwrap(frames.first { $0.id == grand.id })
        XCTAssertEqual(grandFrame.frame.minX - kidFrame.frame.maxX, LayoutMetrics().horizontalGap, accuracy: 0.001)
        XCTAssertEqual(
            abs(grandFrame.frame.midY - kidFrame.frame.midY),
            grandFrame.frame.midX - kidFrame.frame.midX,
            accuracy: 0.001
        )
        // The rib keeps climbing away from the spine.
        XCTAssertLessThan(grandFrame.frame.midY, kidFrame.frame.midY)
    }

    func testFishboneGivesRibsOnOneSideTheirOwnLanes() throws {
        let ribs = (0..<4).map { index in
            MindMapNode(text: "原因\(index)", children: [MindMapNode(text: "细节\(index)")])
        }
        let root = MindMapNode(text: "问题", children: ribs)
        let frames = fishbone(MindMapDocument(title: "lanes", roots: [root]))
        let first = subtree(of: ribs[0].id, in: frames) + [try XCTUnwrap(frames.first { $0.id == ribs[0].id })]
        let third = subtree(of: ribs[2].id, in: frames) + [try XCTUnwrap(frames.first { $0.id == ribs[2].id })]
        let firstMaxX = first.map(\.frame.maxX).max() ?? 0
        let thirdMinX = third.map(\.frame.minX).min() ?? 0
        XCTAssertLessThan(firstMaxX, thirdMinX)
        XCTAssertGreaterThanOrEqual(thirdMinX - firstMaxX, LayoutMetrics().horizontalGap - 0.001)
    }

    func testFishboneRibHeadLeavesTheSpineAndTheRestLeavesTheRightEdge() throws {
        let kid = MindMapNode(text: "细节")
        let rib = MindMapNode(text: "原因", children: [kid])
        let root = MindMapNode(text: "问题", children: [rib])
        let frames = fishbone(MindMapDocument(title: "links", roots: [root]))
        let rootFrame = try XCTUnwrap(frames.first { $0.id == root.id })
        let ribFrame = try XCTUnwrap(frames.first { $0.id == rib.id })
        let head = try XCTUnwrap(ribFrame.link)
        XCTAssertEqual(head.start.y, rootFrame.frame.midY, accuracy: 0.001)
        XCTAssertEqual(head.end.x, ribFrame.frame.minX, accuracy: 0.001)
        XCTAssertEqual(head.end.y, ribFrame.frame.midY, accuracy: 0.001)
        XCTAssertNil(rootFrame.link)

        let kidFrame = try XCTUnwrap(frames.first { $0.id == kid.id })
        let link = try XCTUnwrap(kidFrame.link)
        XCTAssertEqual(link.start.x, ribFrame.frame.maxX, accuracy: 0.001)
        XCTAssertEqual(link.start.y, ribFrame.frame.midY, accuracy: 0.001)
        XCTAssertEqual(link.end.x, kidFrame.frame.minX, accuracy: 0.001)
        XCTAssertEqual(kidFrame.parentID, rib.id)
    }

    func testFishboneCollapsedTopicHidesItsSubtree() {
        let rib = MindMapNode(text: "原因", children: [MindMapNode(text: "细节")])
        var root = MindMapNode(text: "问题", children: [rib, MindMapNode(text: "另一个")])
        root.isCollapsed = true
        let frames = fishbone(MindMapDocument(title: "fold", roots: [root]))
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames.first?.id, root.id)
    }

    func testFishbonePlacesAStoredRootPointAndKeepsTheSpineOnIt() throws {
        let rib = MindMapNode(text: "原因")
        let root = MindMapNode(
            text: "问题",
            position: MindMapPoint(x: 70, y: 25),
            children: [rib]
        )
        let frames = fishbone(MindMapDocument(title: "manual", roots: [root]))
        let rootFrame = try XCTUnwrap(frames.first { $0.id == root.id })
        let ribFrame = try XCTUnwrap(frames.first { $0.id == rib.id })
        XCTAssertEqual(rootFrame.origin.x, 70, accuracy: 0.001)
        XCTAssertEqual(rootFrame.origin.y, 25, accuracy: 0.001)
        XCTAssertEqual(ribFrame.link?.start.y ?? 0, rootFrame.frame.midY, accuracy: 0.001)
    }

    func testFishboneKeepsThirtyOneTopicsFromOverlapping() {
        let root = MindMapNode(text: "上线失败", children: (0..<6).map { index in
            MindMapNode(
                text: "原因\(index)",
                children: (0..<4).map { MindMapNode(text: "细节\(index)-\($0)") }
            )
        })
        let frames = fishbone(MindMapDocument(title: "big", roots: [root]))
        XCTAssertEqual(frames.count, 31)
        assertNoOverlap(frames)
    }

    func testFishboneJoinsTheStructureRegistry() {
        XCTAssertEqual(LayoutKind.fishbone.displayNameKey, "layout.fishbone")
        XCTAssertEqual(LayoutKind.fishbone.makeLayout(geometry: geometry()).kind, .fishbone)
    }

    // MARK: - 树型表格

    func testTreeTableGivesEveryDepthItsOwnAlignedColumn() throws {
        let grand = MindMapNode(text: "孙")
        let child = MindMapNode(text: "子", children: [grand])
        let sibling = MindMapNode(text: "另一个子")
        let root = MindMapNode(text: "根", children: [child, sibling])
        let frames = treeTable(MindMapDocument(title: "table", roots: [root]))
        let gap = LayoutMetrics().horizontalGap
        let rootFrame = try XCTUnwrap(frames.first { $0.id == root.id })
        let childFrame = try XCTUnwrap(frames.first { $0.id == child.id })
        let siblingFrame = try XCTUnwrap(frames.first { $0.id == sibling.id })
        let grandFrame = try XCTUnwrap(frames.first { $0.id == grand.id })
        XCTAssertEqual(rootFrame.frame.minX, 0, accuracy: 0.001)
        // One column per depth: every topic of a level shares one left edge.
        XCTAssertEqual(childFrame.frame.minX, siblingFrame.frame.minX, accuracy: 0.001)
        // And column d + 1 starts one gap past the widest topic of column d.
        let widestDepth1 = max(childFrame.frame.maxX, siblingFrame.frame.maxX)
        XCTAssertEqual(grandFrame.frame.minX - widestDepth1, gap, accuracy: 0.001)
        let widestDepth0 = frames.filter { $0.depth == 0 }.map(\.frame.maxX).max() ?? 0
        XCTAssertEqual(childFrame.frame.minX - widestDepth0, gap, accuracy: 0.001)
    }

    func testTreeTableStacksRowsOneSiblingGapApartAndCentresTheParent() throws {
        let kids = (0..<3).map { index in
            MindMapNode(text: "行\(index)", children: (0...index).map { MindMapNode(text: "格\($0)") })
        }
        let root = MindMapNode(text: "根", children: kids)
        let frames = treeTable(MindMapDocument(title: "rows", roots: [root]))
        let rootFrame = try XCTUnwrap(frames.first { $0.id == root.id })
        let rows = try kids.map { kid in
            try XCTUnwrap(frames.first { $0.id == kid.id })
        }.sorted { $0.frame.minY < $1.frame.minY }
        // Rows are one siblingGap apart, measured from the row the topic sits in.
        let cells = try kids.flatMap { kid in
            subtree(of: kid.id, in: frames)
        }.sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertFalse(cells.isEmpty)
        for pair in zip(rows, rows.dropFirst()) {
            XCTAssertGreaterThan(pair.1.frame.minY, pair.0.frame.maxY)
        }
        // The root is centred on the band of its rows.
        let top = rows[0].frame.minY
        let bandTop = min(top, cells[0].frame.minY)
        let bottom = max(rows[2].frame.maxY, cells.map(\.frame.maxY).max() ?? 0)
        XCTAssertEqual(rootFrame.frame.midY, (bandTop + bottom) / 2, accuracy: 1)

        // Leaf-only rows are exactly one siblingGap apart.
        let leaves = (0..<3).map { MindMapNode(text: "格\($0)") }
        let leafFrames = treeTable(
            MindMapDocument(title: "leaves", roots: [MindMapNode(text: "根", children: leaves)])
        )
        let leafRows = try leaves.map { leaf in
            try XCTUnwrap(leafFrames.first { $0.id == leaf.id })
        }.sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertEqual(leafRows[1].frame.minY - leafRows[0].frame.maxY, LayoutMetrics().siblingGap, accuracy: 0.001)
        XCTAssertEqual(leafRows[2].frame.minY - leafRows[1].frame.maxY, LayoutMetrics().siblingGap, accuracy: 0.001)
    }

    func testTreeTableGrowsARowForAWrappedTitle() throws {
        let short = MindMapNode(text: "短")
        let long = MindMapNode(text: String(repeating: "很长的一段主题文字", count: 6))
        let shortFrames = treeTable(
            MindMapDocument(title: "short", roots: [MindMapNode(text: "根", children: [short])])
        )
        let longFrames = treeTable(
            MindMapDocument(title: "long", roots: [MindMapNode(text: "根", children: [long])])
        )
        let shortFrame = try XCTUnwrap(shortFrames.first { $0.id == short.id })
        let longFrame = try XCTUnwrap(longFrames.first { $0.id == long.id })
        // A wrapped title is taller, and the row grew with it.
        XCTAssertGreaterThan(longFrame.frame.height, shortFrame.frame.height)

        // The height is the one `LayoutGeometry` measured, not a second formula.
        let geometry = LayoutGeometry(
            cache: TextMeasurementCache(),
            metrics: LayoutMetrics(),
            appearance: .standard
        )
        var heights: [Int: CGFloat] = [:]
        geometry.collectHeights(long, depth: 1, into: &heights)
        let measured = geometry.size(long, depth: 1, heights: heights)
        XCTAssertEqual(longFrame.frame.height, measured.height, accuracy: 0.001)
        XCTAssertGreaterThan(longFrame.frame.height, LayoutMetrics().level2FontSize)
        assertNoOverlap(longFrames)
    }

    func testTreeTableLinksLeaveTheRightEdgeIntoTheNextColumn() throws {
        let kid = MindMapNode(text: "子")
        let root = MindMapNode(text: "根", children: [kid])
        let frames = treeTable(MindMapDocument(title: "links", roots: [root]))
        let rootFrame = try XCTUnwrap(frames.first { $0.id == root.id })
        let kidFrame = try XCTUnwrap(frames.first { $0.id == kid.id })
        let link = try XCTUnwrap(kidFrame.link)
        XCTAssertEqual(link.start.x, rootFrame.frame.maxX, accuracy: 0.001)
        XCTAssertEqual(link.start.y, rootFrame.frame.midY, accuracy: 0.001)
        XCTAssertEqual(link.end.x, kidFrame.frame.minX, accuracy: 0.001)
        XCTAssertEqual(link.end.y, kidFrame.frame.midY, accuracy: 0.001)
        XCTAssertNil(rootFrame.link)
        XCTAssertEqual(kidFrame.parentID, root.id)
    }

    func testTreeTableCollapsedTopicHidesItsSubtree() {
        let child = MindMapNode(text: "子", children: [MindMapNode(text: "孙")])
        var root = MindMapNode(text: "根", children: [child])
        root.isCollapsed = true
        let frames = treeTable(MindMapDocument(title: "fold", roots: [root]))
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames.first?.id, root.id)
    }

    func testTreeTablePlacesAStoredRootPoint() throws {
        let child = MindMapNode(text: "子")
        let root = MindMapNode(
            text: "根",
            position: MindMapPoint(x: 32, y: 48),
            children: [child]
        )
        let frames = treeTable(MindMapDocument(title: "manual", roots: [root]))
        let rootFrame = try XCTUnwrap(frames.first { $0.id == root.id })
        let childFrame = try XCTUnwrap(frames.first { $0.id == child.id })
        XCTAssertEqual(rootFrame.frame.minX, 32, accuracy: 0.001)
        XCTAssertEqual(childFrame.frame.minX, rootFrame.frame.maxX + LayoutMetrics().horizontalGap, accuracy: 0.001)
    }

    func testTreeTableKeepsThirtyThreeTopicsFromOverlapping() {
        let root = MindMapNode(text: "知识库", children: (0..<4).map { section in
            MindMapNode(
                text: "章节\(section)",
                children: (0..<3).map { topic in
                    MindMapNode(
                        text: "小节\(section)-\(topic)",
                        children: (0..<2).map { MindMapNode(text: "要点\(section)-\(topic)-\($0)") }
                    )
                }
            )
        })
        let frames = treeTable(MindMapDocument(title: "big", roots: [root]))
        XCTAssertEqual(frames.count, 41)
        assertNoOverlap(frames)
        // Every depth keeps one left edge even at this size.
        let depths = Dictionary(grouping: frames, by: \.depth)
        for (_, group) in depths {
            XCTAssertEqual(Set(group.map { ($0.frame.minX * 100).rounded() / 100 }).count, 1)
        }
    }

    func testTreeTableJoinsTheStructureRegistry() {
        XCTAssertEqual(LayoutKind.treeTable.displayNameKey, "layout.treeTable")
        XCTAssertEqual(LayoutKind.treeTable.makeLayout(geometry: geometry()).kind, .treeTable)
    }

    // MARK: - Helpers

    private func treeTable(_ document: MindMapDocument) -> [NodeFrame] {
        LayoutEngine(kind: .treeTable).layout(document)
    }

    private func fishbone(_ document: MindMapDocument) -> [NodeFrame] {
        LayoutEngine(kind: .fishbone).layout(document)
    }

    private func subtree(of id: UUID, in frames: [NodeFrame]) -> [NodeFrame] {
        var collected: [NodeFrame] = []
        var frontier = [id]
        while let current = frontier.popLast() {
            let kids = frames.filter { $0.parentID == current }
            collected.append(contentsOf: kids)
            frontier.append(contentsOf: kids.map(\.id))
        }
        return collected
    }

    private func geometry() -> LayoutGeometry {
        LayoutGeometry(
            cache: TextMeasurementCache(),
            metrics: LayoutMetrics(),
            appearance: .standard
        )
    }

    private func assertNoOverlap(
        _ frames: [NodeFrame],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for left in frames.indices {
            for right in frames.indices where right > left {
                let hit = frames[left].frame.intersection(frames[right].frame)
                XCTAssertFalse(
                    hit.width > 0.5 && hit.height > 0.5,
                    "\(frames[left].text) overlaps \(frames[right].text)",
                    file: file,
                    line: line
                )
            }
        }
    }
}
