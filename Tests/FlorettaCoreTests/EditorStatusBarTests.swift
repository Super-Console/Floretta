import XCTest
import FlorettaCore

final class EditorStatusBarTests: XCTestCase {
    func testBarHostsCensusZoomAndViewSwitcher() {
        XCTAssertEqual(
            EditorStatusBarModel.controls,
            [.topicCensus, .zoomMenu, .viewSwitcher]
        )
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
            from: ".safeAreaInset(edge: .bottom, spacing: 0)",
            until: "private var tagFilterBanner"
        )
        let modes = try slice(
            try repoFile("Floretta/Shared/Shell/AppSettings.swift"),
            from: "enum DocumentViewMode",
            until: "enum PNGScalePreference"
        )

        XCTAssertTrue(inset.contains("TopicStatusBar("))
        XCTAssertTrue(inset.contains("topicCensus.census(of: session.document)"))
        XCTAssertTrue(inset.contains("EditorStatusControls("))
        XCTAssertTrue(inset.contains("accessibilityIdentifier(\"statusBar\")"))
        XCTAssertTrue(editor.contains("session.zen.chrome.showsStatusBar"))
        XCTAssertFalse(editor.contains("camera.zoom"))
        XCTAssertFalse(editor.contains("zoomMenu"))
        XCTAssertFalse(editor.contains(".editorStatusBar("))

        XCTAssertTrue(bar.contains("accessibilityIdentifier(\"statusBar.zoom\")"))
        XCTAssertTrue(bar.contains("accessibilityIdentifier(\"statusBar.views\")"))
        XCTAssertTrue(bar.contains("ForEach(DocumentViewMode.allCases"))
        XCTAssertTrue(bar.contains("camera.zoom(to: stop)"))
        XCTAssertTrue(bar.contains("camera.fitToContent()"))
        XCTAssertFalse(bar.contains("TitleCountSupply"))
        XCTAssertFalse(bar.contains("safeAreaInset"))

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
