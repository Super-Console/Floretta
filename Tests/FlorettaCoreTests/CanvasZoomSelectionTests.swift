import XCTest
@testable import FlorettaCore

final class CanvasZoomSelectionTests: XCTestCase {
    func testVisibleNodesAndCrossingLinksAreSelectedIndependently() {
        let visibleID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let linkID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let outsideID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let crossingLink = LinkCurve(
            start: CGPoint(x: -20, y: 50),
            control1: CGPoint(x: 20, y: 50),
            control2: CGPoint(x: 80, y: 50),
            end: CGPoint(x: 120, y: 50),
            lineWidth: 1,
            color: .black
        )
        let frames = [
            node(id: visibleID, rect: CGRect(x: 10, y: 10, width: 20, height: 20)),
            node(id: linkID, rect: CGRect(x: 200, y: 200, width: 20, height: 20), link: crossingLink),
            node(id: outsideID, rect: CGRect(x: 300, y: 300, width: 20, height: 20)),
        ]

        let selection = CanvasViewportDrawSelection.select(
            frames: frames,
            in: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        XCTAssertEqual(selection.visibleNodes.map(\.id), [visibleID])
        XCTAssertEqual(selection.visibleLinkNodeIDs, [linkID])
    }

    func testInvalidViewportSelectsNothing() {
        let frame = node(id: UUID(), rect: CGRect(x: 0, y: 0, width: 20, height: 20))
        let selection = CanvasViewportDrawSelection.select(frames: [frame], in: .zero)

        XCTAssertTrue(selection.visibleNodes.isEmpty)
        XCTAssertTrue(selection.visibleLinkNodeIDs.isEmpty)
    }

    func testDrawUsesOneViewportPassForNodesAndLinks() throws {
        let source = try repoFile("Floretta/Shared/Canvas/InfiniteCanvas.swift")
        let draw = try slice(source, from: "private func draw(in context", until: "private func stroke(")

        XCTAssertTrue(draw.contains("CanvasViewportDrawSelection.select("))
        XCTAssertTrue(draw.contains("var visible = drawSelection.visibleNodes"))
        XCTAssertFalse(draw.contains("CanvasPlacement.frames(placed, intersectingCanvas: viewport)"))
        XCTAssertFalse(draw.contains("CanvasPlacement.nodeIDsWithVisibleLinks(placed, viewport: viewport)"))
    }

    private func repoFile(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    private func node(id: UUID, rect: CGRect, link: LinkCurve? = nil) -> NodeFrame {
        NodeFrame(
            id: id,
            text: "node",
            origin: rect.origin,
            size: rect.size,
            depth: 0,
            fontSize: 12,
            isRoot: true,
            fill: .white,
            border: .black,
            textColor: .black,
            cornerRadius: 4,
            link: link
        )
    }

    private func slice(_ source: String, from startMark: String, until endMark: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMark))
        let rest = source[start.lowerBound...]
        let end = try XCTUnwrap(rest.range(of: endMark))
        return String(rest[..<end.lowerBound])
    }
}
