import FlorettaCore
import SwiftFlow
import XCTest
#if os(macOS)
import AppKit
#endif

@MainActor
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

    func testDraggingAFreeNodeKeepsTheStoredPoint() {
        let rootID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let freeID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        var document = MindMapDocument(title: "free", roots: [MindMapNode(id: rootID, text: "根")])
        document.addFreeNode(text: "自由", at: MindMapPoint(x: 400, y: 300), id: freeID)
        let before = CanvasPlacement.nodes(in: document)
        let rootBefore = before.first { $0.id == rootID }!
        let free = before.first { $0.id == freeID }!
        let point = CGPoint(x: free.frame.midX, y: free.frame.midY)
        XCTAssertNil(CanvasPlacement.rootID(at: point, in: document))
        XCTAssertEqual(CanvasPlacement.draggableID(at: point, in: document), freeID)
        XCTAssertNil(free.link)
        XCTAssertTrue(free.isFree)
        XCTAssertNil(free.parentID)

        var origin = free.origin
        var moved = document
        for _ in 0..<4 {
            origin.x += 25
            origin.y -= 18
            moved = CanvasPlacement.movingNode(freeID, to: origin, in: moved)
            let frame = CanvasPlacement.nodes(in: moved).first { $0.id == freeID }!
            XCTAssertEqual(frame.origin.x, origin.x, accuracy: 0.001)
            XCTAssertEqual(frame.origin.y, origin.y, accuracy: 0.001)
            XCTAssertNil(frame.link)
            XCTAssertTrue(frame.isFree)
            XCTAssertNil(frame.parentID)
        }
        let rootAfter = CanvasPlacement.nodes(in: moved).first { $0.id == rootID }!
        XCTAssertEqual(rootAfter.origin.x, rootBefore.origin.x, accuracy: 0.001)
        XCTAssertEqual(rootAfter.origin.y, rootBefore.origin.y, accuracy: 0.001)
        XCTAssertNil(moved.roots[0].position)
        XCTAssertEqual(moved.freeNodes[0].position?.x ?? -1, origin.x, accuracy: 0.001)
        XCTAssertEqual(moved.freeNodes[0].position?.y ?? -1, origin.y, accuracy: 0.001)
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

    func testFitUsesSwiftFlowViewportForBounds() {
        let content = CGRect(x: 10, y: 20, width: 100, height: 50)
        let view = CGSize(width: 400, height: 300)
        var viewport = CanvasViewport()
        viewport.fit(content: content, in: view)
        let fitted = getViewportForBounds(
            bounds: content,
            viewportSize: view,
            minZoom: CanvasViewport.minimumScale,
            maxZoom: CanvasViewport.maximumFitScale,
            padding: 48
        )
        XCTAssertEqual(viewport.scale, fitted.zoom, accuracy: 0.001)
        XCTAssertEqual(viewport.offset.x, fitted.x, accuracy: 0.001)
        XCTAssertEqual(viewport.offset.y, fitted.y, accuracy: 0.001)
    }

    func testTopmostIntersectionWins() {
        let under = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let over = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let document = MindMapDocument(
            title: "hit",
            roots: [
                MindMapNode(id: under, text: "下", position: MindMapPoint(x: 0, y: 0)),
                MindMapNode(id: over, text: "上", position: MindMapPoint(x: 20, y: 10)),
            ]
        )
        let frames = CanvasPlacement.nodes(in: document)
        let underFrame = frames.first { $0.id == under }!
        let overFrame = frames.first { $0.id == over }!
        let shared = CGPoint(x: overFrame.frame.midX, y: min(underFrame.frame.midY, overFrame.frame.midY))
        XCTAssertTrue(underFrame.frame.contains(shared))
        XCTAssertTrue(overFrame.frame.contains(shared))
        XCTAssertEqual(CanvasPlacement.nodeID(at: shared, in: document), over)
        XCTAssertEqual(CanvasPlacement.rootID(at: shared, in: document), over)
    }

    func testDotLatticeCoversEveryCornerAtZoomStopsAndStaysPhaseLocked() throws {
        let view = CGSize(width: 1400, height: 900)
        let stops: [CGFloat] = [0.5, 1, 2, 4]
        for scale in stops {
            let offset = CGPoint(x: 37.5, y: -18)
            let layout = DotLatticeLayout.make(offset: offset, scale: scale, viewSize: view)
            let lattice = try XCTUnwrap(layout)
            XCTAssertEqual(lattice.step, DotLatticeLayout.worldStep * scale, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(lattice.phase.x, 0)
            XCTAssertLessThan(lattice.phase.x, lattice.step)
            XCTAssertGreaterThanOrEqual(lattice.phase.y, 0)
            XCTAssertLessThan(lattice.phase.y, lattice.step)
            XCTAssertTrue(lattice.coversView(view), "scale \(scale) left a corner uncovered")
            let widthRemainder = lattice.fillRectInTileSpace.width.truncatingRemainder(dividingBy: lattice.step)
            XCTAssertTrue(
                abs(widthRemainder) < 0.01 || abs(widthRemainder - lattice.step) < 0.01,
                "tile fill width \(lattice.fillRectInTileSpace.width) is not a multiple of \(lattice.step)"
            )

            let shifted = try XCTUnwrap(DotLatticeLayout.make(
                offset: CGPoint(x: offset.x + lattice.step, y: offset.y + lattice.step * 3),
                scale: scale,
                viewSize: view
            ))
            XCTAssertEqual(shifted.phase.x, lattice.phase.x, accuracy: 0.001)
            XCTAssertEqual(shifted.phase.y, lattice.phase.y, accuracy: 0.001)

            let half = try XCTUnwrap(DotLatticeLayout.make(
                offset: CGPoint(x: offset.x + lattice.step / 2, y: offset.y),
                scale: scale,
                viewSize: view
            ))
            XCTAssertEqual(half.phase.x, positiveRemainder(lattice.phase.x + lattice.step / 2, modulo: lattice.step), accuracy: 0.001)
            XCTAssertNotEqual(half.phase.x, lattice.phase.x)
        }

        let wide = CGSize(width: 3200, height: 1800)
        let zoomedOut = try XCTUnwrap(DotLatticeLayout.make(offset: CGPoint(x: -5, y: 800), scale: 0.5, viewSize: wide))
        XCTAssertTrue(zoomedOut.coversView(wide))
        XCTAssertEqual(zoomedOut.step, 16, accuracy: 0.001)
    }

    func testDetailDropsTextWhenZoomedOutAndKeepsFullStyleAtFourHundredPercent() {
        XCTAssertEqual(CanvasDetail.level(scale: 0.5, onScreenHeight: 6), .far)
        XCTAssertEqual(CanvasDetail.level(scale: 0.5, onScreenHeight: 20), .mid)
        XCTAssertFalse(CanvasDetail.far.drawsText)
        XCTAssertFalse(CanvasDetail.far.drawsShadow)
        XCTAssertFalse(CanvasDetail.far.drawsSelectionHandles)
        XCTAssertTrue(CanvasDetail.mid.drawsText)
        XCTAssertFalse(CanvasDetail.mid.drawsShadow)
        XCTAssertFalse(CanvasDetail.mid.drawsFineBorder)
        XCTAssertEqual(CanvasDetail.level(scale: 1, onScreenHeight: 24), .near)
        XCTAssertEqual(CanvasDetail.level(scale: 4, onScreenHeight: 40), .near)
        XCTAssertTrue(CanvasDetail.near.drawsText)
        XCTAssertTrue(CanvasDetail.near.drawsShadow)
        XCTAssertTrue(CanvasDetail.near.drawsFineBorder)
        XCTAssertTrue(CanvasDetail.near.drawsSelectionHandles)
    }

    func testViewportCullingUsesSwiftFlowIntersectionAndDropsOffscreenNodes() {
        var viewport = CanvasViewport()
        viewport.flow = Viewport(x: 0, y: 0, zoom: 4)
        let visible = viewport.canvasRect(in: CGSize(width: 800, height: 600))
        XCTAssertEqual(visible.width, 200, accuracy: 0.001)
        XCTAssertEqual(visible.height, 150, accuracy: 0.001)

        let onScreen = sampleFrame(id: UUID(), origin: CGPoint(x: 20, y: 20))
        let offScreen = sampleFrame(id: UUID(), origin: CGPoint(x: 5_000, y: 5_000))
        var many: [NodeFrame] = [onScreen, offScreen]
        for index in 0..<998 {
            many.append(sampleFrame(id: UUID(), origin: CGPoint(x: 10_000 + CGFloat(index), y: 10_000)))
        }
        XCTAssertEqual(many.count, 1000)
        let drawn = CanvasPlacement.frames(many, intersectingCanvas: visible.insetBy(dx: -48, dy: -48))
        XCTAssertEqual(drawn.map(\.id), [onScreen.id])
        XCTAssertLessThan(drawn.count, 50)

        let long = LinkCurve(
            start: CGPoint(x: 0, y: 0),
            control1: CGPoint(x: 400, y: 0),
            control2: CGPoint(x: 800, y: 0),
            end: CGPoint(x: 900, y: 0),
            lineWidth: 1.5,
            color: .black
        )
        XCTAssertTrue(CanvasDrawPolicy.useStraightLink(nodeCount: 10, link: long))
        let short = LinkCurve(
            start: .zero,
            control1: CGPoint(x: 40, y: 10),
            control2: CGPoint(x: 80, y: 10),
            end: CGPoint(x: 120, y: 0),
            lineWidth: 1.5,
            color: .black
        )
        XCTAssertFalse(CanvasDrawPolicy.useStraightLink(nodeCount: 12, link: short))
        XCTAssertTrue(CanvasDrawPolicy.useStraightLink(nodeCount: 1000, link: short))
    }

    func testOnScreenFontSizeMatchesTheEditFieldAndStaysInsideTheStops() {
        XCTAssertEqual(CanvasViewport.minimumScale, ZoomStop.fifty.scale)
        XCTAssertEqual(CanvasViewport.maximumScale, ZoomStop.fourHundred.scale)
        XCTAssertEqual(CanvasViewport.clampScale(0.1), 0.5)
        XCTAssertEqual(CanvasViewport.clampScale(0.5), 0.5)
        XCTAssertEqual(CanvasViewport.clampScale(4), 4)
        XCTAssertEqual(CanvasViewport.clampScale(9), 4)
        XCTAssertEqual(CanvasViewport.clampScale(.nan), 1)

        let atFifty = CanvasTextScale.onScreenPointSize(fontSize: 30, scale: 0.5)
        let atFourHundred = CanvasTextScale.onScreenPointSize(fontSize: 16, scale: 4)
        XCTAssertEqual(atFifty, 15)
        XCTAssertEqual(atFourHundred, 64)
        XCTAssertEqual(CanvasTextScale.onScreenPointSize(fontSize: 20, scale: 0.2), 10)
        XCTAssertEqual(CanvasTextLOD.level(onScreenPointSize: atFifty), .full)
        XCTAssertEqual(CanvasTextLOD.level(onScreenPointSize: atFourHundred), .full)
        XCTAssertEqual(CanvasTextLOD.level(onScreenPointSize: 8), .blocks)
        XCTAssertFalse(CanvasTextLOD.blocks.drawsTitle)
        XCTAssertTrue(CanvasTextLOD.title.drawsTitle)
    }

    func testContentBoundsIncludeTheRelationshipLine() throws {
        let root = UUID()
        let left = UUID()
        let right = UUID()
        let link = UUID()
        var document = MindMapDocument(
            title: "关系",
            roots: [
                MindMapNode(
                    id: root,
                    text: "根",
                    children: [
                        MindMapNode(id: left, text: "左支"),
                        MindMapNode(id: right, text: "右支"),
                    ]
                ),
            ]
        )
        let bare = try XCTUnwrap(CanvasPlacement.contentBounds(in: document, includingStickies: false))
        _ = document.linkTopics(from: left, to: right, title: "对照", id: link)
        let line = try XCTUnwrap(
            RelationshipGeometry.lines(in: document, frames: CanvasPlacement.nodes(in: document)).first
        )
        let bounds = try XCTUnwrap(CanvasPlacement.contentBounds(in: document, includingStickies: false))
        XCTAssertTrue(bounds.contains(line.curve.start))
        XCTAssertTrue(bounds.contains(line.curve.end))
        XCTAssertTrue(bounds.contains(line.curveLabel))
        XCTAssertTrue(bounds.contains(line.chordLabel))
        XCTAssertGreaterThanOrEqual(bounds.width + 0.01, bare.width)
        XCTAssertGreaterThanOrEqual(bounds.height + 0.01, bare.height)
        XCTAssertFalse(CanvasPlacement.nodes(in: document).contains { $0.id == link })
    }

    func testEditModeKeepsTheNodeFrameWhenTextFits() throws {
        let node = CGRect(x: 40, y: 80, width: 72, height: 32)
        XCTAssertEqual(NodeEditChrome.editorFrame(node: node, compositionWidth: 0), node)
        let wider = NodeEditChrome.editorFrame(node: node, compositionWidth: 140)
        XCTAssertEqual(wider.width, 140, accuracy: 0.001)
        XCTAssertEqual(wider.height, node.height, accuracy: 0.001)
        XCTAssertEqual(wider.midX, node.midX, accuracy: 0.001)
        XCTAssertEqual(wider.minY, node.minY, accuracy: 0.001)
        XCTAssertFalse(NodeEditChrome.showsSelectionHandles(editing: true))
        XCTAssertTrue(NodeEditChrome.showsSelectionHandles(editing: false))
        XCTAssertEqual(NodeEditChrome.selectionStrokeWidth, 2)

        let fitted = try XCTUnwrap(LayoutEngine().layout(NodeEditChrome.sampleDocument(clock: FoundationClock())).first)
        XCTAssertLessThan(fitted.size.width, 88)
        XCTAssertEqual(NodeEditChrome.hex(fitted.fill), "#800020")
        XCTAssertEqual(NodeEditChrome.editorFrame(node: fitted.frame, compositionWidth: 0), fitted.frame)
        XCTAssertEqual(NodeEditChrome.probeIdentifier(editing: false, fill: fitted.fill), "canvas.node.chrome.idle.fill-800020")
        XCTAssertEqual(NodeEditChrome.probeIdentifier(editing: true, fill: fitted.fill), "canvas.node.chrome.edit.fill-800020")
    }

    #if os(macOS)
    func testEditingProbeIdentifierLeavesTextViewContentUntouched() {
        let view = NSTextView(frame: CGRect(x: 0, y: 0, width: 263, height: 125))
        view.string = "user text"
        let identifier = NodeEditChrome.probeIdentifier(
            editing: true,
            fill: BranchColor(red: 128 / 255, green: 0, blue: 32 / 255)
        )

        view.setAccessibilityIdentifier(identifier)

        XCTAssertEqual(view.string, "user text")
    }
    #endif

    func testLiveOriginMovesOnlyThatFrameAndLeavesTheDocumentAlone() {
        let freeID = UUID()
        let otherID = UUID()
        let frames = [
            sampleFrame(id: otherID, origin: CGPoint(x: 10, y: 20)),
            sampleFrame(id: freeID, origin: CGPoint(x: 40, y: 80)),
        ]
        let moved = CanvasPlacement.applyingLiveOrigin(frames, id: freeID, origin: CGPoint(x: 100, y: 60))
        XCTAssertEqual(moved.first { $0.id == freeID }?.origin, CGPoint(x: 100, y: 60))
        XCTAssertEqual(moved.first { $0.id == otherID }?.origin, CGPoint(x: 10, y: 20))
        XCTAssertEqual(CanvasPlacement.applyingLiveOrigin(frames, id: UUID(), origin: CGPoint(x: 1, y: 1)), frames)
    }

    func testLayoutCacheStaysPutWhileAPetalWouldBeSampling() {
        let root = MindMapNode(text: "根", children: [MindMapNode(text: "甲"), MindMapNode(text: "乙")])
        let document = MindMapDocument(title: "cache", roots: [root])
        let cache = LaidOutFrames()
        let first = cache.frames(for: document, scheme: .light)
        XCTAssertEqual(cache.layoutPassCount, 1)
        for _ in 0..<60 {
            let again = cache.frames(for: document, scheme: .light)
            XCTAssertEqual(again.map(\.id), first.map(\.id))
        }
        XCTAssertEqual(cache.layoutPassCount, 1, "petal frames must reuse the layout, not measure every sample")

        var folded = document
        folded.mutateNode(root.id) { $0.isCollapsed = true }
        _ = cache.frames(for: folded, scheme: .light)
        XCTAssertEqual(cache.layoutPassCount, 2)
        for _ in 0..<60 {
            _ = cache.frames(for: folded, scheme: .light)
        }
        XCTAssertEqual(cache.layoutPassCount, 2)
    }

    private func sampleFrame(id: UUID, origin: CGPoint) -> NodeFrame {
        NodeFrame(
            id: id,
            text: "n",
            origin: origin,
            size: CGSize(width: 36, height: 22),
            depth: 0,
            fontSize: 16,
            isRoot: true,
            parentID: nil,
            fill: .white,
            border: .black,
            textColor: .black,
            cornerRadius: 8
        )
    }
}

final class LineBreakTests: XCTestCase {
    private let zh80 = String(repeating: "春眠不觉晓处处闻啼鸟夜来风雨声花落知多少", count: 4)
    private let longWord = "supercalifragilisticexpialidocious"
    private let metrics = CoreTextFontMetrics()

    func testLongChineseWrapsInsideMaxWidthWithoutOverflow() {
        let measured = metrics.measure(text: zh80, fontName: "Helvetica", fontSize: 20, maxWidth: 240)
        XCTAssertLessThanOrEqual(measured.width, 241)
        XCTAssertGreaterThan(measured.height, 40, "80 Chinese characters must wrap to more than one line")
        let lines = NodeTextTypography.lineStrings(zh80, fontSize: 20, width: 240)
        XCTAssertGreaterThanOrEqual(lines.count, 3)
        XCTAssertFalse(lines.contains(where: { $0.isEmpty }))
    }

    func testUnbrokenEnglishWordSplitsInsteadOfOverflowing() {
        let natural = metrics.measure(text: longWord, fontName: "Helvetica", fontSize: 20, maxWidth: nil)
        XCTAssertGreaterThan(natural.width, 240)
        let measured = metrics.measure(text: longWord, fontName: "Helvetica", fontSize: 20, maxWidth: 240)
        XCTAssertLessThanOrEqual(measured.width, 241)
        XCTAssertGreaterThan(measured.height, natural.height * 0.8)
        let lines = NodeTextTypography.lineStrings(longWord, fontSize: 20, width: 240)
        XCTAssertGreaterThanOrEqual(lines.count, 2)
        XCTAssertEqual(lines.joined().replacingOccurrences(of: "\n", with: ""), longWord)
    }

    func testMixedChineseAndUnbrokenEnglishWrapsWithoutDroppingCharacters() {
        let text = "中文说明 supercalifragilisticexpialidocious 继续无空格的中文内容"
        let measured = metrics.measure(text: text, fontName: "Helvetica", fontSize: 20, maxWidth: 240)
        let lines = NodeTextTypography.lineStrings(text, fontSize: 20, width: 240)
        XCTAssertLessThanOrEqual(measured.width, 241)
        XCTAssertGreaterThan(measured.height, 40)
        XCTAssertGreaterThan(lines.count, 1)
        XCTAssertEqual(lines.joined(), text)
        XCTAssertFalse(lines.contains(where: \.isEmpty))
    }

    func testManualNewlinesAreKeptAsSeparateLines() {
        let text = "第一行手动换行\n第二行还在"
        let measured = metrics.measure(text: text, fontName: "Helvetica", fontSize: 20, maxWidth: 240)
        let single = metrics.measure(text: "第一行手动换行第二行还在", fontName: "Helvetica", fontSize: 20, maxWidth: 240)
        XCTAssertGreaterThan(measured.height, single.height)
        let lines = NodeTextTypography.lineStrings(text, fontSize: 20, width: 240)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("第一行"))
        XCTAssertTrue(lines[1].contains("第二行"))
    }

    func testLineBreaksStayStableAcrossZoom() {
        let base = NodeTextTypography.lineStrings(zh80, fontSize: 20, width: 240)
        let half = NodeTextTypography.lineStrings(zh80, fontSize: 10, width: 120)
        let double = NodeTextTypography.lineStrings(zh80, fontSize: 40, width: 480)
        XCTAssertEqual(half, base)
        XCTAssertEqual(double, base)
    }

    func testEnterAndShiftEnterAreInsertedAtTheCaretByTheTextView() {
        let shiftEnter = KeyEvent(key: .enter, modifiers: .shift, mode: .edit, isComposing: false)
        let enter = KeyEvent(key: .enter, modifiers: [], mode: .edit, isComposing: false)
        let commandEnter = KeyEvent(key: .enter, modifiers: .command, mode: .edit, isComposing: false)
        XCTAssertTrue(NodeEditLineBreak.textViewInsertsLine(for: shiftEnter))
        XCTAssertTrue(NodeEditLineBreak.textViewInsertsLine(for: enter))
        XCTAssertFalse(NodeEditLineBreak.textViewInsertsLine(for: commandEnter))
        XCTAssertEqual(KeyboardCommandMapper.map(shiftEnter), .insertNewline)
        XCTAssertEqual(KeyboardCommandMapper.map(enter), .insertNewline)
        XCTAssertNotEqual(KeyboardCommandMapper.map(enter), .createSibling)
    }

    func testLayoutCacheDoesNotGrowPastMaxTextWidthForLongTitles() {
        let cache = TextMeasurementCache(metrics: CoreTextFontMetrics())
        let size = cache.size(text: zh80, fontSize: 20, maxWidth: 240)
        XCTAssertLessThanOrEqual(size.width, 264) // maxWidth + 24 padding
        XCTAssertGreaterThan(size.height, 48)
    }
}
