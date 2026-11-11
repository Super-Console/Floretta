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

    /// Nothing selected used to center 「检查器」 and the segments with the brush placeholder.
    /// The header's origin y and size stay on the with-content measurement. The placeholder
    /// stays in the content area under the header.
    @MainActor
    func testHeaderStaysPutWhenNothingIsSelected() {
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

        let header = app.descendants(matching: .any)["inspector.header"]
        XCTAssertTrue(header.waitForExistence(timeout: 8), "检查器顶栏没有出现")
        XCTAssertTrue(marker(app, "形状").waitForExistence(timeout: 5), "有选中主题时样式表单没有出现")

        let pinned = settledFrame(header)
        XCTAssertGreaterThan(pinned.width, 40, "顶栏宽度异常：\(describe(pinned))")
        XCTAssertGreaterThan(pinned.height, 8, "顶栏高度异常：\(describe(pinned))")

        clearSelection(app)
        XCTAssertTrue(marker(app, "选择一个主题").waitForExistence(timeout: 5), "取消选择后没有出现空态")
        let shapeGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: marker(app, "形状")
        )
        XCTAssertEqual(XCTWaiter.wait(for: [shapeGone], timeout: 3), .completed, "取消选择后样式表单还在")

        let emptyHeader = settledFrame(header)
        assertSameFrame(emptyHeader, pinned, label: "顶栏")

        let empty = app.descendants(matching: .any)["inspector.empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5), "空态没有出现")
        assertPlaceholderSitsUnderHeader(settledFrame(empty), header: emptyHeader, name: "空态")
        assertPlaceholderSitsUnderHeader(settledFrame(marker(app, "选择一个主题")), header: emptyHeader, name: "「选择一个主题」")
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

    /// Blank canvas clears the topic selection. A compact inspector is a sheet
    /// over the canvas, so that path dismisses it, taps, and opens the inspector again.
    @MainActor
    private func clearSelection(_ app: XCUIApplication) {
        let canvas = app.descendants(matching: .any)["editor.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "画布没有出现")
        if canvas.isHittable {
            for offset in [CGVector(dx: 0.07, dy: 0.16), CGVector(dx: 0.07, dy: 0.84)] {
                canvas.coordinate(withNormalizedOffset: offset).tap()
                if marker(app, "选择一个主题").waitForExistence(timeout: 2) { return }
            }
        }

        let dismiss = app.descendants(matching: .any)["inspector.dismiss"]
        if dismiss.waitForExistence(timeout: 1) {
            dismiss.tap()
        } else {
            app.descendants(matching: .any)["inspector.header"].swipeDown()
        }
        for offset in [CGVector(dx: 0.08, dy: 0.45), CGVector(dx: 0.92, dy: 0.45)] {
            app.coordinate(withNormalizedOffset: offset).tap()
            if marker(app, "选择一个主题").waitForExistence(timeout: 2) { return }
        }
        for offset in [CGVector(dx: 0.07, dy: 0.16), CGVector(dx: 0.5, dy: 0.12)] {
            guard canvas.isHittable else { break }
            canvas.coordinate(withNormalizedOffset: offset).tap()
            if marker(app, "选择一个主题").waitForExistence(timeout: 2) { break }
        }
        if app.descendants(matching: .any)["inspector.header"].exists,
           marker(app, "选择一个主题").exists {
            return
        }
        let open = app.descendants(matching: .any)["inspector.open"]
        if !open.waitForExistence(timeout: 5) {
            let tree = app.debugDescription
            try? tree.write(toFile: "/tmp/floretta-uitest-tree.txt", atomically: true, encoding: String.Encoding.utf8)
            let more = app.descendants(matching: .any)["editor.more"]
            XCTAssertTrue(more.waitForExistence(timeout: 2), "打不开检查器（更多菜单也没有出现）")
            more.tap()
            XCTAssertTrue(open.waitForExistence(timeout: 5), "打不开检查器")
        }
        open.tap()
    }

    private func assertPlaceholderSitsUnderHeader(
        _ placeholder: CGRect,
        header: CGRect,
        name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThan(placeholder.height, 1, "\(name) 没有尺寸：\(describe(placeholder))", file: file, line: line)
        XCTAssertGreaterThan(
            placeholder.midY,
            header.maxY - 1,
            "\(name) 不在顶栏下面的内容区：顶栏 \(describe(header))，占位 \(describe(placeholder))",
            file: file,
            line: line
        )
    }

    private func assertSameFrame(
        _ actual: CGRect,
        _ expected: CGRect,
        label: String = "分段控件",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let message = "\(label) frame 变了：\(describe(expected)) → \(describe(actual))"
        XCTAssertEqual(actual.origin.x, expected.origin.x, accuracy: 1, message, file: file, line: line)
        XCTAssertEqual(actual.origin.y, expected.origin.y, accuracy: 1, message, file: file, line: line)
        XCTAssertEqual(actual.size.width, expected.size.width, accuracy: 1, message, file: file, line: line)
        XCTAssertEqual(actual.size.height, expected.size.height, accuracy: 1, message, file: file, line: line)
    }

    private func describe(_ frame: CGRect) -> String {
        String(format: "(%.1f, %.1f, %.1f×%.1f)", frame.minX, frame.minY, frame.width, frame.height)
    }
}
