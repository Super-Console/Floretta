import XCTest

/// Locks editor chrome alongside the UI test: the back glyph and the editable
/// filename share one leading Mac navigation capsule (system glass only, no
/// custom plate stacked inside it), and the iOS control is a stock toolbar
/// item. The hit area itself is `EditorBackButtonHitAreaTests`.
final class EditorChromeContractTests: XCTestCase {
    func testMacBackButtonAndTitleShareOneNavigationCapsule() throws {
        let source = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let leading = try slice(
            source,
            from: "private var macToolbarItemsLeading",
            until: "private var macToolbarItemsPrimary"
        )
        XCTAssertTrue(leading.contains("chevron.backward"))
        XCTAssertTrue(leading.contains("\"basicChain.back\""))
        XCTAssertTrue(leading.contains("ToolbarItem(id: \"document.navigation\", placement: .navigation)"))
        XCTAssertTrue(leading.contains("HStack(spacing: 8)"), "the title sits beside the back glyph in the one system capsule")
        XCTAssertTrue(leading.contains("\"document.title\""), "the rename control keeps its accessibility identifier")
        XCTAssertTrue(leading.contains("Text(verbatim: documentTitle)"))
        XCTAssertFalse(leading.contains(".appleGlassChrome(.floatingPanel)"), "no custom glass plate may be nested inside the system navigation capsule")
        XCTAssertTrue(source.contains(".modifier(MacEditorWindowTitle(title: \"\"))"))
    }

    /// The iOS back control has to be a stock toolbar button. A custom style,
    /// a drawn circle, or a frame wrapped around the glyph opts out of the
    /// system bar item, and the hit target collapses to the symbol.
    func testIOSBackButtonIsAStandardToolbarItem() throws {
        let source = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let leading = try slice(
            source,
            from: "private var editorToolbar",
            until: "private var editorEvents"
        )
        let toolbar = try slice(leading, from: ".toolbar {", until: "#if !os(macOS)")
        let iosStart = try XCTUnwrap(toolbar.range(of: "#if os(iOS)"))
        let ios = String(toolbar[iosStart.lowerBound...])
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
        XCTAssertTrue(ios.contains("\"document.title\""))
        XCTAssertTrue(source.contains("ToolbarItem(id: \"document.navigation\", placement: .navigation)"))
    }

    func testDocumentFilenameIsNotDuplicatedInNativeWindowTitle() throws {
        let source = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        XCTAssertTrue(source.contains(".navigationTitle(\"\")"))
        XCTAssertTrue(source.contains(".modifier(MacEditorWindowTitle(title: \"\"))"))
        XCTAssertTrue(source.contains("window.title = title"))
        XCTAssertTrue(source.contains("window.titleVisibility = .visible"))
    }

    func testMacDocumentTitleIsPersistentOutsideSelectionDependentToolbar() throws {
        let source = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let toolbar = try slice(source, from: ".toolbar(id: \"floretta.editor\")", until: ".toolbarBackground(.hidden, for: .windowToolbar)")
        let title = try XCTUnwrap(toolbar.range(of: "macToolbarItemsLeading"))
        let conditional = try XCTUnwrap(toolbar.range(of: "if session.zen.chrome.showsToolbar"))

        XCTAssertLessThan(title.lowerBound, conditional.lowerBound, "back and title stay installed regardless of editor selection/focus chrome")
    }

    /// Window chrome is corrected once, from attachment and representable
    /// update. Writing it from `layout()` re-enters toolbar layout.
    func testWindowChromeIsNotAppliedFromLayout() throws {
        let source = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let view = try slice(source, from: "final class MacWindowTitleView", until: "struct DroppedImage")
        XCTAssertFalse(view.contains("override func layout("))
        XCTAssertTrue(view.contains("chromePass.applying("))
        XCTAssertTrue(view.contains("toolbar.displayMode = .iconOnly"))
        XCTAssertFalse(source.contains("UIPolishRuntimeTrace"))
        let canvas = try repoFile("Floretta/Shared/Canvas/InfiniteCanvas.swift")
        XCTAssertFalse(canvas.contains("UIPolishRuntimeTrace"))
        let editor = try repoFile("Floretta/Shared/Keyboard/NodeTextEditor.swift")
        XCTAssertFalse(editor.contains("UIPolishRuntimeTrace"))
        XCTAssertTrue(editor.contains("shouldAssignFont("))
        XCTAssertTrue(editor.contains("TextCenteringPass"))
        XCTAssertTrue(editor.contains("shouldApply(to:"))
    }

    func testWordCountSitsInTheOverflowMenu() throws {
        let source = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let bar = try repoFile("Floretta/Shared/Shell/EditorStatusBar.swift")
        let more = try slice(source, from: "private var moreMenu", until: "private var insertOverflowSubmenu")
        XCTAssertTrue(source.contains(".overlay(alignment: .bottom)"))
        XCTAssertTrue(source.contains("session.zen.chrome.showsStatusBar"))
        XCTAssertTrue(source.contains("EditorStatusStrip("))
        XCTAssertFalse(source.contains("TopicStatusBar("))
        XCTAssertTrue(more.contains("EditorOverflowCensus("))
        XCTAssertTrue(more.contains("overflowCensus"))
        XCTAssertFalse(more.contains("perform(.about)"))
        XCTAssertFalse(more.contains(".about"))
        XCTAssertTrue(bar.contains("struct EditorOverflowCensus"))
        XCTAssertTrue(bar.contains("\"主题 %lld\""))
        XCTAssertTrue(bar.contains("\"字数 %lld\""))
        XCTAssertTrue(bar.contains("\"字符数 %lld\""))
        XCTAssertTrue(bar.contains("status.topics"))
        XCTAssertTrue(bar.contains("status.words"))
        XCTAssertTrue(bar.contains("status.characters"))
        XCTAssertTrue(bar.contains("TopicTitleCensus"))
        let inspector = try slice(source, from: "private var documentInfo", until: "private var relationshipLabelForm")
        XCTAssertFalse(inspector.contains("字数"))
        XCTAssertFalse(inspector.contains("字符数"))
        let editor = try repoFile("Floretta/Shared/Keyboard/NodeTextEditor.swift")
        XCTAssertFalse(editor.contains("字数"))
        XCTAssertFalse(editor.contains("TopicStatusBar"))
        XCTAssertFalse(editor.contains("EditorOverflowCensus"))
    }

    /// TD-007: the right-top inspector switch is one glass capsule. The plate
    /// comes from the official glass role, the hit target stays at least 28x28,
    /// and nothing paints its own gradient, blur, or shadow.
    func testMacInspectorToggleIsOneGlassCapsule() throws {
        let source = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let toggle = try slice(source, from: "private var macInspectorToggle", until: "#endif")
        XCTAssertTrue(toggle.contains("ToolbarItem(id: \"inspector.toggle\", placement: .primaryAction)"))
        XCTAssertTrue(toggle.contains("showInspector.toggle()"))
        XCTAssertTrue(toggle.contains(".appleGlassChrome(.toolbarFloatingButton)"))
        XCTAssertTrue(toggle.contains("sidebar.trailing"))
        XCTAssertTrue(toggle.contains(".frame(width: 34, height: 28)"), "hit target must stay at least 28x28")
        XCTAssertTrue(toggle.contains("contentShape(Capsule())"))
        XCTAssertTrue(toggle.contains("accessibilityIdentifier(\"inspector.toggle\")"))
        XCTAssertTrue(toggle.contains(".defaultCustomization(.visible)"))
        for painted in [".linearGradient", ".blur(", ".shadow(", "ultraThinMaterial", "Color.white", "Color.black"] {
            XCTAssertFalse(toggle.contains(painted), painted)
        }
        let glass = try repoFile("Floretta/Shared/Shell/AppleGlassChrome.swift")
        XCTAssertTrue(glass.contains("case .segmentedContainer, .bottomBarCapsule, .toolbarFloatingButton:"))
        XCTAssertTrue(glass.contains("plated(inked(view), shape: Capsule())"))
        XCTAssertTrue(toggle.contains("EditorToolbarCatalog.command(.style).title"), "the switch reuses the 样式 title instead of inventing one")
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
