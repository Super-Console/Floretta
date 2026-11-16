import FlorettaCore
import XCTest

/// Locks editor chrome alongside the UI test: the back glyph and the editable
/// filename share one leading Mac navigation capsule (system glass only, no
/// custom plate stacked inside it), and the iOS control is a stock toolbar
/// item. The hit area itself is `EditorBackButtonHitAreaTests`.
final class EditorChromeContractTests: XCTestCase {
    /// The name sits on the leading capsule's centre line, not to the right of
    /// the back control.
    ///
    /// The row is `返回 + gap + 名 + gap + 返回(空)`: the trailing slot is the
    /// same control with no ink, no hit testing, and no accessibility, so the
    /// name's slot is symmetric and the name keeps the plate's centre. A plain
    /// `[返回][名]` row measured ~20 pt right of centre in
    /// `scripts/measure-title-capsule.sh --baseline`; this test locks the shape
    /// that keeps it at 0 pt.
    func testMacBackButtonAndTitleShareOneCentredNavigationCapsule() throws {
        let source = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let leading = try slice(
            source,
            from: "private var macToolbarItemsLeading",
            until: "/// The one leading system capsule"
        )
        let capsule = try slice(
            source,
            from: "private struct DocumentTitleCapsule",
            until: "private var macToolbarItemsPrimary"
        )
        XCTAssertTrue(leading.contains("ToolbarItem(id: \"document.navigation\", placement: .navigation)"), "back and title share the leading navigation slot")
        XCTAssertTrue(leading.contains("DocumentTitleCapsule("), "the one item draws the capsule type")
        XCTAssertTrue(leading.contains("title: macToolbarSnapshot.documentTitle"))
        XCTAssertTrue(leading.contains("onBack: onClose"))
        XCTAssertFalse(leading.contains("HStack"), "the row lives in the capsule type: one item, one plate")

        XCTAssertTrue(capsule.contains("chevron.backward"))
        XCTAssertTrue(capsule.contains("\"basicChain.back\""))
        XCTAssertTrue(capsule.contains("\"document.title\""), "the rename control keeps its accessibility identifier")
        XCTAssertTrue(capsule.contains("HStack(spacing: Self.gap)"), "both gaps come from the one constant")
        XCTAssertTrue(capsule.contains("backSlot"), "the trailing mirror is what centres the name")
        XCTAssertTrue(capsule.contains(".opacity(0)"), "the mirror carries no ink")
        XCTAssertTrue(capsule.contains(".allowsHitTesting(false)"), "the mirror is not a second clickable back button")
        XCTAssertTrue(capsule.contains(".accessibilityHidden(true)"), "the mirror is not a second back button to VoiceOver")
        XCTAssertTrue(capsule.contains("CappedWidthLayout(maxWidth: titleWidthLimit)"), "a long name truncates instead of widening the plate")
        XCTAssertTrue(capsule.contains(".truncationMode(.middle)"), "the .floretta extension survives")
        XCTAssertFalse(capsule.contains(".frame(width:"), "no guessed back-button width: the mirror is the control itself")
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
        XCTAssertFalse(
            backItem.contains(".appleGlassChrome"),
            "a bar item is already glass; a plate inside it is the double-glass bug"
        )
        XCTAssertFalse(backItem.contains("HStack"))
        XCTAssertFalse(backItem.contains("ultraThinMaterial"))
        XCTAssertFalse(backItem.contains(".blur("))
        XCTAssertFalse(
            ios.contains(".sharedBackgroundVisibility(.hidden)"),
            "hiding the shared background is what left the filename as bare text"
        )
        XCTAssertTrue(ios.contains("\"document.title\""))
        XCTAssertTrue(source.contains("ToolbarItem(id: \"document.navigation\", placement: .navigation)"))
    }

    /// ④ 2026-11-16: the iPhone filename is wrapped in a capsule.
    /// It is a system bar item and nothing else: the bar paints the capsule, so
    /// the name is no longer two bare glyphs over the canvas, and this file adds
    /// no plate of its own (that would be double glass inside the bar item).
    func testIPhoneFilenameIsWrappedInOneSystemGlassCapsule() throws {
        let source = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let toolbar = try slice(source, from: "private var editorToolbar", until: "private var editorEvents")
        let ios = try slice(toolbar, from: "#if os(iOS)", until: "#if !os(macOS)")
        let spacer = try XCTUnwrap(ios.range(of: "ToolbarSpacer(.fixed, placement: .cancellationAction)"))
        let titleArea = String(ios[spacer.upperBound...])

        XCTAssertTrue(titleArea.contains("ToolbarItem(placement: .cancellationAction)"))
        XCTAssertTrue(titleArea.contains("Text(verbatim: documentTitle)"))
        XCTAssertTrue(titleArea.contains("\"document.title\""))
        XCTAssertTrue(titleArea.contains(".accessibilityLabel(documentTitle)"))
        XCTAssertFalse(titleArea.contains("sharedBackgroundVisibility"), "the system capsule stays visible")
        XCTAssertFalse(titleArea.contains(".appleGlassChrome"), "the bar capsule is the only plate")
        XCTAssertFalse(titleArea.contains("Capsule()"), "no hand-drawn capsule behind the name")
        XCTAssertFalse(titleArea.contains("Material"), "no hand-rolled material behind the name")
    }

    /// ② 2026-11-16: 配色 is a compact bubble, not a sheet.
    /// Two columns by three rows of cards, the remaining schemes behind
    /// 「更多主题…」, and one tap applies plus closes. The bubble must ask for
    /// `.presentationCompactAdaptation(.popover)`, or a compact iPhone turns it
    /// back into a full-page sheet.
    func testThemePickerIsACompactPopoverBubble() throws {
        let source = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let menu = try slice(source, from: "private var moreMenu", until: "/// `menu(.more)` minus")
        let bubble = try slice(source, from: "private struct BranchThemePopover", until: "private struct BranchThemeEntry")
        let presets = try slice(source, from: "private var entries: [BranchThemeEntry]", until: "private func isSelected")

        XCTAssertTrue(menu.contains(".popover(isPresented: $showThemes, arrowEdge: .top)"), "the bubble hangs under the ••• button")
        XCTAssertTrue(menu.contains("BranchThemePopover("))
        XCTAssertTrue(bubble.contains(".presentationCompactAdaptation(.popover)"), "without this a compact iPhone degrades the popover to a sheet")
        XCTAssertTrue(bubble.contains("static let popoverWidth: CGFloat = 320"), "the bubble is about 320pt wide")
        XCTAssertTrue(bubble.contains("static let visibleRows = 3"), "three rows of cards are visible")
        XCTAssertEqual(
            bubble.components(separatedBy: "GridItem(.flexible()").count - 1,
            2,
            "the card grid is two columns"
        )
        XCTAssertTrue(bubble.contains("LazyVGrid("))
        XCTAssertTrue(bubble.contains("theme.popover.more"))
        XCTAssertTrue(bubble.contains("text(\"更多主题…\")"))
        // One tap applies and closes; no 完成 button, no second sheet.
        XCTAssertTrue(bubble.contains("onSelect(entry.id)"))
        XCTAssertTrue(bubble.contains("dismiss()"))
        XCTAssertFalse(bubble.contains("NavigationStack"), "a bubble is not a navigation container")

        // The existing catalogs and persistence are reused unchanged.
        XCTAssertTrue(presets.contains("MapThemeCatalog.all"))
        XCTAssertTrue(presets.contains("MapColorPresetCatalog.all"))
        XCTAssertEqual(
            source.components(separatedBy: "BranchThemeSheet(themeID:").count - 1,
            1,
            "the iOS sheet is replaced by the bubble; only the macOS sheet remains"
        )

        // iOS has no theme sheet left; macOS keeps it.
        let sheet = try XCTUnwrap(source.range(of: ".sheet(isPresented: $showThemes)"))
        let before = String(source[..<sheet.lowerBound].suffix(180))
        XCTAssertTrue(before.contains("#if os(macOS)"), "the sheet is macOS-only now")
    }

    /// ⑥ 2026-11-16: 大纲 gets its rows on the panel's own grid, real 44pt
    /// header targets, and system motion.
    func testOutlinePanelAlignmentTouchTargetsAndMotion() throws {
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let panel = try slice(editor, from: "private var outlinePanel", until: "private var markdownBanner")
        let stack = try slice(editor, from: "private var canvasStack", until: "private var bottomBarRow")
        let outline = try repoFile("Floretta/Shared/Outline/OutlineView.swift")
        let glass = try repoFile("Floretta/Shared/Shell/AppleGlassChrome.swift")
        let inset = try slice(glass, from: "func sidebarSelectionInset()", until: "private struct AppleGlassChromePlate")

        // Header controls: a 44pt square target holding a glyph, and no second
        // plate — the panel's sidebar glass stays the only surface.
        XCTAssertTrue(panel.contains(".frame(width: 44, height: 44)"))
        XCTAssertTrue(panel.contains(".contentShape(Rectangle())"))
        XCTAssertFalse(panel.contains(".appleGlassChrome"), "a header circle inside the panel is a second plate")
        XCTAssertTrue(panel.contains("outline.wide"))
        XCTAssertTrue(panel.contains("outline.close"))

        // Width: a compact phone fills the width instead of leaving a 300pt
        // column with a sliver of canvas beside it.
        XCTAssertTrue(stack.contains("outlineFillsWidth"))
        XCTAssertTrue(editor.contains("horizontalSizeClass == .compact"))

        // Rows: the 12pt leading matches the header padding, and every row is a
        // 44pt touch target.
        XCTAssertTrue(inset.contains("EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12)"))
        XCTAssertTrue(outline.contains(".frame(minHeight: 44, alignment: .leading)"))

        // Motion: the system snappy spring, skipped when reduce motion is on.
        XCTAssertTrue(stack.contains(".transition(.move(edge: .leading).combined(with: .opacity))"))
        XCTAssertTrue(
            stack.contains(".animation(ChromeMotion.resolved(ChromeMotion.panel, reduceMotion: reduceMotion), value: showOutline)"),
            "the panel uses the system snappy curve through ChromeMotion, which hands back nil for Reduce Motion"
        )
        XCTAssertTrue(editor.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
        XCTAssertTrue(outline.contains("withAnimation(.snappy)"))
        XCTAssertTrue(outline.contains("reduceMotion"))
    }

    /// ⑥ 沉浸模式: the only control is one 44pt glass circle, icon only, and it
    /// fades in and out instead of snapping on.
    func testImmersiveExitIsOneFortyFourPointGlassCircle() throws {
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let exit = try slice(editor, from: ".overlay(alignment: .topTrailing)", until: ".onChange(of: session.zen.isActive)")

        XCTAssertTrue(exit.contains("Image(systemName: \"xmark\")"))
        XCTAssertFalse(exit.contains("Label(\"退出全屏沉浸\""), "immersive chrome is icon only, not a text pill")
        XCTAssertTrue(exit.contains("EditorStatusBarChrome.controlMinHeight"), "44pt on iOS")
        XCTAssertTrue(exit.contains(".contentShape(Circle())"))
        XCTAssertTrue(exit.contains(".appleGlassChrome(.canvasFloatingButton)"))
        XCTAssertTrue(exit.contains(".accessibilityLabel(text(\"退出全屏沉浸\"))"))
        XCTAssertTrue(exit.contains("zen.exit"))
        XCTAssertTrue(exit.contains(".transition(.opacity.combined(with: .scale(scale: 0.98)))"))
        XCTAssertTrue(exit.contains(".animation(reduceMotion ? nil : .snappy, value: isExitAffordanceRevealed)"))
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
        let conditional = try XCTUnwrap(toolbar.range(of: "if macToolbarSnapshot.showsToolbar"))

        XCTAssertLessThan(title.lowerBound, conditional.lowerBound, "back and title stay installed regardless of editor selection/focus chrome")
    }

    func testMacToolbarSnapshotAndEditorHostingDoNotCarrySelectionIdentity() throws {
        let source = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let snapshot = try slice(source, from: "private struct MacToolbarSnapshot", until: "/// Canvas and inspector live in their own SwiftUI graph.")
        let host = try slice(source, from: "private struct MacEditorContentHost", until: "private struct MacEditorContent:")

        XCTAssertTrue(snapshot.contains("EditorToolbarContext"))
        XCTAssertTrue(snapshot.contains("documentTitle"))
        XCTAssertTrue(snapshot.contains("showsToolbar"))
        XCTAssertFalse(snapshot.contains("selectedNodeID"), "selection identity must not invalidate the outer toolbar graph")
        XCTAssertTrue(host.contains("NSViewRepresentable"))
        XCTAssertTrue(host.contains("NSHostingView<AnyView>"))
        XCTAssertTrue(host.contains("MacEditorContent(editor: editor"))
        XCTAssertTrue(source.contains("onChange(of: liveToolbarSnapshot, initial: true)"))
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
        let inspector = try slice(source, from: "private var documentInfo", until: "private var relationshipLabelSection")
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
        XCTAssertTrue(canvas.contains(".truncationMode(.middle)"), "the .floretta extension is kept")
        XCTAssertTrue(canvas.contains("CappedWidthLayout(maxWidth: titleWidthLimit)"))
        XCTAssertFalse(canvas.contains(".frame(maxWidth:"), "a flexible frame fills its cap and stretches the capsule")
        XCTAssertTrue(core.contains("public static func canvasTitleWidthLimit(rowWidth: CGFloat)"))
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

    /// The view-mode control is one button that flips 地图模式 ⇄ 聚焦模式. No ▾
    /// menu and no second click, and the glyph is the mode that is showing.
    func testViewModeControlIsAToggleNotAMenu() throws {
        let bar = try repoFile("Floretta/Shared/Shell/EditorStatusBar.swift")

        XCTAssertTrue(bar.contains("private var viewModeToggle"))
        XCTAssertFalse(bar.contains("private var viewModeMenu"))
        XCTAssertFalse(bar.contains("ForEach(DocumentViewMode.allCases"), "a mode picker means a menu")

        let toggle = try slice(bar, from: "private var viewModeToggle", until: "private var outlineToggle")
        XCTAssertTrue(toggle.contains("Button {"))
        XCTAssertTrue(
            toggle.contains("changeViewMode(session.viewMode == .map ? .focus : .map)"),
            "one tap flips the mode; the state write stays one line inside the helper"
        )
        XCTAssertTrue(toggle.contains("session.viewMode = mode"), "the helper is the only writer")
        XCTAssertTrue(toggle.contains("withAnimation(.snappy)"), "chrome state changes with the system spring")
        XCTAssertTrue(toggle.contains("reduceMotion"), "减少动态效果 turns the animation off")
        XCTAssertFalse(toggle.contains("Menu {"), "a menu needs a second click and a ▾")
        XCTAssertFalse(toggle.contains("menuIndicator"))
        XCTAssertTrue(toggle.contains(".buttonStyle(.plain)"))
        XCTAssertTrue(toggle.contains(".help(Text(verbatim:"))
        XCTAssertTrue(toggle.contains(".accessibilityLabel(Text(verbatim:"))
        XCTAssertTrue(toggle.contains(".accessibilityHint("))
        XCTAssertTrue(toggle.contains("accessibilityIdentifier(\"statusBar.views\")"))

        // The two glyphs are the stock SF Symbols the rest of the app uses.
        XCTAssertEqual(EditorToolbarCatalog.command(.mapMode).symbol, "map")
        XCTAssertEqual(EditorToolbarCatalog.command(.focusMode).symbol, "scope")
        let symbols = try slice(bar, from: "private func viewModeSymbol", until: "private func viewModeTitle")
        XCTAssertTrue(symbols.contains("EditorToolbarCatalog.command(.mapMode).symbol"))
        XCTAssertTrue(symbols.contains("EditorToolbarCatalog.command(.focusMode).symbol"))
    }

    /// Every glyph in the two bottom capsules is a vector SF Symbol at one
    /// weight (regular) and one size (`chromeFontSize`), inside one icon box, and
    /// every control keeps a tooltip and an accessibility label.
    func testBottomCapsuleIconsShareOneWeightAndSize() throws {
        let bar = try repoFile("Floretta/Shared/Shell/EditorStatusBar.swift")
        let source = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")

        let symbol = try slice(bar, from: "private func statusSymbol", until: "// MARK: text")
        XCTAssertTrue(symbol.contains("size: EditorStatusBarChrome.chromeFontSize, weight: .regular"))
        XCTAssertTrue(symbol.contains("width: EditorStatusBarChrome.iconButtonSize"))
        XCTAssertTrue(symbol.contains("height: EditorStatusBarChrome.iconButtonSize"))
        XCTAssertTrue(symbol.contains("symbolRenderingMode(.monochrome)"))
        XCTAssertFalse(symbol.contains("weight: .bold"))
        XCTAssertFalse(bar.contains("weight: .medium"))

        // help() + accessibilityLabel() on every control of the status capsule.
        XCTAssertGreaterThanOrEqual(bar.components(separatedBy: ".help(").count - 1, 5)
        XCTAssertGreaterThanOrEqual(bar.components(separatedBy: ".accessibilityLabel(").count - 1, 5)

        // The sheet capsule's own glyphs follow the same weight.
        let canvas = try slice(source, from: "private var canvasTabBar", until: "private var currentCanvasIndex")
        XCTAssertTrue(canvas.contains("chevron.down"))
        XCTAssertTrue(canvas.contains("weight: .regular"))
        XCTAssertTrue(canvas.contains("EditorStatusBarChrome.chromeFontSize"))
        XCTAssertFalse(canvas.contains(".font(.caption2)"))
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
