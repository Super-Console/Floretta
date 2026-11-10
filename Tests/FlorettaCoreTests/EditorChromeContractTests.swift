import XCTest

/// Locks the editor chrome that has no XCUITest: the back button sits before
/// the filename, and the Mac window title is not a second copy of that name.
final class EditorChromeContractTests: XCTestCase {
    func testBackButtonPrecedesTheFilenameInTheLeadingToolbar() throws {
        let source = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        XCTAssertTrue(source.contains("ToolbarItem(placement: .cancellationAction)"))
        XCTAssertTrue(source.contains("leadingDocumentChrome"))
        let leading = try slice(
            source,
            from: "private var leadingDocumentChrome",
            until: "private var toolbarContext"
        )
        let back = try XCTUnwrap(leading.range(of: "\"basicChain.back\""))
        let title = try XCTUnwrap(leading.range(of: "\"document.title\""))
        XCTAssertLessThan(back.lowerBound, title.lowerBound)
        XCTAssertTrue(leading.contains("chevron.backward"))
        XCTAssertTrue(leading.contains("documentTitle"))
    }

    func testToolbarFilenameIsNotRepeatedInTheWindowTitle() throws {
        let source = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        XCTAssertTrue(source.contains(".navigationTitle(\"\")"))
        XCTAssertTrue(source.contains(".modifier(MacEditorWindowTitle())"))
        XCTAssertTrue(source.contains("window.titleVisibility = .hidden"))
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
