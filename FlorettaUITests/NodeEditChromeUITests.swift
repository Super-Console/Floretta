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

        let chrome = app.descendants(matching: .any)["canvas.node.chrome"]
        XCTAssertTrue(chrome.waitForExistence(timeout: 15))
        let before = try Probe(chrome.value as? String)
        XCTAssertEqual(before.mode, "idle")
        XCTAssertEqual(before.fill, "#800020", "iOS 节点填充不是酒红")
        XCTAssertLessThan(before.width, 88, "样例节点已经比旧的编辑框最小宽度还宽")
        let beforeFrame = chrome.frame

        chrome.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let editing = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ AND value CONTAINS %@", "canvas.node.chrome", "mode=edit")
        ).firstMatch
        XCTAssertTrue(editing.waitForExistence(timeout: 8))
        let after = try Probe(editing.value as? String)
        XCTAssertEqual(after.fill, before.fill, "iOS 进入编辑后填充色变了")
        XCTAssertEqual(after.width, before.width, accuracy: 1, "iOS 进入编辑后宽度变了")
        XCTAssertEqual(after.height, before.height, accuracy: 1, "iOS 进入编辑后高度变了")
        XCTAssertEqual(editing.frame.width, beforeFrame.width, accuracy: 1)
        XCTAssertEqual(editing.frame.height, beforeFrame.height, accuracy: 1)
        XCTAssertEqual(editing.frame.minX, beforeFrame.minX, accuracy: 1)
        XCTAssertEqual(editing.frame.minY, beforeFrame.minY, accuracy: 1)
    }

    private struct Probe {
        var mode: String
        var fill: String
        var width: CGFloat
        var height: CGFloat

        init(_ raw: String?) throws {
            let text = try XCTUnwrap(raw)
            var fields: [String: String] = [:]
            for part in text.split(separator: ";") {
                let pieces = part.split(separator: "=", maxSplits: 1).map(String.init)
                if pieces.count == 2 {
                    fields[pieces[0]] = pieces[1]
                }
            }
            mode = try XCTUnwrap(fields["mode"])
            fill = try XCTUnwrap(fields["fill"])
            width = CGFloat(try XCTUnwrap(Double(try XCTUnwrap(fields["w"]))))
            height = CGFloat(try XCTUnwrap(Double(try XCTUnwrap(fields["h"]))))
        }
    }
}
