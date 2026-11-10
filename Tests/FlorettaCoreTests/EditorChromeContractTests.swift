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

    func testWordCountSitsOnTheExistingBottomBar() throws {
        let source = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let bar = try slice(
            source,
            from: "private struct TopicStatusBar",
            until: "private final class TopicCensusModel"
        )
        XCTAssertTrue(source.contains(".safeAreaInset(edge: .bottom, spacing: 0)"))
        XCTAssertTrue(source.contains("session.zen.chrome.showsStatusBar"))
        XCTAssertTrue(source.contains("TopicStatusBar("))
        XCTAssertTrue(bar.contains("\"主题: %lld\""))
        XCTAssertTrue(bar.contains("\"字数: %lld\""))
        XCTAssertTrue(bar.contains("\"字符数: %lld\""))
        XCTAssertTrue(bar.contains("#if os(macOS)"))
        XCTAssertTrue(bar.contains(".trailing"))
        XCTAssertTrue(bar.contains(".leading"))
        XCTAssertTrue(bar.contains(".help(Text(verbatim: breakdown))"))
        XCTAssertTrue(bar.contains("status.topicCensus"))
        let inspector = try slice(source, from: "private var documentInfo", until: "private var relationshipLabelForm")
        XCTAssertFalse(inspector.contains("字数"))
        XCTAssertFalse(inspector.contains("字符数"))
        let editor = try repoFile("Floretta/Shared/Keyboard/NodeTextEditor.swift")
        XCTAssertFalse(editor.contains("字数"))
        XCTAssertFalse(editor.contains("TopicStatusBar"))
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
