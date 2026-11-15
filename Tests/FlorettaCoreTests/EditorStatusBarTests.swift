import XCTest
import FlorettaCore

final class EditorStatusBarTests: XCTestCase {
    func testStatusCapsuleOwnsTheZoomControl() throws {
        #if os(macOS)
        XCTAssertEqual(
            EditorStatusBarModel.controls,
            [.topics, .zoomMenu, .pointerMode, .viewMode, .outline, .immersive],
            "the Mac capsule adds the pointer / hand tool beside the view mode"
        )
        #else
        XCTAssertEqual(
            EditorStatusBarModel.controls,
            [.topics, .zoomMenu, .viewMode, .outline, .immersive]
        )
        #endif
        #if os(macOS)
        XCTAssertEqual(EditorStatusBarChrome.controlMinHeight, 28)
        #else
        XCTAssertEqual(EditorStatusBarChrome.controlMinHeight, 44)
        #endif
        let bar = try repoFile("Floretta/Shared/Shell/EditorStatusBar.swift")
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        // TD-003: the capsule is the one zoom entry, so no bar draws a second.
        XCTAssertTrue(bar.contains("statusBar.zoom"))
        XCTAssertTrue(bar.contains("EditorStatusZoomChoice.menu"))
        XCTAssertFalse(editor.contains("toolbarControl(.zoom)"))
        XCTAssertFalse(editor.contains("macItem(.zoom)"))
        XCTAssertFalse(editor.contains("\"editor.zoom\""))
        XCTAssertEqual(EditorToolbarCatalog.command(.zoom).customization, .menuOnly)
        XCTAssertTrue(bar.contains("StatusCensusBreakdown"))
    }

    func testCompactToolbarLeavesOnlyInsertAndTheOverflowEllipsis() {
        XCTAssertEqual(
            EditorToolbarLayout.visibleItems(for: .compact),
            [.insert, .more]
        )
        XCTAssertEqual(
            EditorToolbarLayout.visibleItems(for: .regular),
            EditorToolbarCatalog.defaultToolbarItems
        )
        XCTAssertEqual(EditorToolbarLayout.visibleItems(for: .regular).last, .more)
        let ellipsis = EditorToolbarCatalog.commands.filter { $0.symbol == "ellipsis" }
        XCTAssertEqual(ellipsis.map(\.id), [.more])
    }

    func testZoomMenuIsTheExistingStopsPlusFit() {
        XCTAssertEqual(
            EditorStatusZoomChoice.menu.map(\.menuTitle),
            ["50%", "75%", "100%", "125%", "150%", "200%", "300%", "400%", "适应窗口"]
        )
        XCTAssertEqual(
            EditorStatusZoomChoice.menu.compactMap(\.fixedScale),
            ZoomStop.allCases.map(\.scale)
        )
        XCTAssertEqual(EditorStatusZoomChoice.menu.last, .fitWindow)
        XCTAssertNil(EditorStatusZoomChoice.fitWindow.fixedScale)
    }

    func testZoomStopUpdatesTheExistingChromePercent() {
        var chrome = CanvasChrome.standard
        XCTAssertEqual(chrome.zoomPercent, 100)
        EditorStatusBarModel.apply(.stop(.twoHundred), to: &chrome)
        XCTAssertEqual(chrome.zoomPercent, 200)
        XCTAssertEqual(chrome.zoomPercent, ZoomStop.twoHundred.percent)
        let beforeFit = chrome.zoomPercent
        EditorStatusBarModel.apply(.fitWindow, to: &chrome)
        XCTAssertEqual(chrome.zoomPercent, beforeFit)
    }

    func testStatusCapsuleShowsFiveRealControls() throws {
        let bar = try repoFile("Floretta/Shared/Shell/EditorStatusBar.swift")
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let core = try repoFile("FlorettaCore/Layout/EditorStatusBar.swift")
        let inset = try slice(
            editor,
            from: ".overlay(alignment: .bottom)",
            until: "private var tagFilterBanner"
        )
        let modes = try slice(
            try repoFile("Floretta/Shared/Shell/AppSettings.swift"),
            from: "enum DocumentViewMode",
            until: "enum PNGScalePreference"
        )
        let status = try slice(
            editor,
            from: "if session.zen.chrome.showsStatusBar",
            until: "private var showsCanvasTabs"
        )

        XCTAssertTrue(inset.contains("EditorStatusStrip("))
        XCTAssertTrue(status.contains("EditorStatusStrip("))
        XCTAssertFalse(status.contains("TopicStatusBar("))
        XCTAssertFalse(status.contains(".shadow("))
        XCTAssertTrue(inset.contains("census: statusCensus"))
        XCTAssertTrue(inset.contains("showOutline: $showOutline"))
        XCTAssertTrue(inset.contains("canvas.tabs"))
        XCTAssertTrue(inset.contains("appleGlassChrome(.bottomBarCapsule)"))
        XCTAssertFalse(inset.contains("floatingPanel"))
        XCTAssertTrue(inset.contains("EditorStatusBarChrome.controlMinHeight"))
        XCTAssertTrue(editor.contains("session.zen.chrome.showsStatusBar"))
        XCTAssertFalse(inset.contains("camera.zoom"))
        XCTAssertFalse(inset.contains("zoomMenu"))

        // One glass plate, five controls, no hand-painted blur or shadow.
        XCTAssertTrue(bar.contains(".appleGlassChrome(.bottomBarCapsule)"))
        XCTAssertTrue(bar.contains("accessibilityIdentifier(\"statusBar\")"))
        XCTAssertTrue(bar.contains("accessibilityIdentifier(\"statusBar.capsule\")"))
        XCTAssertTrue(bar.contains("accessibilityIdentifier(\"status.topics\")"))
        XCTAssertTrue(bar.contains("accessibilityIdentifier(\"statusBar.zoom\")"))
        XCTAssertTrue(bar.contains("accessibilityIdentifier(\"statusBar.views\")"))
        XCTAssertTrue(bar.contains("accessibilityIdentifier(\"status.outline\")"))
        XCTAssertTrue(bar.contains("accessibilityIdentifier(\"status.immersive\")"))
        XCTAssertTrue(bar.contains("EditorToolbarCatalog.command(.outline)"))
        XCTAssertTrue(bar.contains("EditorToolbarCatalog.command(.immersive)"))
        XCTAssertTrue(bar.contains("EditorToolbarCatalog.command(.mapMode)"))
        XCTAssertFalse(bar.contains("viewModeMenu"), "the mode control is a toggle, not a menu")
        XCTAssertTrue(bar.contains("viewModeToggle"))
        XCTAssertTrue(bar.contains("session.enterZen()"))
        XCTAssertFalse(bar.contains(".shadow("))
        XCTAssertFalse(bar.contains("linearGradient"))
        XCTAssertFalse(bar.contains(".blur("))
        XCTAssertFalse(bar.contains("ultraThinMaterial"))
        XCTAssertFalse(bar.contains("TopicStatusBar"))
        XCTAssertTrue(bar.contains("struct StatusCensusBreakdown"))
        XCTAssertTrue(bar.contains("\"主题 %lld\""))
        XCTAssertTrue(bar.contains("\"字数 %lld\""))
        XCTAssertTrue(bar.contains("\"字符数 %lld\""))
        XCTAssertFalse(bar.contains("TitleCountSupply"))
        XCTAssertFalse(bar.contains("safeAreaInset"))

        // macOS hovers, iPad and iPhone tap; both paths are wired.
        XCTAssertTrue(bar.contains(".onHover(perform: hoverCensus)"))
        XCTAssertTrue(bar.contains(".popover(isPresented: $showsCensus"))

        XCTAssertTrue(modes.contains("case map"))
        XCTAssertTrue(modes.contains("case focus"))
        XCTAssertEqual(modes.components(separatedBy: "case ").count - 1, 2)

        // 演说 is the one XMind capsule control the person said not to build.
        for absent in ["演说", "鱼骨", "时间轴", "逻辑图", "Slider(", "Timer", "TimelineView", "scheduledTimer"] {
            XCTAssertFalse(bar.contains(absent), absent)
            XCTAssertFalse(core.contains(absent), absent)
        }
        for counting in ["isLetter", "unicodeScalars", "CharacterSet", "enumerateSubstrings"] {
            XCTAssertFalse(core.contains(counting), counting)
            XCTAssertFalse(bar.contains(counting), counting)
        }
    }

    /// One set of numbers for both bottom capsules, plus the give-way order on a
    /// narrow window: the sheet name truncates, then its divider goes, and the
    /// status capsule is never compressed.
    func testBottomBarSharesOneInsetOneHeightAndOneFitRule() {
        #if os(macOS)
        XCTAssertEqual(EditorStatusBarChrome.controlMinHeight, 28)
        #else
        XCTAssertEqual(EditorStatusBarChrome.controlMinHeight, 44)
        #endif
        XCTAssertEqual(EditorStatusBarChrome.chromeFontSize, 13)
        XCTAssertEqual(EditorStatusBarChrome.iconButtonSize, 28)
        XCTAssertEqual(EditorStatusBarChrome.capsuleHorizontalPadding, 10)
        XCTAssertEqual(EditorStatusBarChrome.capsuleVerticalPadding, 3)
        XCTAssertEqual(EditorStatusBarChrome.capsuleControlSpacing, 10)
        XCTAssertEqual(EditorStatusBarChrome.horizontalInset, 12)
        XCTAssertEqual(EditorStatusBarChrome.bottomInset, 6)
        XCTAssertEqual(EditorStatusBarChrome.capsuleGap, 8)
        XCTAssertEqual(EditorStatusBarChrome.canvasTitleMaxWidth, 240)
        XCTAssertEqual(EditorStatusBarChrome.canvasTitleMinWidth, 120)
        XCTAssertEqual(EditorStatusBarChrome.canvasTitleWidthFraction, 0.30)
        XCTAssertEqual(EditorBottomBarLayout.minimumWidthWithDivider, 200)

        XCTAssertTrue(EditorBottomBarLayout.showsSheetDivider(rowWidth: 1200, statusWidth: 320))
        XCTAssertTrue(EditorBottomBarLayout.showsSheetDivider(rowWidth: 560, statusWidth: 320))
        XCTAssertFalse(EditorBottomBarLayout.showsSheetDivider(rowWidth: 420, statusWidth: 320))
        XCTAssertTrue(EditorBottomBarLayout.showsSheetDivider(rowWidth: 300, statusWidth: 0))
        XCTAssertFalse(EditorBottomBarLayout.showsSheetDivider(rowWidth: 0, statusWidth: 0))
    }

    /// TD-002 sheet name: centred, middle-truncated, and capped at a share of
    /// the window instead of a fixed box. The fixture is 60 汉字 plus the
    /// `.floretta` extension — the name that used to spill out of the capsule
    /// and widen the bottom row.
    func testSheetNameIsCentredCappedInTheMiddleAndNeverStretchesTheCapsule() throws {
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let bar = try repoFile("Floretta/Shared/Shell/EditorStatusBar.swift")
        let canvas = try slice(editor, from: "private var canvasTabBar", until: "private var currentCanvasIndex")

        // Centred, middle-truncated name inside the capped slot.
        XCTAssertTrue(canvas.contains(".multilineTextAlignment(.center)"))
        XCTAssertTrue(canvas.contains(".truncationMode(.middle)"))
        XCTAssertTrue(canvas.contains("CappedWidthLayout(maxWidth: canvasTitleWidthLimit)"))
        XCTAssertFalse(canvas.contains("alignment: .leading"), "a leading frame left the name off-centre in a wide box")
        XCTAssertFalse(canvas.contains(".frame(maxWidth:"), "a flexible frame fills its cap and stretches the capsule")
        XCTAssertTrue(bar.contains("struct CappedWidthLayout: Layout"))
        XCTAssertTrue(bar.contains("subview.sizeThatFits"))
        XCTAssertTrue(bar.contains("bounds.midX - width / 2"), "the slot centres its child")

        // The cap follows the window: 30% of the measured row, floor 120,
        // ceiling 240, and the floor while the row has not been measured.
        let longName = String(repeating: "长", count: 60) + ".floretta"
        XCTAssertEqual(longName.count, 69)
        XCTAssertEqual(EditorBottomBarLayout.canvasTitleWidthLimit(rowWidth: 2000), 240, accuracy: 0.001)
        XCTAssertEqual(EditorBottomBarLayout.canvasTitleWidthLimit(rowWidth: 1200), 240, accuracy: 0.001)
        XCTAssertEqual(EditorBottomBarLayout.canvasTitleWidthLimit(rowWidth: 700), 210, accuracy: 0.001)
        XCTAssertEqual(EditorBottomBarLayout.canvasTitleWidthLimit(rowWidth: 400), 120, accuracy: 0.001)
        XCTAssertEqual(EditorBottomBarLayout.canvasTitleWidthLimit(rowWidth: 200), 120, accuracy: 0.001)
        XCTAssertEqual(EditorBottomBarLayout.canvasTitleWidthLimit(rowWidth: 0), 120, accuracy: 0.001)

        // A CJK glyph advances one em at `chromeFontSize`, so 69 characters need
        // at least 897 pt: the long name always truncates, whatever the window.
        let naturalWidth = CGFloat(longName.count) * EditorStatusBarChrome.chromeFontSize
        for rowWidth in [600.0, 900.0, 1400.0, 2200.0] as [CGFloat] {
            let limit = EditorBottomBarLayout.canvasTitleWidthLimit(rowWidth: rowWidth)
            XCTAssertLessThan(limit, naturalWidth, "the long name is truncated, never laid out in full")
            XCTAssertLessThanOrEqual(limit, EditorStatusBarChrome.canvasTitleMaxWidth)
            XCTAssertGreaterThanOrEqual(limit, EditorStatusBarChrome.canvasTitleMinWidth)
            XCTAssertLessThanOrEqual(limit, rowWidth * EditorStatusBarChrome.canvasTitleWidthFraction + 0.001)
        }
    }

    /// Spacing and hit targets of the status capsule, from the one set of
    /// constants: 10 pt between controls, 16 pt between groups measured across
    /// the hairline, and an icon hit target that never drops below 28x28.
    func testStatusCapsuleSpacingAndIconHitTargets() throws {
        let bar = try repoFile("Floretta/Shared/Shell/EditorStatusBar.swift")
        let core = try repoFile("FlorettaCore/Layout/EditorStatusBar.swift")

        XCTAssertEqual(EditorStatusBarChrome.capsuleControlSpacing, 10)
        XCTAssertEqual(EditorStatusBarChrome.capsuleGroupSpacing, 16)
        XCTAssertEqual(EditorStatusBarChrome.capsuleSeparatorWidth, 1)
        XCTAssertEqual(EditorStatusBarChrome.capsuleSeparatorHeight, 16)
        XCTAssertEqual(EditorStatusBarChrome.capsuleSeparatorInset, 7.5, accuracy: 0.001)

        // Hit target: the frame the symbols draw in, floored at 28x28, while
        // the glyph keeps its 13 pt optical size.
        XCTAssertEqual(EditorStatusBarChrome.iconButtonHitMinSize, 28)
        XCTAssertGreaterThanOrEqual(
            EditorStatusBarChrome.iconButtonSize,
            EditorStatusBarChrome.iconButtonHitMinSize
        )
        let symbol = try slice(bar, from: "private func statusSymbol", until: "// MARK: text")
        XCTAssertTrue(symbol.contains("width: EditorStatusBarChrome.iconButtonSize"))
        XCTAssertTrue(symbol.contains("height: EditorStatusBarChrome.iconButtonSize"))
        XCTAssertTrue(symbol.contains("size: EditorStatusBarChrome.chromeFontSize"))
        XCTAssertTrue(symbol.contains(".contentShape(Rectangle())"))

        // The row keeps no spacing of its own: the hairline carries the group
        // gap, and the icon group carries the control spacing.
        let capsule = try slice(bar, from: "private var capsule", until: "// MARK: counts")
        XCTAssertTrue(capsule.contains("HStack(spacing: 0)"))
        XCTAssertTrue(capsule.contains("EditorStatusBarChrome.capsuleSeparatorInset"))
        XCTAssertTrue(capsule.contains("EditorStatusBarChrome.capsuleSeparatorWidth"))
        XCTAssertTrue(capsule.contains("EditorStatusBarChrome.capsuleSeparatorHeight"))
        let group = try slice(bar, from: "private var viewControls", until: "/// A hairline")
        XCTAssertTrue(group.contains("HStack(spacing: EditorStatusBarChrome.capsuleControlSpacing)"))
        for control in ["viewModeToggle", "outlineToggle", "fullScreenToggle"] {
            XCTAssertTrue(group.contains(control), control)
        }

        // Every number lives in core; no literal spacing or icon box is left in
        // the bar, which is how the old 8 / 14 drift came back.
        XCTAssertTrue(core.contains("public static let capsuleGroupSpacing: CGFloat = 16"))
        XCTAssertTrue(core.contains("public static let iconButtonHitMinSize: CGFloat = 28"))
        XCTAssertFalse(bar.contains("spacing: 8"))
        XCTAssertFalse(bar.contains("spacing: 14"))
        XCTAssertFalse(bar.contains("width: 22"))
        XCTAssertFalse(bar.contains("height: 22"))
        XCTAssertFalse(bar.contains(".frame(width: 1, height: 16)"), "the hairline uses the constants")
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
