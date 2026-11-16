import XCTest

final class NodeTextEditorBackgroundContractTests: XCTestCase {
    func testNativeTextViewsUseTheirOwnSurfaceWhenNoPaperIsSupplied() throws {
        let source = try repoFile("Floretta/Shared/Keyboard/NodeTextEditor.swift")
        let macMake = try slice(source, from: "private func makeEditingTextView", until: "func updateNSView")
        XCTAssertTrue(macMake.contains("view.drawsBackground = paper != nil"))
        XCTAssertTrue(macMake.contains("paper.map { NSColor($0) } ?? .clear"))

        let macUpdate = try slice(source, from: "func updateNSView(_ nsView: EditingTextView", until: "private func applyNodeChrome")
        XCTAssertTrue(macUpdate.contains("let drawsPaper = paper != nil"))
        XCTAssertTrue(macUpdate.contains("nsView.drawsBackground = drawsPaper"))
        XCTAssertTrue(macUpdate.contains("paper.map { NSColor($0) } ?? .clear"))
        XCTAssertTrue(macUpdate.contains("nsView.insertionPointColor = NSColor(ink)"), "transparent paper must keep the insertion caret visible")

        let iosMake = try slice(source, from: "func makeUIView(context: Context)", until: "func updateUIView")
        XCTAssertTrue(iosMake.contains("paper.map { UIColor($0) } ?? .clear"))
        XCTAssertTrue(iosMake.contains("view.isOpaque = paper != nil"))

        let iosUpdate = try slice(source, from: "func updateUIView(_ uiView: FlorettaTextView", until: "private func applyNodeChrome")
        XCTAssertTrue(iosUpdate.contains("paper.map { UIColor($0) } ?? .clear"))
        XCTAssertTrue(iosUpdate.contains("let isOpaque = paper != nil"))
        XCTAssertTrue(iosUpdate.contains("uiView.isOpaque = isOpaque"))
    }

    func testNodeEditUsesItsFillWhileCanvasOverlayLabelsStayTransparent() throws {
        let editor = try repoFile("Floretta/Shared/Canvas/InfiniteCanvas.swift")
        let node = try slice(editor, from: "private var editField", until: "private var nodeChromeProbe")
        XCTAssertTrue(node.contains("nodeChrome: NodeEditSurface("))
        XCTAssertTrue(node.contains("fill: frame.fill"))

        for (name, start, end) in [
            ("relationship", "private var relationshipEditor", "private var summaryEditor"),
            ("summary", "private var summaryEditor", "private var boundaryEditor"),
            ("boundary", "private var boundaryEditor", "private var regionEditor"),
            ("region", "private var regionEditor", "private func performRegionAction")
        ] {
            let overlay = try slice(editor, from: start, until: end)
            XCTAssertFalse(overlay.contains("paper:"), name + " labels should reveal their underlying canvas surface")
        }
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
