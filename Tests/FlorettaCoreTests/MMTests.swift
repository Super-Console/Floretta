import FlorettaCore
import XCTest

final class MMTests: XCTestCase {
    func testExportImportPreservesTextHierarchyOrderFoldAndSide() throws {
        let root = MindMapNode(
            text: "中心",
            children: [
                MindMapNode(text: "右题", side: .right, children: [
                    MindMapNode(text: "孙", isCollapsed: true),
                ]),
                MindMapNode(text: "左题", side: .left),
            ]
        )
        let document = MindMapDocument(title: "中心", roots: [root])
        let imported = try FlorettaMMCodec.importMap(try FlorettaMMCodec.export(document))
        XCTAssertEqual(imported.roots.count, 1)
        assertShape(imported.roots[0], root)
    }

    func testRichContentPlainTextAndLinkRoundTrip() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <map version="1.0.1">
          <node TEXT="">
            <richcontent TYPE="NODE"><html><head></head><body><p>Hello <b>world</b></p><p>Rich &amp; plain</p></body></html></richcontent>
            <node TEXT="子" LINK="https://example.com/a?b=1&amp;c=2" FOLDED="true" POSITION="left">
              <richcontent TYPE="NOTE"><html><head></head><body><p>备注</p></body></html></richcontent>
            </node>
          </node>
        </map>
        """
        let imported = try FlorettaMMCodec.importMap(Data(xml.utf8))
        XCTAssertEqual(imported.roots[0].text, "Hello world\nRich & plain")
        let child = imported.roots[0].children[0]
        XCTAssertEqual(child.text, "子")
        XCTAssertEqual(child.note, "备注")
        XCTAssertEqual(child.link, "https://example.com/a?b=1&c=2")
        XCTAssertTrue(child.isCollapsed)
        XCTAssertEqual(child.side, .left)

        let again = try FlorettaMMCodec.importMap(try FlorettaMMCodec.export(imported))
        assertShape(again.roots[0], imported.roots[0])
    }

    func testImportExportImportKeepsSiblingOrder() throws {
        let xml = """
        <map version="1.0.1">
          <node TEXT="根">
            <node TEXT="甲" POSITION="right"/>
            <node TEXT="乙" POSITION="left"/>
            <node TEXT="丙" POSITION="right"/>
          </node>
        </map>
        """
        let first = try FlorettaMMCodec.importMap(Data(xml.utf8))
        XCTAssertEqual(first.roots[0].children.map(\.text), ["甲", "乙", "丙"])
        XCTAssertEqual(first.roots[0].children.map(\.side), [.right, .left, .right])
        let third = try FlorettaMMCodec.importMap(try FlorettaMMCodec.export(first))
        assertShape(third.roots[0], first.roots[0])
    }

    func testDifferingRichContentIsKeptInTheNote() throws {
        let xml = """
        <map version="1.0.1">
          <node TEXT="短">
            <richcontent TYPE="NODE"><html><body><p>更长的富文本</p></body></html></richcontent>
          </node>
        </map>
        """
        let imported = try FlorettaMMCodec.importMap(Data(xml.utf8))
        XCTAssertEqual(imported.roots[0].text, "短")
        XCTAssertEqual(imported.roots[0].note, "更长的富文本")
    }

    func testUnknownElementsAreNotNodes() throws {
        let xml = """
        <map version="1.0.1">
          <node TEXT="父">
            <icon BUILTIN="idea"/>
            <font NAME="SansSerif"/>
            <node TEXT="子"/>
          </node>
        </map>
        """
        let imported = try FlorettaMMCodec.importMap(Data(xml.utf8))
        XCTAssertEqual(imported.roots[0].children.map(\.text), ["子"])
    }

    func testUnknownPositionAndExternalEntityFail() {
        let badSide = Data("<map version=\"1.0.1\"><node TEXT=\"根\" POSITION=\"up\"/></map>".utf8)
        XCTAssertThrowsError(try FlorettaMMCodec.importMap(badSide)) { error in
            XCTAssertEqual(error as? FlorettaMMError, .unknownPosition("up"))
        }
        let xxe = Data("""
        <!DOCTYPE map [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>
        <map version="1.0.1"><node TEXT="&xxe;"/></map>
        """.utf8)
        XCTAssertThrowsError(try FlorettaMMCodec.importMap(xxe))
    }

    func testMultipleRootsExportUnderTheTitle() throws {
        let document = MindMapDocument(
            title: "两根",
            roots: [MindMapNode(text: "甲"), MindMapNode(text: "乙")]
        )
        let imported = try FlorettaMMCodec.importMap(try FlorettaMMCodec.export(document))
        XCTAssertEqual(imported.roots.count, 1)
        XCTAssertEqual(imported.roots[0].text, "两根")
        XCTAssertEqual(imported.roots[0].children.map(\.text), ["甲", "乙"])
    }

    private func assertShape(
        _ actual: MindMapNode,
        _ expected: MindMapNode,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.text, expected.text, file: file, line: line)
        XCTAssertEqual(actual.note, expected.note, file: file, line: line)
        XCTAssertEqual(actual.isCollapsed, expected.isCollapsed, file: file, line: line)
        XCTAssertEqual(actual.link, expected.link, file: file, line: line)
        XCTAssertEqual(actual.side, expected.side, file: file, line: line)
        XCTAssertEqual(actual.children.count, expected.children.count, file: file, line: line)
        for pair in zip(actual.children, expected.children) {
            assertShape(pair.0, pair.1, file: file, line: line)
        }
    }
}
