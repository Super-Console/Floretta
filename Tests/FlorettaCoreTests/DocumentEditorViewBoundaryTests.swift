import XCTest
import Foundation

final class DocumentEditorViewBoundaryTests: XCTestCase {
    func testCrashProneEditorBranchesStopAtNamedViewBoundaries() throws {
        let source = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let editorCore = try slice(source, from: "private var editorCore: some View", until: "private struct EditorCoreView: View")
        let canvasStack = try slice(source, from: "private var canvasStack: some View", until: "private struct CanvasStackView: View")

        XCTAssertTrue(editorCore.contains("EditorCoreView(editor: self)"))
        XCTAssertFalse(editorCore.contains(".overlay(alignment: .topTrailing)"), "the shell's generic chain belongs behind a concrete view boundary")
        XCTAssertTrue(canvasStack.contains("CanvasStackView(editor: self)"))
        XCTAssertFalse(canvasStack.contains("InfiniteCanvas("), "the large canvas subtree must not be nested in DocumentEditor.canvasStack")
    }

    func testOutlinePanelHasItsOwnConcreteBoundary() throws {
        let source = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let outline = try slice(source, from: "private var outlinePanel: some View", until: "private struct OutlinePanelView: View")
        let panel = try slice(source, from: "private struct OutlinePanelView: View", until: "private struct OutlinePanelHeaderView: View")

        XCTAssertTrue(outline.contains("OutlinePanelView(editor: self)"))
        XCTAssertFalse(outline.contains("VStack(alignment: .leading"), "the panel's toolbar and outline list stay out of the canvas stack's type")
        XCTAssertTrue(panel.contains("OutlinePanelHeaderView(editor: editor)"))
        XCTAssertFalse(panel.contains("HStack(spacing: 4)"), "the panel header's button subtree needs its own concrete boundary")
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
