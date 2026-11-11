import XCTest

/// Smoke coverage for the iPhone home shell: the recent-page title, a live
/// settings tab, document rows that actually open, and a way back out.
final class HomeSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHomeTitleSettingsNewMapAndRows() throws {
        let app = launchHome()

        let titleBar = homeTitle(app)
        XCTAssertTrue(titleBar.waitForExistence(timeout: 15), "首页导航标题「最近」不可见")
        assertNoDeadRecentRow(app, titleBar: titleBar)
        XCTAssertTrue(app.descendants(matching: .any)["home.recent"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.element.exists)

        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.staticTexts["语言"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))

        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(homeTitle(app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.newMap"].waitForExistence(timeout: 5))

        let rows = app.buttons.matching(identifier: "home.recent.row")
        XCTAssertGreaterThan(rows.count, 0, "首页没有可点的导图行")
        let labels = (0..<rows.count).map { rows.element(boundBy: $0).label }
        XCTAssertEqual(Set(labels).count, labels.count)
        for label in labels {
            let row = app.buttons.matching(identifier: "home.recent.row")
                .matching(NSPredicate(format: "label == %@", label))
                .firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5), label)
            let thumbnail = row.descendants(matching: .any)["home.recent.thumbnail"]
            XCTAssertTrue(thumbnail.exists, "「\(label)」缺少最近列表缩略区域")
            XCTAssertGreaterThan(thumbnail.frame.width, 0, "「\(label)」缩略区域宽度为空")
            XCTAssertGreaterThan(thumbnail.frame.height, 0, "「\(label)」缩略区域高度为空")
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
        let documentTitle = app.buttons["document.title"]
        XCTAssertTrue(documentTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(documentTitle.label, "未命名")
        back.tap()
        XCTAssertTrue(homeTitle(app).waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["home.newMap"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testEditorViewSwitchAndFeatureEntryPoints() throws {
        let app = launchHome()
        let newMap = app.buttons["home.newMap"]
        XCTAssertTrue(newMap.waitForExistence(timeout: 15), "首页没有「新建导图」")
        newMap.tap()

        let back = app.buttons["basicChain.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 8), "新建导图没有进入画布")
        let title = app.buttons["document.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "编辑器标题不存在")

        let viewPicker = app.descendants(matching: .any)["statusBar.views"]
        XCTAssertTrue(viewPicker.waitForExistence(timeout: 5), "画布/聚焦视图切换器不存在")
        XCTAssertTrue(viewPicker.isEnabled, "画布/聚焦视图切换器不可用")
        let viewButtons = viewPicker.buttons
        XCTAssertGreaterThanOrEqual(viewButtons.count, 2, "视图切换器缺少选项")
        viewButtons.element(boundBy: 1).tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5), "切换视图后编辑器标题消失")
        viewButtons.element(boundBy: 0).tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5), "切回画布后编辑器标题消失")

        let insert = app.descendants(matching: .any)["editor.insert"]
        XCTAssertTrue(insert.waitForExistence(timeout: 5), "插入菜单入口不存在")
        insert.tap()
        let summary = app.buttons["insert.summary"]
        let boundary = app.buttons["insert.boundary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "插入菜单没有概要项")
        XCTAssertTrue(boundary.waitForExistence(timeout: 5), "插入菜单没有边界项")
        XCTAssertFalse(summary.isEnabled, "未选中节点时概要项应禁用")
        XCTAssertFalse(boundary.isEnabled, "未选中节点时边界项应禁用")
        let attachment = app.buttons["insert.attachment"]
        XCTAssertTrue(attachment.waitForExistence(timeout: 5), "插入菜单没有附件入口（音视频文件选择共用该入口）")
        XCTAssertTrue(attachment.isEnabled, "音视频文件选择入口不可用")
        app.buttons["insert.region"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["editor.canvas"].exists, "插入专区后画布消失")

        var more = app.descendants(matching: .any)["editor.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "更多菜单入口不存在")
        more.tap()
        let theme = app.buttons["theme.menu"]
        XCTAssertTrue(theme.waitForExistence(timeout: 5), "更多菜单中没有配色入口")
        theme.tap()
        let themeSheet = app.descendants(matching: .any)["theme.sheet"]
        XCTAssertTrue(themeSheet.waitForExistence(timeout: 5), "配色入口没有打开面板")
        XCTAssertTrue(app.buttons["theme.close"].exists, "配色面板缺少关闭入口")
        app.buttons["theme.close"].tap()

        more = app.descendants(matching: .any)["editor.more"]
        more.tap()
        let outline = app.buttons["outline.open"]
        XCTAssertTrue(outline.waitForExistence(timeout: 5), "更多菜单中没有大纲入口")
        outline.tap()
        XCTAssertTrue(app.descendants(matching: .any)["editor.outline"].waitForExistence(timeout: 5), "大纲入口没有打开大纲")
        more = app.descendants(matching: .any)["editor.more"]
        more.tap()
        let closeOutline = app.buttons["outline.open"]
        XCTAssertTrue(closeOutline.waitForExistence(timeout: 5), "更多菜单中没有关闭大纲的入口")
        closeOutline.tap()
        XCTAssertFalse(app.descendants(matching: .any)["editor.outline"].exists, "关闭大纲后面板仍然存在")
        let addCanvas = app.buttons["canvas.tab.add"]
        XCTAssertTrue(addCanvas.waitForExistence(timeout: 5), "编辑器中没有新建画布入口")
        XCTAssertTrue(addCanvas.isEnabled, "新建画布入口不可用")
        addCanvas.tap()
        XCTAssertTrue(app.buttons["canvas.tab.1"].waitForExistence(timeout: 5), "新画布没有加入画布标签栏")

        more = app.descendants(matching: .any)["editor.more"]
        more.tap()
        let tagFilter = app.buttons["tagFilter.open"]
        XCTAssertTrue(tagFilter.waitForExistence(timeout: 5), "更多菜单中没有标签筛选入口")
        tagFilter.tap()
        let tagSheet = app.descendants(matching: .any)["tagFilter.sheet"]
        XCTAssertTrue(tagSheet.waitForExistence(timeout: 5), "标签筛选入口没有打开面板")
        XCTAssertTrue(app.buttons["tagFilter.close"].exists, "标签筛选面板缺少关闭入口")
        app.buttons["tagFilter.close"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5), "关闭标签筛选后没有回到编辑器")
        back.tap()
        XCTAssertTrue(homeTitle(app).waitForExistence(timeout: 8), "退出编辑器后没有回到首页")
    }

    /// The home chrome is a system tab bar, a toolbar menu, and `.searchable`.
    /// The old three-icon capsule kept 「模板库」 as a visible toolbar button.
    @MainActor
    func testHomeUsesSystemTabBarMenuAndSearchNotACapsule() throws {
        let app = launchHome()
        let titleBar = homeTitle(app)
        XCTAssertTrue(titleBar.waitForExistence(timeout: 15), "首页导航标题「最近」不可见")

        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["设置"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["home.actionCapsule"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["home.tabCapsule"].exists)
        XCTAssertFalse(
            titleBar.buttons["home.templates"].exists,
            "模板库仍是工具栏上的独立按钮，三图标胶囊还在"
        )

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "首页没有系统搜索框")
        XCTAssertTrue(search.isHittable)

        XCTAssertTrue(titleBar.buttons["home.newMap"].exists)
        let menu = titleBar.buttons["home.toolbarMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        XCTAssertTrue(app.buttons["home.templates"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.open"].waitForExistence(timeout: 5))
        app.buttons["home.templates"].tap()
        XCTAssertTrue(app.navigationBars["模板库"].waitForExistence(timeout: 5))
        app.buttons["关闭"].tap()
        XCTAssertTrue(titleBar.waitForExistence(timeout: 5))
    }

    @MainActor
    private func launchHome() -> XCUIApplication {
        let app = XCUIApplication()
        // Pin the smoke suite to Simplified Chinese. The language setting can
        // switch these labels; the assertions below still check the source strings.
        app.launchArguments = [
            "-FlorettaUITest",
            "-FlorettaLanguage", "zh-Hans",
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN",
        ]
        app.launch()
        return app
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

/// The editor back button used to be a chevron nested in the filename stack.
/// That glyph's accessibility frame is well under 44pt and not square. A
/// system toolbar button's frame is the circular platter: at least 44×44.
final class EditorBackButtonHitAreaTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEditorBackButtonHitAreaIsAtLeastFortyFourPointsAndRoughlyCircular() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-FlorettaUITest",
            "-FlorettaLanguage", "zh-Hans",
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN",
        ]
        app.launch()

        let newMap = app.buttons["home.newMap"]
        XCTAssertTrue(newMap.waitForExistence(timeout: 15), "首页没有「新建导图」")
        newMap.tap()

        let back = app.buttons["basicChain.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 8), "新建导图后没有左上返回按钮")
        let frame = back.frame
        XCTAssertGreaterThanOrEqual(
            frame.width,
            44,
            "返回按钮点击宽度 \(frame.width) pt，小于 44"
        )
        XCTAssertGreaterThanOrEqual(
            frame.height,
            44,
            "返回按钮点击高度 \(frame.height) pt，小于 44"
        )
        let longSide = max(frame.width, frame.height)
        let shortSide = min(frame.width, frame.height)
        XCTAssertGreaterThan(shortSide, 0)
        XCTAssertLessThanOrEqual(
            longSide / shortSide,
            1.15,
            "返回按钮点击区域应接近圆形，宽 \(frame.width) 高 \(frame.height)"
        )
    }
}
