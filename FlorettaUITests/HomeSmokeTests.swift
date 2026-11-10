import XCTest

/// Smoke coverage for the iPhone home shell: the recent-page title, a live
/// settings tab, document rows that actually open, and a way back out.
final class HomeSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHomeTitleSettingsNewMapAndRows() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FlorettaUITest"]
        app.launch()

        let titleBar = homeTitle(app)
        XCTAssertTrue(titleBar.waitForExistence(timeout: 15), "首页导航标题「最近」不可见")
        assertNoDeadRecentRow(app, titleBar: titleBar)
        XCTAssertTrue(app.descendants(matching: .any)["home.recent"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.element.exists)

        app.tabBars.buttons["设置"].tap()
        let language = app.staticTexts["语言"]
        XCTAssertTrue(language.waitForExistence(timeout: 5))
        XCTAssertTrue(language.isHittable)
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))

        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(homeTitle(app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.newMap"].waitForExistence(timeout: 5))
        XCTAssertFalse(language.isHittable)

        let rows = app.buttons.matching(identifier: "home.recent.row")
        XCTAssertGreaterThan(rows.count, 0, "首页没有可点的导图行")
        let labels = (0..<rows.count).map { rows.element(boundBy: $0).label }
        XCTAssertEqual(Set(labels).count, labels.count)
        for label in labels {
            let row = app.buttons.matching(identifier: "home.recent.row")
                .matching(NSPredicate(format: "label == %@", label))
                .firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5), label)
            row.tap()
            let back = app.buttons["basicChain.back"]
            XCTAssertTrue(back.waitForExistence(timeout: 8), "点了「\(label)」没有进入导图")
            XCTAssertFalse(app.buttons["home.newMap"].exists)
            XCTAssertFalse(homeTitle(app).exists)
            back.tap()
            XCTAssertTrue(homeTitle(app).waitForExistence(timeout: 8), "退出导图后没有回到首页")
            XCTAssertTrue(app.buttons["home.newMap"].waitForExistence(timeout: 5))
        }

        app.buttons["home.newMap"].tap()
        let back = app.buttons["basicChain.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 8), "新建导图没有进入画布")
        XCTAssertTrue(app.buttons["未命名"].waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(homeTitle(app).waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["home.newMap"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func homeTitle(_ app: XCUIApplication) -> XCUIElement {
        app.navigationBars["最近"]
    }

    /// The old sidebar row was a button labeled 「最近」. The navigation title
    /// may also be exposed as a button; that one sits inside the bar.
    @MainActor
    private func assertNoDeadRecentRow(_ app: XCUIApplication, titleBar: XCUIElement) {
        let rows = app.buttons.matching(NSPredicate(format: "label == %@", "最近"))
        for index in 0..<rows.count {
            let row = rows.element(boundBy: index)
            guard row.isHittable else { continue }
            XCTAssertTrue(
                titleBar.frame.contains(row.frame),
                "首页还有一个点了没反应的「最近」行"
            )
        }
    }
}
