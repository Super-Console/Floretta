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

    /// TD-003: the counts left the ••• menu for the bottom capsule's popover.
    /// Both still read the one `TopicTitleCensus`; nothing counts twice.
    func testStatusCapsuleCarriesTheCountsInsteadOfTheOverflowMenu() throws {
        let source = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let bar = try repoFile("Floretta/Shared/Shell/EditorStatusBar.swift")
        let more = try slice(source, from: "private var moreMenu", until: "private var insertOverflowSubmenu")
        XCTAssertTrue(source.contains(".overlay(alignment: .bottom)"))
        XCTAssertTrue(source.contains("session.zen.chrome.showsStatusBar"))
        XCTAssertTrue(source.contains("EditorStatusStrip("))
        XCTAssertFalse(source.contains("TopicStatusBar("))
        XCTAssertFalse(more.contains("EditorCensusBreakdown"))
        XCTAssertFalse(more.contains("StatusCensusBreakdown"))
        XCTAssertFalse(more.contains("status.topicCensus"))
        XCTAssertFalse(source.contains("makeCensusUIMenu"))
        XCTAssertFalse(source.contains("EditorOverflowCensus"))
        XCTAssertTrue(source.contains("census: statusCensus"))
        XCTAssertFalse(more.contains("perform(.about)"))
        XCTAssertFalse(more.contains(".about"))
        XCTAssertTrue(bar.contains("struct StatusCensusBreakdown"))
        XCTAssertTrue(bar.contains("\"主题 %lld\""))
        XCTAssertTrue(bar.contains("\"字数 %lld\""))
        XCTAssertTrue(bar.contains("\"字符数 %lld\""))
        XCTAssertTrue(bar.contains("status.popover.topics"))
        XCTAssertTrue(bar.contains("status.popover.words"))
        XCTAssertTrue(bar.contains("status.popover.characters"))
        XCTAssertTrue(bar.contains("TopicTitleCensus"))
        let inspector = try slice(source, from: "private var documentInfo", until: "private var relationshipLabelForm")
        XCTAssertFalse(inspector.contains("字数"))
        XCTAssertFalse(inspector.contains("字符数"))
        let editor = try repoFile("Floretta/Shared/Keyboard/NodeTextEditor.swift")
        XCTAssertFalse(editor.contains("字数"))
        XCTAssertFalse(editor.contains("TopicStatusBar"))
        XCTAssertFalse(editor.contains("StatusCensusBreakdown"))
        XCTAssertFalse(editor.contains("EditorOverflowCensus"))
    }

    /// TD-006: the Mac top bar is three groups — 撤销/重做/删除 | ＋插入 |
    /// 关系线/概要/边界/标签 — with the ••• last, and the ••• menu never repeats
    /// a command the bar already draws.
    func testMacTopBarGroupsHighFrequencyCommandsAndOverflowComesLast() throws {
        let source = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let primary = try slice(source, from: "private var macToolbarItemsPrimary", until: "private var macToolbarItemsInsert")
        XCTAssertTrue(primary.contains("macItem(.undo)"))
        XCTAssertTrue(primary.contains("macItem(.redo)"))
        XCTAssertFalse(primary.contains("macItem(.share)"), "import/export is low frequency")

        let insert = try slice(source, from: "private var macToolbarItemsInsert", until: "private var macToolbarItemsRelations")
        XCTAssertTrue(insert.contains("macItem(.insert)"), "＋ 插入 is a bar item")
        XCTAssertTrue(insert.contains("macItem(.freeNode)"))
        XCTAssertTrue(insert.contains("macItem(.sticky)"))
        XCTAssertTrue(insert.contains("macItem(.image)"))
        XCTAssertTrue(insert.contains("macItem(.attachment)"))
        XCTAssertFalse(insert.contains("macItem(.link)"), "关系线 is its own group now")
        XCTAssertFalse(insert.contains("macItem(.summary)"))
        XCTAssertFalse(insert.contains("macItem(.boundary)"))

        let relations = try slice(source, from: "private var macToolbarItemsRelations", until: "private var macToolbarItemsOverflow")
        for id in ["link", "summary", "boundary", "tagFilter"] {
            XCTAssertTrue(relations.contains("macItem(.\(id))"), id)
        }

        let groups = try slice(source, from: ".toolbar(id: \"floretta.editor\")", until: ".toolbarBackground(.hidden, for: .windowToolbar)")
        var cursor = groups.startIndex
        for name in ["macToolbarItemsPrimary", "macToolbarItemsInsert", "macToolbarItemsRelations", "macToolbarItemsOverflow"] {
            let range = try XCTUnwrap(groups.range(of: name, range: cursor..<groups.endIndex), name)
            cursor = range.upperBound
        }
        let overflow = try XCTUnwrap(groups.range(of: "macToolbarItemsView"))
        XCTAssertLessThan(cursor, overflow.lowerBound, "the ••• comes before the trailing inspector capsule")

        // One de-duplication rule, no per-platform list.
        let more = try slice(source, from: "private var moreMenu", until: "private var overflowMenuCommands")
        XCTAssertFalse(more.contains("#if os(macOS)\n            insertOverflowSubmenu"))
        for guarded in [".insert", ".share", ".undo", ".redo", ".delete", ".immersive"] {
            XCTAssertTrue(more.contains("toolbarVisibleItems.contains(\(guarded))"), guarded)
        }
        XCTAssertTrue(source.contains("EditorToolbarCatalog.menu(.more).filter { !onBar.contains($0) }"))
        XCTAssertTrue(source.contains("ForEach(overflowMenuCommands"))

        // Narrow windows are the system toolbar's job, not a "swap to •••" rule.
        XCTAssertTrue(source.contains("/// The ••• overflow. It stays a normal toolbar item"))
    }

    /// TD-002 + TD-003 on one line: the sheet capsule and the status capsule are
    /// siblings in one bottom row, share one plate height and one bottom inset,
    /// and neither side adds a compensating padding. This is the regression guard
    /// for the two capsules drifting onto two different lines.
    func testBottomCapsulesShareOneRowHeightAndInset() throws {
        let source = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let bar = try repoFile("Floretta/Shared/Shell/EditorStatusBar.swift")
        let core = try repoFile("FlorettaCore/Layout/EditorStatusBar.swift")

        let row = try slice(
            source,
            from: "private var bottomBarRow",
            until: "private func revealZenExitAffordance"
        )
        XCTAssertTrue(row.contains("HStack(alignment: .bottom"), "the two capsules are one row")
        XCTAssertTrue(row.contains("canvasTabBar"))
        XCTAssertTrue(row.contains("EditorStatusStrip("))
        XCTAssertFalse(row.contains("VStack"), "a VStack puts the capsules on two lines; that is the bug")
        XCTAssertTrue(row.contains(".padding(.horizontal, EditorStatusBarChrome.horizontalInset)"))
        XCTAssertTrue(row.contains(".padding(.bottom, EditorStatusBarChrome.bottomInset)"))
        XCTAssertTrue(row.contains(".safeAreaPadding(.bottom)"))
        XCTAssertTrue(row.contains(".layoutPriority(1)"), "the status capsule is served first, never squeezed")

        // Both plates are the same height, so `.bottom` alignment is enough.
        let canvas = try slice(
            source,
            from: "private var canvasTabBar",
            until: "private var currentCanvasIndex"
        )
        XCTAssertTrue(canvas.contains(".frame(minHeight: EditorStatusBarChrome.controlMinHeight)"))
        XCTAssertTrue(bar.contains(".frame(minHeight: EditorStatusBarChrome.controlMinHeight)"))
        XCTAssertFalse(bar.contains(".padding(.vertical, 6)"), "the strip's own bottom padding made the two plates hang from different lines")
        XCTAssertFalse(bar.contains("Spacer("), "the row places the capsule; the strip owns no trailing gap")
        XCTAssertTrue(bar.contains(".fixedSize(horizontal: true, vertical: false)"))

        // The row owns the window inset; no capsule re-adds its own.
        let canvasPlate = try slice(
            canvas,
            from: ".appleGlassChrome(.bottomBarCapsule)",
            until: ".accessibilityElement"
        )
        XCTAssertFalse(canvasPlate.contains(".padding"), "a per-capsule window inset is the magic padding that must not come back")

        // One copy of the numbers, in core, beside the chrome role.
        XCTAssertTrue(core.contains("public static let controlMinHeight"))
        XCTAssertTrue(core.contains("public static let horizontalInset"))
        XCTAssertTrue(core.contains("public static let bottomInset"))
        XCTAssertTrue(core.contains("public static let capsuleGap"))
        XCTAssertTrue(core.contains("public static let canvasTitleMaxWidth"))

        // Narrow windows: the name truncates, then the divider goes. Nothing
        // overlaps and the status capsule is never pushed off screen.
        XCTAssertTrue(canvas.contains(".truncationMode(.tail)"))
        XCTAssertTrue(canvas.contains("EditorStatusBarChrome.canvasTitleMaxWidth"))
        XCTAssertTrue(canvas.contains("if showsSheetDivider"))
        XCTAssertTrue(source.contains("EditorBottomBarLayout.showsSheetDivider("))
        XCTAssertTrue(canvas.contains("accessibilityIdentifier(\"canvas.tabs\")"))
    }

    /// Both bottom capsules draw at one platform-aware plate height, with one
    /// padding, one spacing, and one icon box. The Mac plate is 28 pt — the
    /// optical height of a native toolbar control — while iOS keeps the 44 pt
    /// touch target.
    func testBottomCapsulesUsePlatformPlateHeightAndOneSetOfSizes() throws {
        let bar = try repoFile("Floretta/Shared/Shell/EditorStatusBar.swift")
        let source = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let core = try repoFile("FlorettaCore/Layout/EditorStatusBar.swift")

        XCTAssertTrue(core.contains("#if os(macOS)"))
        XCTAssertTrue(core.contains("public static let controlMinHeight: CGFloat = 28"))
        XCTAssertTrue(core.contains("public static let controlMinHeight: CGFloat = 44"))

        XCTAssertTrue(bar.contains("EditorStatusBarChrome.capsuleControlSpacing"))
        XCTAssertTrue(bar.contains("EditorStatusBarChrome.capsuleHorizontalPadding"))
        XCTAssertTrue(bar.contains("EditorStatusBarChrome.capsuleVerticalPadding"))
        XCTAssertTrue(bar.contains("EditorStatusBarChrome.iconButtonSize"))
        XCTAssertTrue(bar.contains(".controlSize(.small)"))
        XCTAssertTrue(bar.contains(".frame(minHeight: EditorStatusBarChrome.controlMinHeight)"))
        XCTAssertFalse(bar.contains(".padding(.horizontal, 12)"), "no per-capsule literal padding")
        XCTAssertFalse(bar.contains(".padding(.vertical, 4)"), "no per-capsule literal padding")

        let canvas = try slice(
            source,
            from: "private var canvasTabBar",
            until: "private var currentCanvasIndex"
        )
        XCTAssertTrue(canvas.contains(".controlSize(.small)"))
        XCTAssertTrue(canvas.contains(".frame(minHeight: EditorStatusBarChrome.controlMinHeight)"))
        XCTAssertFalse(canvas.contains(".frame(minHeight: 44)"), "the plate height comes from the one constant, not a literal")

        // This branch never sets a font family on the capsules; the theme face is
        // handled by the chrome-typography branch.
        XCTAssertFalse(bar.contains(".custom("))
        XCTAssertFalse(bar.contains("Font.custom"))
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
