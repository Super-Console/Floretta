import FlorettaCore
import XCTest

/// Contract for the hover add handles: the handles are drawn outside the topic
/// box, so the hover test has to reach past the box, keep the hover for a moment
/// after a miss, and offer only the directions the structure can grow in.
final class AddHandleTests: XCTestCase {
    // MARK: - hover reach

    func testHoverReachCoversTheWholeHandleGlyph() {
        XCTAssertGreaterThanOrEqual(
            AddHandleGeometry.hoverInflate,
            AddHandleGeometry.spacing + AddHandleGeometry.buttonSide / 2,
            "The ring has to reach the far edge of the glyph or that edge is dead."
        )
        XCTAssertGreaterThanOrEqual(AddHandleGeometry.hoverGraceMilliseconds, 150)
        XCTAssertLessThanOrEqual(AddHandleGeometry.hoverGraceMilliseconds, 250)
    }

    func testHoverRingIsTheViewReachConvertedToCanvasUnits() {
        XCTAssertEqual(AddHandleGeometry.canvasInflate(scale: 1), AddHandleGeometry.hoverInflate)
        XCTAssertEqual(
            AddHandleGeometry.canvasInflate(scale: 2),
            AddHandleGeometry.hoverInflate / 2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            AddHandleGeometry.canvasInflate(scale: 0.5),
            AddHandleGeometry.hoverInflate * 2,
            accuracy: 0.001
        )
        // A broken zoom must not collapse the region to zero.
        XCTAssertEqual(AddHandleGeometry.canvasInflate(scale: 0), AddHandleGeometry.hoverInflate)
        XCTAssertEqual(AddHandleGeometry.canvasInflate(scale: .nan), AddHandleGeometry.hoverInflate)
    }

    func testHandleSeatsSitOneSpacingOutsideTheBoxOnEverySide() {
        let rect = CGRect(x: 100, y: 40, width: 60, height: 30)
        XCTAssertEqual(AddHandleGeometry.handleCenter(.up, in: rect), CGPoint(x: 130, y: 22))
        XCTAssertEqual(AddHandleGeometry.handleCenter(.down, in: rect), CGPoint(x: 130, y: 88))
        XCTAssertEqual(AddHandleGeometry.handleCenter(.left, in: rect), CGPoint(x: 82, y: 55))
        XCTAssertEqual(AddHandleGeometry.handleCenter(.right, in: rect), CGPoint(x: 178, y: 55))
    }

    /// The regression: with an exact-box hit test the seat is a miss, the hover
    /// clears, and the handle is gone before the pointer arrives.
    func testEveryHandleSeatHitsTheTopicThroughTheRing() {
        let id = UUID()
        let rect = CGRect(x: 0, y: 0, width: 120, height: 40)
        let boxes = [(id: id, rect: rect)]
        for direction in CanvasDirection.allCases {
            let seat = AddHandleGeometry.handleCenter(direction, in: rect)
            XCTAssertFalse(rect.contains(seat), "The seat is outside the box: that is the bug.")
            XCTAssertEqual(
                NodeHitRegion.nodeID(at: seat, inflate: AddHandleGeometry.hoverInflate, in: boxes),
                id,
                "\(direction) seat has to keep the topic hovered."
            )
        }
    }

    func testPointsPastTheRingMiss() {
        let id = UUID()
        let rect = CGRect(x: 0, y: 0, width: 120, height: 40)
        let boxes = [(id: id, rect: rect)]
        let past = AddHandleGeometry.hoverInflate + 0.5
        XCTAssertNil(NodeHitRegion.nodeID(at: CGPoint(x: rect.maxX + past, y: rect.midY), inflate: AddHandleGeometry.hoverInflate, in: boxes))
        XCTAssertNil(NodeHitRegion.nodeID(at: CGPoint(x: rect.midX, y: rect.minY - past), inflate: AddHandleGeometry.hoverInflate, in: boxes))
        XCTAssertNil(NodeHitRegion.nodeID(at: CGPoint(x: rect.midX, y: rect.maxY + past), inflate: AddHandleGeometry.hoverInflate, in: boxes))
        XCTAssertNil(NodeHitRegion.nodeID(at: CGPoint(x: rect.minX - past, y: rect.midY), inflate: AddHandleGeometry.hoverInflate, in: boxes))
        // At zoom 0 the ring collapses, so only the box itself is hovered.
        XCTAssertNil(NodeHitRegion.nodeID(at: CGPoint(x: rect.maxX + 2, y: rect.midY), inflate: 0, in: boxes))
    }

    func testTheBoxItselfWinsOverAnotherTopicRing() {
        let first = UUID()
        let second = UUID()
        let boxes = [
            (id: first, rect: CGRect(x: 0, y: 0, width: 100, height: 40)),
            (id: second, rect: CGRect(x: 140, y: 0, width: 100, height: 40)),
        ]
        // Inside the first box, and inside the second one's ring.
        XCTAssertEqual(NodeHitRegion.nodeID(at: CGPoint(x: 95, y: 20), inflate: 28, in: boxes), first)
        // In the second box, and inside the first one's ring.
        XCTAssertEqual(NodeHitRegion.nodeID(at: CGPoint(x: 145, y: 20), inflate: 28, in: boxes), second)
    }

    func testOverlappingRingsPickTheNearestTopicAndALaterFrameOnATie() {
        let first = UUID()
        let second = UUID()
        let boxes = [
            (id: first, rect: CGRect(x: 0, y: 0, width: 100, height: 40)),
            (id: second, rect: CGRect(x: 140, y: 0, width: 100, height: 40)),
        ]
        // 15 from the first, 25 from the second.
        XCTAssertEqual(NodeHitRegion.nodeID(at: CGPoint(x: 115, y: 20), inflate: 28, in: boxes), first)
        // 25 from the first, 15 from the second.
        XCTAssertEqual(NodeHitRegion.nodeID(at: CGPoint(x: 125, y: 20), inflate: 28, in: boxes), second)
        // 20 from both: the later frame is painted on top, so it wins.
        XCTAssertEqual(NodeHitRegion.nodeID(at: CGPoint(x: 120, y: 20), inflate: 28, in: boxes), second)
        XCTAssertNil(NodeHitRegion.nodeID(at: CGPoint(x: 120, y: 120), inflate: 28, in: boxes))
    }

    func testDistanceToRectIsZeroInsideAndTheEdgeGapOutside() {
        let rect = CGRect(x: 10, y: 10, width: 20, height: 20)
        XCTAssertEqual(NodeHitRegion.distance(to: rect, from: CGPoint(x: 20, y: 20)), 0)
        XCTAssertEqual(NodeHitRegion.distance(to: rect, from: CGPoint(x: 36, y: 20)), 6, accuracy: 0.001)
        // 6 across, 5 down: the corner gap is the hypotenuse, not the sum.
        XCTAssertEqual(NodeHitRegion.distance(to: rect, from: CGPoint(x: 36, y: 35)), 61.squareRoot(), accuracy: 0.001)
    }

    /// The same rule through laid-out frames, which is what the canvas passes in.
    func testLaidOutFramesKeepTheHoverOnTheHandleSeat() throws {
        let root = MindMapNode(text: "中心")
        let frames = LayoutEngine().layout(MindMapDocument(title: "hover", roots: [root]))
        let rootFrame = try XCTUnwrap(frames.first { $0.id == root.id })
        let seat = AddHandleGeometry.handleCenter(.right, in: rootFrame.frame)
        let inflate = AddHandleGeometry.canvasInflate(scale: 1)
        XCTAssertEqual(NodeHitRegion.nodeID(at: seat, inflate: inflate, in: frames), root.id)
        XCTAssertNil(
            NodeHitRegion.nodeID(
                at: CGPoint(x: seat.x + inflate + 1, y: seat.y),
                inflate: inflate,
                in: frames
            )
        )
    }

    // MARK: - directions per structure

    func testEachStructureOffersOnlyTheHandlesItCanGrow() {
        XCTAssertEqual(LayoutKind.bilateral.addDirections, [.left, .right])
        XCTAssertEqual(LayoutKind.logicChart.addDirections, [.right])
        XCTAssertEqual(LayoutKind.timeline.addDirections, [.right])
        XCTAssertEqual(LayoutKind.fishbone.addDirections, [.right])
        XCTAssertEqual(LayoutKind.orgChart.addDirections, [.down])
        XCTAssertEqual(LayoutKind.treeTable.addDirections, [.down])
        XCTAssertEqual(LayoutKind.matrix.addDirections, [.down])
        for kind in LayoutKind.allCases {
            XCTAssertFalse(kind.addDirections.isEmpty, "\(kind) must offer a handle")
            XCTAssertLessThanOrEqual(kind.addDirections.count, 2, "\(kind) offers too many handles")
            XCTAssertFalse(kind.addDirections.contains(.up), "\(kind) grows upwards")
        }
    }

    func testInteractionOffersHandlesOnlyWhileATopicIsHovered() {
        var document = MindMapDocument(title: "handles", roots: [MindMapNode(text: "根")])
        var interaction = CanvasInteraction.standard
        XCTAssertTrue(interaction.addDirections(for: .bilateral).isEmpty)
        CanvasCommands.apply(.hover(document.roots[0].id), document: &document, interaction: &interaction)
        XCTAssertEqual(interaction.addDirections(for: .bilateral), [.left, .right])
        XCTAssertEqual(interaction.addDirections(for: .logicChart), [.right])
        CanvasCommands.apply(.hover(nil), document: &document, interaction: &interaction)
        XCTAssertTrue(interaction.addDirections(for: .logicChart).isEmpty)
    }

    // MARK: - direction reaches the model

    func testBilateralLeftAndRightHandlesStoreTheBranchSide() throws {
        var document = MindMapDocument(title: "双侧", roots: [MindMapNode(text: "中心")])
        var interaction = CanvasInteraction.standard
        let rootID = document.roots[0].id
        let leftID = try XCTUnwrap(CanvasCommands.apply(
            .addChild(parentID: rootID, direction: .left),
            document: &document,
            interaction: &interaction
        ))
        let rightID = try XCTUnwrap(CanvasCommands.apply(
            .addChild(parentID: rootID, direction: .right),
            document: &document,
            interaction: &interaction
        ))
        XCTAssertEqual(document.node(leftID)?.side, .left)
        XCTAssertEqual(document.node(rightID)?.side, .right)
    }

    func testOtherStructuresDoNotStoreASide() throws {
        for kind in LayoutKind.allCases where kind != .bilateral {
            var document = MindMapDocument(title: "t", roots: [MindMapNode(text: "根")], layoutKind: kind)
            var interaction = CanvasInteraction.standard
            let direction = kind.addDirections[0]
            let childID = try XCTUnwrap(CanvasCommands.apply(
                .addChild(parentID: document.roots[0].id, direction: direction),
                document: &document,
                interaction: &interaction
            ))
            XCTAssertNil(document.node(childID)?.side, "\(kind) writes no side")
        }
    }

    func testBilateralPlacesANamedSideOnThatSideOfTheRoot() throws {
        let left = MindMapNode(text: "左分支", side: .left)
        let right = MindMapNode(text: "右分支", side: .right)
        let root = MindMapNode(text: "中心", children: [left, right])
        let frames = LayoutEngine().layout(MindMapDocument(title: "sides", roots: [root]))
        let rootFrame = try XCTUnwrap(frames.first { $0.id == root.id })
        let leftFrame = try XCTUnwrap(frames.first { $0.id == left.id })
        let rightFrame = try XCTUnwrap(frames.first { $0.id == right.id })
        XCTAssertLessThanOrEqual(leftFrame.frame.maxX, rootFrame.frame.minX)
        XCTAssertGreaterThanOrEqual(rightFrame.frame.minX, rootFrame.frame.maxX)
        // The children that name no side keep the height-balanced split: first
        // right, then left, exactly as before the handles stored a side.
        XCTAssertFalse(leftFrame.frame.intersects(rightFrame.frame))
    }

    func testTopicsWithNoStoredSideKeepTheBalancedSplit() throws {
        let first = MindMapNode(text: "一")
        let second = MindMapNode(text: "二")
        let root = MindMapNode(text: "中心", children: [first, second])
        let frames = LayoutEngine().layout(MindMapDocument(title: "auto", roots: [root]))
        let rootFrame = try XCTUnwrap(frames.first { $0.id == root.id })
        let firstFrame = try XCTUnwrap(frames.first { $0.id == first.id })
        let secondFrame = try XCTUnwrap(frames.first { $0.id == second.id })
        XCTAssertGreaterThanOrEqual(firstFrame.frame.minX, rootFrame.frame.maxX)
        XCTAssertLessThanOrEqual(secondFrame.frame.maxX, rootFrame.frame.minX)
    }

    // MARK: - files

    func testOldFilesGainNoSideKeyAndASideRoundTrips() throws {
        let document = MindMapDocument(
            title: "t",
            roots: [MindMapNode(text: "root", children: [MindMapNode(text: "child")])]
        )
        let oldJSON = try XCTUnwrap(String(data: FlorettaCodec.encode(document), encoding: .utf8))
        XCTAssertFalse(oldJSON.contains("\"side\""), "A side nobody set must not reach the file.")
        let reopened = try FlorettaCodec.decode(Data(oldJSON.utf8))
        XCTAssertNil(reopened.roots[0].children[0].side)

        var sided = reopened
        var root = sided.roots[0]
        var child = root.children[0]
        child.side = .left
        root.children[0] = child
        sided.roots[0] = root
        let sidedJSON = try XCTUnwrap(String(data: FlorettaCodec.encode(sided), encoding: .utf8))
        XCTAssertTrue(sidedJSON.contains("\"side\""))
        XCTAssertEqual(try FlorettaCodec.decode(Data(sidedJSON.utf8)).roots[0].children[0].side, .left)
    }
}
