import XCTest

/// Locks editor chrome alongside the UI test: the back button sits before the
/// filename, the iOS control is a stock toolbar item, and the Mac window title
/// is not a second copy of that name. The hit area itself is
/// `EditorBackButtonHitAreaTests`.
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

    /// The iOS back control has to be a stock toolbar button. A custom style,
    /// a drawn circle, or a frame wrapped around the glyph opts out of the
    /// system bar item, and the hit target collapses to the symbol.
    func testIOSBackButtonIsAStandardToolbarItem() throws {
        let source = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let leading = try slice(
            source,
            from: "if session.zen.chrome.showsToolbar",
            until: "ToolbarItemGroup(placement: .principal)"
        )
        let iosStart = try XCTUnwrap(leading.range(of: "#if os(iOS)"))
        let iosEnd = try XCTUnwrap(leading.range(of: "#else"))
        let ios = String(leading[iosStart.lowerBound..<iosEnd.lowerBound])
        let mac = String(leading[iosEnd.upperBound...])
        let spacer = try XCTUnwrap(ios.range(of: "ToolbarSpacer(.fixed, placement: .cancellationAction)"))
        let backItem = String(ios[..<spacer.lowerBound])
        XCTAssertTrue(backItem.contains("ToolbarItem(placement: .cancellationAction)"))
        XCTAssertTrue(backItem.contains("chevron.backward"))
        XCTAssertTrue(backItem.contains("\"basicChain.back\""))
        XCTAssertTrue(backItem.contains(".frame(width: 44, height: 44)"))
        XCTAssertTrue(backItem.contains("contentShape(Circle())"))
        XCTAssertTrue(backItem.contains(".appleGlassChrome(.iconButton)"))
        XCTAssertFalse(backItem.contains("HStack"))
        XCTAssertFalse(backItem.contains("ultraThinMaterial"))
        XCTAssertFalse(backItem.contains(".blur("))
        XCTAssertTrue(ios.contains(".sharedBackgroundVisibility(.hidden)"))
        XCTAssertTrue(mac.contains("leadingDocumentChrome"))
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
