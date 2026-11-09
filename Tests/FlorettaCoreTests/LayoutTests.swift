import FlorettaCore
import XCTest

final class LayoutTests: XCTestCase {
    func testSingleRootIsCenteredWithCenterStyle() {
        let engine = LayoutEngine()
        let root = MindMapNode(text: "中心")
        let frames = engine.layout(MindMapDocument(title: "one", roots: [root]))
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].frame.midX, 0, accuracy: 0.001)
        XCTAssertEqual(frames[0].frame.midY, 0, accuracy: 0.001)
        XCTAssertEqual(frames[0].fontSize, 30)
        XCTAssertEqual(frames[0].fill, .white)
        XCTAssertEqual(frames[0].border, .black)
        XCTAssertEqual(frames[0].textColor, .black)
        XCTAssertNil(frames[0].link)
        XCTAssertFalse(engine.appearance.showsShadows)
    }

    func testMultipleRootsStackWithoutOverlap() {
        let engine = LayoutEngine()
        let first = MindMapNode(text: "一", children: [MindMapNode(text: "甲")])
        let second = MindMapNode(text: "二", children: [MindMapNode(text: "乙")])
        let frames = engine.layout(MindMapDocument(title: "many", roots: [first, second]))
        let top = frames.filter { $0.parentID == nil }
        XCTAssertEqual(top.count, 2)
        XCTAssertEqual(top[0].frame.midX, 0, accuracy: 0.001)
        XCTAssertEqual(top[1].frame.midX, 0, accuracy: 0.001)
        let firstTree = frames.filter { $0.id == first.id || $0.parentID == first.id }
        let secondTree = frames.filter { $0.id == second.id || $0.parentID == second.id }
        let firstBottom = firstTree.map(\.frame.maxY).max()!
        let secondTop = secondTree.map(\.frame.minY).min()!
        XCTAssertGreaterThan(secondTop, firstBottom)
    }

    func testTwoAndThreeLevelsGrowOutward() {
        let grand = MindMapNode(text: "孙")
        let right = MindMapNode(text: "右", children: [grand])
        let left = MindMapNode(text: "左")
        let root = MindMapNode(text: "根", children: [right, left])
        let frames = LayoutEngine().layout(MindMapDocument(title: "levels", roots: [root]))
        let rootFrame = frames.first { $0.id == root.id }!
        let rightFrame = frames.first { $0.id == right.id }!
        let leftFrame = frames.first { $0.id == left.id }!
        let grandFrame = frames.first { $0.id == grand.id }!
        XCTAssertEqual(rootFrame.fontSize, 30)
        XCTAssertEqual(rightFrame.fontSize, 20)
        XCTAssertEqual(grandFrame.fontSize, 18)
        XCTAssertGreaterThan(rightFrame.frame.minX, rootFrame.frame.maxX)
        XCTAssertGreaterThan(grandFrame.frame.minX, rightFrame.frame.maxX)
        XCTAssertLessThan(leftFrame.frame.maxX, rootFrame.frame.minX)
        XCTAssertEqual(rightFrame.frame.minX - rootFrame.frame.maxX, LayoutMetrics().horizontalGap, accuracy: 0.001)
        assertNoOverlap(frames)
    }

    func testBalanceUsesSubtreeHeightInsteadOfOddEven() {
        let tall = MindMapNode(
            text: "高",
            children: (0..<6).map { MindMapNode(text: "孙\($0)") }
        )
        let shortA = MindMapNode(text: "甲")
        let shortB = MindMapNode(text: "乙")
        let root = MindMapNode(text: "根", children: [tall, shortA, shortB])
        let frames = LayoutEngine().layout(MindMapDocument(title: "balance", roots: [root]))
        let rootFrame = frames.first { $0.id == root.id }!
        let tallFrame = frames.first { $0.id == tall.id }!
        let aFrame = frames.first { $0.id == shortA.id }!
        let bFrame = frames.first { $0.id == shortB.id }!
        XCTAssertGreaterThan(tallFrame.frame.minX, rootFrame.frame.maxX)
        XCTAssertLessThan(aFrame.frame.maxX, rootFrame.frame.minX)
        XCTAssertLessThan(bFrame.frame.maxX, rootFrame.frame.minX)
        let union = frames.reduce(rootFrame.frame) { $0.union($1.frame) }
        XCTAssertEqual(rootFrame.frame.midY, union.midY, accuracy: 0.01)
    }

    func testSameLevelSharesHeightAndSiblingGapStaysConstant() {
        let short = MindMapNode(text: "短")
        let long = MindMapNode(text: "这是一段明显更长的一级主题")
        let third = MindMapNode(text: "短")
        let root = MindMapNode(text: "根", children: [short, long, third])
        let frames = LayoutEngine().layout(MindMapDocument(title: "size", roots: [root]))
        let level1 = [short, long, third].map { id in frames.first { $0.id == id.id }! }
        XCTAssertEqual(level1[0].size.height, level1[1].size.height)
        XCTAssertEqual(level1[1].size.height, level1[2].size.height)
        XCTAssertGreaterThan(level1[1].size.width, level1[0].size.width)
        let right = level1.filter { $0.frame.minX > frames[0].frame.maxX }.sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertGreaterThanOrEqual(right.count, 2)
        let gap = right[1].frame.minY - right[0].frame.maxY
        XCTAssertEqual(gap, LayoutMetrics().siblingGap, accuracy: 0.001)
    }

    func testLinksAreEdgeMidpointSCurvesThatThinAndFollowBranchColor() {
        let grand = MindMapNode(text: "孙")
        let first = MindMapNode(text: "一", children: [grand])
        let second = MindMapNode(text: "二")
        let root = MindMapNode(text: "根", children: [first, second])
        let engine = LayoutEngine()
        let frames = engine.layout(MindMapDocument(title: "links", roots: [root]))
        let rootFrame = frames.first { $0.id == root.id }!
        let firstFrame = frames.first { $0.id == first.id }!
        let secondFrame = frames.first { $0.id == second.id }!
        let grandFrame = frames.first { $0.id == grand.id }!
        let firstLink = try! XCTUnwrap(firstFrame.link)
        XCTAssertEqual(firstLink.start.x, rootFrame.frame.maxX, accuracy: 0.001)
        XCTAssertEqual(firstLink.start.y, rootFrame.frame.midY, accuracy: 0.001)
        XCTAssertEqual(firstLink.end.x, firstFrame.frame.minX, accuracy: 0.001)
        XCTAssertEqual(firstLink.end.y, firstFrame.frame.midY, accuracy: 0.001)
        XCTAssertEqual(firstLink.control1.y, firstLink.start.y, accuracy: 0.001)
        XCTAssertEqual(firstLink.control2.y, firstLink.end.y, accuracy: 0.001)
        XCTAssertNotEqual(firstLink.control1.x, firstLink.start.x)
        XCTAssertGreaterThan(firstLink.lineWidth, grandFrame.link!.lineWidth)
        XCTAssertEqual(firstFrame.fill, firstLink.color)
        XCTAssertEqual(firstFrame.textColor, .white)
        XCTAssertEqual(grandFrame.link?.color, firstLink.color)
        XCTAssertEqual(grandFrame.textColor, .black)
        XCTAssertNotEqual(secondFrame.link?.color, firstLink.color)
        XCTAssertEqual(secondFrame.textColor, .white)
        let light = firstLink.color.lightened(by: engine.appearance.deeperFillMix)
        XCTAssertEqual(grandFrame.fill, light)
    }

    /// Three equal siblings put two on one side, so those midpoints are not level with the parent.
    /// A cubic that has been replaced by a straight segment keeps its controls on the chord and fails here.
    /// t = 0.5 of this symmetric S lies on the chord; the quarter point is the one that bows.
    func testSCurveBendsWhenParentAndChildDifferInY() throws {
        let siblings = [
            MindMapNode(text: "上"),
            MindMapNode(text: "中"),
            MindMapNode(text: "下"),
        ]
        let root = MindMapNode(text: "根", children: siblings)
        let frames = LayoutEngine().layout(MindMapDocument(title: "bend", roots: [root]))
        let rootFrame = try XCTUnwrap(frames.first { $0.id == root.id })
        let children = siblings.compactMap { node in frames.first { $0.id == node.id } }
        XCTAssertEqual(children.count, 3)
        let bent = children.filter { abs($0.frame.midY - rootFrame.frame.midY) > 1 }
        XCTAssertFalse(bent.isEmpty)

        for child in bent {
            let link = try XCTUnwrap(child.link)
            XCTAssertGreaterThan(abs(link.end.y - link.start.y), 1)
            XCTAssertGreaterThan(distanceFromChord(link.control1, link: link), 1)
            XCTAssertGreaterThan(distanceFromChord(link.control2, link: link), 1)
            let quarter = cubicPoint(link, t: 0.25)
            XCTAssertGreaterThan(distanceFromChord(quarter, link: link), 1)
        }
    }

    func testCollapsedSubtreeIsExcluded() {
        let root = MindMapNode(text: "根", isCollapsed: true, children: [MindMapNode(text: "藏")])
        let frames = LayoutEngine().layout(MindMapDocument(title: "fold", roots: [root]))
        XCTAssertEqual(frames.map(\.id), [root.id])
    }

    func testManualPositionSkipsThatBranch() {
        let hidden = MindMapNode(text: "藏")
        let child = MindMapNode(text: "子", children: [hidden])
        let root = MindMapNode(
            text: "根",
            position: MindMapPoint(x: 12, y: 34),
            children: [child]
        )
        let frames = LayoutEngine().layout(MindMapDocument(title: "manual", roots: [root]))
        XCTAssertEqual(frames.map(\.id), [root.id])
        XCTAssertEqual(frames[0].origin.x, 12, accuracy: 0.001)
        XCTAssertEqual(frames[0].origin.y, 34, accuracy: 0.001)
    }

    func testManualChildIsPlacedButItsSubtreeIsNotAutoLaid() {
        let hidden = MindMapNode(text: "藏")
        let child = MindMapNode(
            text: "浮",
            position: MindMapPoint(x: 400, y: 20),
            children: [hidden]
        )
        let root = MindMapNode(text: "根", children: [child])
        let frames = LayoutEngine().layout(MindMapDocument(title: "branch", roots: [root]))
        XCTAssertNotNil(frames.first { $0.id == child.id })
        XCTAssertEqual(frames.first { $0.id == child.id }?.origin.x ?? -1, 400, accuracy: 0.001)
        XCTAssertNil(frames.first { $0.id == hidden.id })
    }

    func testMeasurementCacheKeyIncludesFontSize() {
        let cache = TextMeasurementCache()
        var engine = LayoutEngine(cache: cache)
        let document = MindMapDocument(title: "cache", roots: [MindMapNode(text: "根", children: [MindMapNode(text: "子")])])
        _ = engine.layout(document)
        let misses = cache.missCount
        XCTAssertGreaterThan(misses, 0)
        _ = engine.layout(document)
        XCTAssertEqual(cache.missCount, misses)
        engine.metrics.centerFontSize = 28
        _ = engine.layout(document)
        XCTAssertGreaterThan(cache.missCount, misses)
    }

    func testInteractionHooksExposeHoverSelectionAndFloatingTopics() {
        var interaction = CanvasInteraction.standard
        var document = MindMapDocument(title: "hooks", roots: [MindMapNode(text: "根")])
        let rootID = document.roots[0].id
        CanvasCommands.apply(.hover(rootID), document: &document, interaction: &interaction)
        XCTAssertEqual(interaction.addDirections, CanvasDirection.allCases)
        XCTAssertEqual(interaction.addDirections.count, 4)
        CanvasCommands.apply(.hover(nil), document: &document, interaction: &interaction)
        XCTAssertTrue(interaction.addDirections.isEmpty)

        CanvasCommands.apply(.select(rootID), document: &document, interaction: &interaction)
        XCTAssertTrue(interaction.showsSelectionChrome)
        XCTAssertEqual(interaction.selectionBorder, .selectionBlue)
        XCTAssertEqual(interaction.selectionBorderWidth, 1.5)
        XCTAssertEqual(interaction.resizeHandles, CanvasDirection.allCases)
        XCTAssertFalse(interaction.showsShadows)

        let before = document.roots[0].children.count
        let childID = CanvasCommands.apply(
            .addChild(parentID: rootID, direction: .right),
            document: &document,
            interaction: &interaction
        )
        XCTAssertNotNil(childID)
        XCTAssertEqual(document.roots[0].children.count, before + 1)

        let point = CGPoint(x: 80, y: -20)
        let floating = CanvasCommands.apply(
            .addFloatingTopic(at: point),
            document: &document,
            interaction: &interaction
        )
        XCTAssertEqual(document.roots.count, 2)
        XCTAssertEqual(document.roots[1].id, floating)
        XCTAssertEqual(document.roots[1].position?.x ?? -1, 80, accuracy: 0.001)
        XCTAssertEqual(document.roots[1].position?.y ?? -1, -20, accuracy: 0.001)
    }

    func testCanvasChromeParamsCoverZoomFitAndSheets() {
        var chrome = CanvasChrome.standard
        XCTAssertTrue(chrome.isInfinite)
        XCTAssertEqual(chrome.zoomPercent, 100)
        XCTAssertTrue(chrome.zoomIsClickable)
        XCTAssertTrue(chrome.fitControlVisible)
        XCTAssertEqual(chrome.sheets.count, 1)
        chrome.addSheet(title: "Page 2")
        chrome.selectSheet(1)
        XCTAssertEqual(chrome.sheets.count, 2)
        XCTAssertEqual(chrome.activeSheetIndex, 1)
        XCTAssertEqual(LayoutEngine().kind, .bilateral)
    }

    func testThousandNodeLayoutPrintsElapsedTime() {
        var children: [MindMapNode] = []
        var count = 1
        for index in 0..<40 {
            let grandchildren = index == 39 ? 23 : 24
            let branch = MindMapNode(
                text: "支\(index)",
                children: (0..<grandchildren).map { MindMapNode(text: "叶\(index)-\($0)") }
            )
            children.append(branch)
            count += 1 + grandchildren
        }
        XCTAssertEqual(count, 1000)
        let document = MindMapDocument(title: "measure", roots: [MindMapNode(text: "根", children: children)])
        let start = Date()
        let frames = LayoutEngine().layout(document)
        let seconds = Date().timeIntervalSince(start)
        print("measure bilateral-layout nodes=\(frames.count) seconds=\(seconds)")
        XCTAssertEqual(frames.count, 1000)
    }

    private func cubicPoint(_ link: LinkCurve, t: CGFloat) -> CGPoint {
        let u = 1 - t
        let uu = u * u
        let tt = t * t
        return CGPoint(
            x: uu * u * link.start.x + 3 * uu * t * link.control1.x + 3 * u * tt * link.control2.x + tt * t * link.end.x,
            y: uu * u * link.start.y + 3 * uu * t * link.control1.y + 3 * u * tt * link.control2.y + tt * t * link.end.y
        )
    }

    private func distanceFromChord(_ point: CGPoint, link: LinkCurve) -> CGFloat {
        let dx = link.end.x - link.start.x
        let dy = link.end.y - link.start.y
        let length = hypot(dx, dy)
        let cross = dx * (point.y - link.start.y) - dy * (point.x - link.start.x)
        return abs(cross) / length
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
