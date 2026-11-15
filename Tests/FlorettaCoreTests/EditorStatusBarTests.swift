import XCTest
import FlorettaCore

final class EditorStatusBarTests: XCTestCase {
    func testStatusCapsuleOwnsTheZoomControl() throws {
        XCTAssertEqual(
            EditorStatusBarModel.controls,
            [.topics, .zoomMenu, .viewMode, .outline, .immersive]
        )
        XCTAssertEqual(EditorStatusBarChrome.controlMinHeight, 44)
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
        XCTAssertEqual(EditorStatusBarChrome.controlMinHeight, 44)
        XCTAssertEqual(EditorStatusBarChrome.horizontalInset, 12)
        XCTAssertEqual(EditorStatusBarChrome.bottomInset, 6)
        XCTAssertEqual(EditorStatusBarChrome.capsuleGap, 8)
        XCTAssertEqual(EditorStatusBarChrome.canvasTitleMaxWidth, 240)
        XCTAssertEqual(EditorBottomBarLayout.minimumWidthWithDivider, 200)

        XCTAssertTrue(EditorBottomBarLayout.showsSheetDivider(rowWidth: 1200, statusWidth: 320))
        XCTAssertTrue(EditorBottomBarLayout.showsSheetDivider(rowWidth: 560, statusWidth: 320))
        XCTAssertFalse(EditorBottomBarLayout.showsSheetDivider(rowWidth: 420, statusWidth: 320))
        XCTAssertTrue(EditorBottomBarLayout.showsSheetDivider(rowWidth: 300, statusWidth: 0))
        XCTAssertFalse(EditorBottomBarLayout.showsSheetDivider(rowWidth: 0, statusWidth: 0))
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
