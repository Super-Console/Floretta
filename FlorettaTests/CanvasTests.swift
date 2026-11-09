import XCTest

final class CanvasTests: XCTestCase {
    func testPanAndZoomKeepThePointerAnchor() {
        var viewport = CanvasViewport()
        viewport.pan(by: CGSize(width: 10, height: -4))
        XCTAssertEqual(viewport.offset.x, 10, accuracy: 0.001)
        XCTAssertEqual(viewport.offset.y, -4, accuracy: 0.001)

        let anchor = CGPoint(x: 100, y: 80)
        let canvasBefore = viewport.canvasPoint(fromView: anchor)
        viewport.zoom(by: 2, around: anchor)
        let viewAfter = viewport.viewPoint(fromCanvas: canvasBefore)
        XCTAssertEqual(viewAfter.x, anchor.x, accuracy: 0.001)
        XCTAssertEqual(viewAfter.y, anchor.y, accuracy: 0.001)
        XCTAssertEqual(viewport.scale, 2, accuracy: 0.001)
    }

    func testCommandScrollZoomsAndPlainScrollPans() {
        var viewport = CanvasViewport()
        viewport.applyScroll(
            delta: CGSize(width: 0, height: 40),
            around: CGPoint(x: 20, y: 20),
            command: false
        )
        XCTAssertEqual(viewport.offset.y, 40, accuracy: 0.001)
        XCTAssertEqual(viewport.scale, 1, accuracy: 0.001)

        let before = viewport.scale
        viewport.applyScroll(
            delta: CGSize(width: 0, height: 100),
            around: CGPoint(x: 20, y: 20),
            command: true
        )
        XCTAssertGreaterThan(viewport.scale, before)
    }

    func testFitPlacesContentInsideTheView() {
        let root = MindMapNode(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            text: "根",
            position: MindMapPoint(x: 100, y: 50)
        )
        let document = MindMapDocument(title: "fit", roots: [root])
        let bounds = CanvasPlacement.contentBounds(in: document)!
        var viewport = CanvasViewport()
        let view = CGSize(width: 400, height: 300)
        viewport.fit(content: bounds, in: view)
        let drawn = viewport.viewRect(fromCanvas: bounds)
        XCTAssertGreaterThanOrEqual(drawn.minX, 47)
        XCTAssertGreaterThanOrEqual(drawn.minY, 47)
        XCTAssertLessThanOrEqual(drawn.maxX, view.width - 47)
        XCTAssertLessThanOrEqual(drawn.maxY, view.height - 47)
    }

    func testDraggingARootStoresPositionAndSkipsThatBranch() {
        let childID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let rootID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let child = MindMapNode(id: childID, text: "子")
        let root = MindMapNode(id: rootID, text: "根", children: [child])
        let document = MindMapDocument(title: "drag", roots: [root])

        let rootFrame = CanvasPlacement.nodes(in: document).first { $0.id == rootID }!.frame
        XCTAssertEqual(CanvasPlacement.rootID(at: CGPoint(x: rootFrame.midX, y: rootFrame.midY), in: document), rootID)
        let childFrame = CanvasPlacement.nodes(in: document).first { $0.id == childID }!.frame
        XCTAssertNil(CanvasPlacement.rootID(at: CGPoint(x: childFrame.midX, y: childFrame.midY), in: document))

        let moved = CanvasPlacement.movingRoot(rootID, to: CGPoint(x: 80, y: 40), in: document)
        XCTAssertEqual(moved.roots[0].position, MindMapPoint(x: 80, y: 40))
        XCTAssertNil(moved.roots[0].children[0].position)
        let placed = CanvasPlacement.nodes(in: moved)
        let movedRoot = placed.first { $0.id == rootID }!.frame
        XCTAssertNil(placed.first { $0.id == childID })
        XCTAssertEqual(movedRoot.origin.x, 80, accuracy: 0.001)
        XCTAssertEqual(movedRoot.origin.y, 40, accuracy: 0.001)
    }

    func testStoredPositionRoundTripsAndIsOmittedWhenUnset() throws {
        var root = MindMapNode(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            text: "根",
            position: MindMapPoint(x: 12.5, y: -3)
        )
        let stamped = Date(timeIntervalSince1970: 1_762_646_400)
        let document = MindMapDocument(
            title: "pos",
            createdAt: stamped,
            modifiedAt: stamped,
            roots: [root]
        )
        let decoded = try FlorettaCodec.decode(try FlorettaCodec.encode(document))
        XCTAssertEqual(decoded.roots[0].position, MindMapPoint(x: 12.5, y: -3))

        root.position = nil
        let without = MindMapDocument(
            title: "pos",
            createdAt: stamped,
            modifiedAt: stamped,
            roots: [root]
        )
        let json = try XCTUnwrap(String(data: try FlorettaCodec.encode(without), encoding: .utf8))
        XCTAssertFalse(json.contains("\"position\""))
    }
}
