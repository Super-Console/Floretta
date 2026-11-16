import XCTest

final class CanvasZoomOutVisibilityContractTests: XCTestCase {
    func testFarNodesRetainContoursAndText() throws {
        let placement = try repoFile("Floretta/Shared/Canvas/CanvasPlacement.swift")
        let canvas = try repoFile("Floretta/Shared/Canvas/InfiniteCanvas.swift")

        XCTAssertTrue(placement.contains("var drawsOutline: Bool { true }"))
        XCTAssertTrue(canvas.contains("detail.drawsOutline"))
        XCTAssertTrue(canvas.contains("max(outlineWidth, 0.75)"))
        XCTAssertTrue(canvas.contains("textRect.height > 0, textRect.width > 0"))
    }

    func testTextLODDoesNotDropSmallButValidGlyphs() throws {
        let placement = try repoFile("Floretta/Shared/Canvas/CanvasPlacement.swift")
        let lod = try slice(placement, from: "enum CanvasTextLOD", until: "/// How much of a node's style")

        XCTAssertTrue(lod.contains("guard onScreenPointSize.isFinite, onScreenPointSize > 0"))
        XCTAssertFalse(lod.contains("onScreenPointSize < 5"))
    }

    private func repoFile(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    private func slice(_ source: String, from startMark: String, until endMark: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMark))
        let rest = source[start.lowerBound...]
        let end = try XCTUnwrap(rest.range(of: endMark))
        return String(rest[..<end.lowerBound])
    }
}
