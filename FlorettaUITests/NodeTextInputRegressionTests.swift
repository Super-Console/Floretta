import XCTest

/// End-to-end regression for real text entry into an iOS canvas node.
final class NodeTextInputRegressionTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTypingIntoNodePersistsWithoutLeakingEditChrome() throws {
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

        let canvas = app.descendants(matching: .any)["editor.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 8), "新建导图后画布不存在")
        let idleNode = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "canvas.node.chrome.idle.fill-")
        ).firstMatch
        XCTAssertTrue(idleNode.waitForExistence(timeout: 8), "新建导图后中心节点探针不存在")
        let nodeFrame = idleNode.frame
        let nodeCenter = idleNode.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        nodeCenter.doubleTap()

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 8), "双击中心节点后没有进入文本编辑")
        editor.typeText("测试一二三abc")

        XCTAssertTrue(
            NSPredicate(format: "value CONTAINS %@", "测试一二三abc")
                .evaluate(with: editor),
            "节点编辑器未收到真实输入：\(String(describing: editor.value))"
        )
        let typedText = editor.value as? String ?? ""
        XCTAssertFalse(typedText.contains("mode=edit"), "节点文本泄漏编辑标记：\(typedText)")

        // Tap outside the node to commit and leave edit mode.
        app.buttons["document.title"].tap()
        XCTAssertFalse(editor.isHittable, "点击画布外后编辑器仍处于编辑状态")

        app.coordinate(withNormalizedOffset: CGVector(
            dx: nodeFrame.midX / app.frame.width,
            dy: nodeFrame.midY / app.frame.height
        )).doubleTap()
        let reopenedEditor = app.textViews.firstMatch
        XCTAssertTrue(reopenedEditor.waitForExistence(timeout: 8), "重新双击节点后没有进入编辑")
        let persistedText = reopenedEditor.value as? String ?? ""
        XCTAssertTrue(persistedText.contains("测试一二三abc"), "退出并重新进入后文本未保留：\(persistedText)")
        XCTAssertFalse(persistedText.contains("mode=edit"), "重新进入后节点文本仍泄漏编辑标记：\(persistedText)")
    }
}
