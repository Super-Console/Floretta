import XCTest
import FlorettaCore

final class EditorStatusBarTests: XCTestCase {
    func testBarHostsCapsuleZoomAndViewSwitcher() {
        XCTAssertEqual(
            EditorStatusBarModel.controls,
            [.topicCapsule, .zoomMenu, .viewSwitcher]
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

    func testCapsuleUsesTopicCountUntilATitleCounterExists() {
        let document = MindMapDocument(
            title: "图",
            roots: [
                MindMapNode(text: "中文English\n下一行", children: [MindMapNode(text: "子")]),
            ],
            freeNodes: [MindMapNode(text: "自由")]
        )
        XCTAssertEqual(document.topicCount, 3)
        XCTAssertNil(TitleCountSupplyReader.supply(for: document))
        let capsule = TopicCountCapsuleModel(document: document)
        XCTAssertEqual(capsule.topicCount, document.topicCount)
        XCTAssertFalse(capsule.showsWordCount)
        XCTAssertNil(capsule.titles)
        XCTAssertNil(capsule.breakdown)
    }

    func testSuppliedTitleCountsAppearInTheCapsuleBreakdown() {
        let supply = TitleCountSupply(wordCount: 7, characterCount: 9)
        let capsule = TopicCountCapsuleModel(topicCount: 3, titles: supply)
        XCTAssertTrue(capsule.showsWordCount)
        XCTAssertEqual(
            capsule.breakdown,
            TopicCountBreakdown(topicCount: 3, wordCount: 7, characterCount: 9)
        )
    }

    func testStatusBarSourceHostsRealControlsOnly() throws {
        let bar = try repoFile("Floretta/Shared/Shell/EditorStatusBar.swift")
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let core = try repoFile("FlorettaCore/Layout/EditorStatusBar.swift")
        let modes = try slice(
            try repoFile("Floretta/Shared/Shell/AppSettings.swift"),
            from: "enum DocumentViewMode",
            until: "enum PNGScalePreference"
        )

        XCTAssertTrue(bar.contains("accessibilityIdentifier(\"statusBar\")"))
        XCTAssertTrue(bar.contains("accessibilityIdentifier(\"statusBar.topics\")"))
        XCTAssertTrue(bar.contains("accessibilityIdentifier(\"statusBar.zoom\")"))
        XCTAssertTrue(bar.contains("accessibilityIdentifier(\"statusBar.views\")"))
        XCTAssertTrue(bar.contains("TitleCountSupplyReader.supply(for: session.document)"))
        XCTAssertTrue(bar.contains("ForEach(DocumentViewMode.allCases"))
        XCTAssertTrue(bar.contains("camera.zoom(to: stop)"))
        XCTAssertTrue(bar.contains("camera.fitToContent()"))
        XCTAssertTrue(bar.contains("placement: .bottomBar"))
        XCTAssertTrue(bar.contains("safeAreaInset(edge: .bottom"))
        XCTAssertTrue(bar.contains("if let breakdown = model.breakdown"))
        XCTAssertTrue(editor.contains("session.zen.chrome.showsStatusBar"))
        XCTAssertTrue(editor.contains(".editorStatusBar("))
        XCTAssertFalse(editor.contains("camera.zoom"))
        XCTAssertFalse(editor.contains("zoomMenu"))

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
