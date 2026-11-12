import XCTest
import FlorettaCore

final class EditorStatusBarTests: XCTestCase {
    func testBarHostsZoomAndViewSwitcherOnly() {
        XCTAssertEqual(
            EditorStatusBarModel.controls,
            [.zoomMenu, .viewSwitcher]
        )
        XCTAssertEqual(EditorStatusBarChrome.featherInset, 12)
        XCTAssertGreaterThanOrEqual(EditorStatusBarChrome.featherInset, 8)
        XCTAssertLessThanOrEqual(EditorStatusBarChrome.featherInset, 16)
        XCTAssertEqual(EditorStatusBarChrome.controlMinHeight, 44)
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

    func testStatusBarSourceHostsRealControlsOnly() throws {
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
        XCTAssertFalse(status.contains("appleGlassChrome"))
        XCTAssertFalse(status.contains(".shadow("))
        XCTAssertTrue(editor.contains("session.zen.chrome.showsStatusBar"))
        XCTAssertFalse(inset.contains("camera.zoom"))
        XCTAssertFalse(inset.contains("zoomMenu"))
        XCTAssertFalse(editor.contains(".editorStatusBar("))

        XCTAssertTrue(bar.contains("accessibilityIdentifier(\"statusBar\")"))
        XCTAssertTrue(bar.contains("accessibilityIdentifier(\"statusBar.zoom\")"))
        XCTAssertTrue(bar.contains("accessibilityIdentifier(\"statusBar.views\")"))
        XCTAssertTrue(bar.contains("ForEach(DocumentViewMode.allCases"))
        XCTAssertTrue(bar.contains("camera.zoom(to: stop)"))
        XCTAssertTrue(bar.contains("camera.fitToContent()"))
        XCTAssertTrue(bar.contains("editorStatusBarFeather"))
        XCTAssertTrue(bar.contains(".mask"))
        XCTAssertTrue(bar.contains(".blur(radius:"))
        XCTAssertTrue(bar.contains("struct EditorOverflowCensus"))
        XCTAssertTrue(bar.contains("\"主题 %lld\""))
        XCTAssertTrue(bar.contains("\"字数 %lld\""))
        XCTAssertTrue(bar.contains("\"字符数 %lld\""))
        XCTAssertTrue(bar.contains("status.topics"))
        XCTAssertTrue(bar.contains("status.words"))
        XCTAssertTrue(bar.contains("status.characters"))
        XCTAssertFalse(bar.contains("appleGlassChrome"))
        XCTAssertFalse(bar.contains(".shadow("))
        XCTAssertFalse(bar.contains("TitleCountSupply"))
        XCTAssertFalse(bar.contains("safeAreaInset"))
        XCTAssertFalse(bar.contains("TopicStatusBar"))

        XCTAssertTrue(modes.contains("case map"))
        XCTAssertTrue(modes.contains("case focus"))
        XCTAssertEqual(modes.components(separatedBy: "case ").count - 1, 2)

        for invented in ["大纲", "演说", "鱼骨", "时间轴", "逻辑图", "Slider(", "Timer", "TimelineView", "scheduledTimer"] {
            XCTAssertFalse(bar.contains(invented), invented)
            XCTAssertFalse(core.contains(invented), invented)
        }
        for counting in ["isLetter", "unicodeScalars", "CharacterSet", "enumerateSubstrings"] {
            XCTAssertFalse(core.contains(counting), counting)
            XCTAssertFalse(bar.contains(counting), counting)
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
