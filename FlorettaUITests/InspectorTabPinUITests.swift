import XCTest

/// The inspector's segmented control stays pinned while the page under it changes.
///
/// The product title is 「演说」. A short page used to recenter the whole column,
/// so this records the control's frame on 样式 (a tall form) and requires the
/// same origin and size after 演说, 导图, and back.
final class InspectorTabPinUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSegmentedControlFrameStaysFixedAcrossTabs() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-FlorettaUITest",
            "-FlorettaOpenInspector",
            "-FlorettaLanguage", "zh-Hans",
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN",
        ]
        app.launch()

        app.buttons["home.newMap"].tap()
        XCTAssertTrue(app.buttons["basicChain.back"].waitForExistence(timeout: 8), "新建导图没有进入画布")

        var tabs = app.segmentedControls["inspector.tabs"]
        if !tabs.waitForExistence(timeout: 8) {
            tabs = app.segmentedControls.firstMatch
        }
        XCTAssertTrue(tabs.waitForExistence(timeout: 2), "检查器分段控件没有出现")
        XCTAssertTrue(marker(app, "形状").waitForExistence(timeout: 5), "样式页没有出现")

        let pinned = settledFrame(tabs)
        XCTAssertGreaterThan(pinned.width, 40, "分段控件宽度异常：\(describe(pinned))")
        XCTAssertGreaterThan(pinned.height, 8, "分段控件高度异常：\(describe(pinned))")

        show(app, tabs: tabs, segment: "演说", index: 1, appeared: "尚未实现", disappeared: "形状")
        assertSameFrame(settledFrame(tabs), pinned)

        show(app, tabs: tabs, segment: "导图", index: 2, appeared: "文档大小", disappeared: "尚未实现")
        assertSameFrame(settledFrame(tabs), pinned)

        show(app, tabs: tabs, segment: "样式", index: 0, appeared: "形状", disappeared: "文档大小")
        assertSameFrame(settledFrame(tabs), pinned)
    }

    @MainActor
    private func show(
        _ app: XCUIApplication,
        tabs: XCUIElement,
        segment title: String,
        index: Int,
        appeared: String,
        disappeared: String
    ) {
        let labeled = tabs.buttons[title]
        let segment = labeled.waitForExistence(timeout: 2) ? labeled : tabs.buttons.element(boundBy: index)
        XCTAssertTrue(segment.waitForExistence(timeout: 3), title)
        segment.tap()
        XCTAssertTrue(marker(app, appeared).waitForExistence(timeout: 5), "点了「\(title)」没有换到对应的页")
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: marker(app, disappeared)
        )
        let result = XCTWaiter.wait(for: [gone], timeout: 3)
        XCTAssertEqual(result, .completed, "点了「\(title)」之后「\(disappeared)」还在")
    }

    @MainActor
    private func marker(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any)[label]
    }

    /// Tab changes animate. The assertion is the settled frame, which is the
    /// one that used to sit in the middle of the inspector.
    @MainActor
    private func settledFrame(_ element: XCUIElement) -> CGRect {
        var last = element.frame
        var matches = 0
        let deadline = Date().addingTimeInterval(2)
        while matches < 3, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            let now = element.frame
            if near(now.minX, last.minX), near(now.minY, last.minY),
               near(now.width, last.width), near(now.height, last.height) {
                matches += 1
            } else {
                matches = 0
                last = now
            }
        }
        return element.frame
    }

    private func near(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) <= 0.5
    }

    private func assertSameFrame(
        _ actual: CGRect,
        _ expected: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let message = "分段控件 frame 变了：\(describe(expected)) → \(describe(actual))"
        XCTAssertEqual(actual.origin.x, expected.origin.x, accuracy: 1, message, file: file, line: line)
        XCTAssertEqual(actual.origin.y, expected.origin.y, accuracy: 1, message, file: file, line: line)
        XCTAssertEqual(actual.size.width, expected.size.width, accuracy: 1, message, file: file, line: line)
        XCTAssertEqual(actual.size.height, expected.size.height, accuracy: 1, message, file: file, line: line)
    }

    private func describe(_ frame: CGRect) -> String {
        String(format: "(%.1f, %.1f, %.1f×%.1f)", frame.minX, frame.minY, frame.width, frame.height)
    }
}
