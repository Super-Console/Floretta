import XCTest

/// iPhone and iPad share the canvas editor. This target hosts Floretta-iOS,
/// so the same assertion covers both. The field publishes the fill it painted.
/// A system background, or the old 88-point minimum, fails the comparison.
final class NodeEditChromeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testIOSNodeFrameAndFillStayWhenEditing() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-FlorettaUITest",
            "-FlorettaEditChrome",
            "-FlorettaLanguage", "zh-Hans",
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN",
        ]
        app.launch()

        let idleQuery = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "canvas.node.chrome.idle.fill-")
        )
        let chrome = idleQuery.firstMatch
        XCTAssertTrue(chrome.waitForExistence(timeout: 15))
        let beforeFill = fill(from: chrome.identifier)
        XCTAssertEqual(beforeFill, "#800020", "iOS 节点填充不是酒红")
        XCTAssertLessThan(chrome.frame.width, 88, "样例节点已经比旧的编辑框最小宽度还宽")
        let beforeFrame = chrome.frame

        chrome.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let editingQuery = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "canvas.node.chrome.edit.fill-")
        )
        let editing = editingQuery.firstMatch
        XCTAssertTrue(editing.waitForExistence(timeout: 8))
        XCTAssertEqual(fill(from: editing.identifier), beforeFill, "iOS 进入编辑后填充色变了")
        XCTAssertEqual(editing.frame.width, beforeFrame.width, accuracy: 1, "iOS 进入编辑后宽度变了")
        XCTAssertEqual(editing.frame.height, beforeFrame.height, accuracy: 1, "iOS 进入编辑后高度变了")
        XCTAssertEqual(editing.frame.minX, beforeFrame.minX, accuracy: 1)
        XCTAssertEqual(editing.frame.minY, beforeFrame.minY, accuracy: 1)
    }

    private func fill(from identifier: String) -> String {
        let marker = ".fill-"
        guard let range = identifier.range(of: marker) else { return "" }
        return "#" + identifier[range.upperBound...]
    }
}
