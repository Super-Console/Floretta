import FlorettaCore
import XCTest

final class OPMLMarkdownTests: XCTestCase {
    func testMarkdownExportPlacesSubtitleUnderItsHeading() {
        let node = MindMapNode(text: "Title", subtitle: "Secondary")
        XCTAssertTrue(FlorettaMarkdown.export(MindMapDocument(title: "t", roots: [node])).contains("# Title\n  > Secondary"))
    }

    func testOPMLExportImportPreservesTextNotesHierarchyAndOrder() throws {
        let root = MindMapNode(
            text: "中心",
            note: "根备注",
            children: [
                MindMapNode(text: "甲", note: "第一行\n第二行"),
                MindMapNode(text: "乙", children: [MindMapNode(text: "孙")]),
            ]
        )
        let document = MindMapDocument(title: "大纲", roots: [root])
        let imported = try FlorettaOPMLCodec.importOutline(try FlorettaOPMLCodec.export(document))
        XCTAssertEqual(imported.title, "大纲")
        XCTAssertEqual(imported.roots.count, 1)
        assertShape(imported.roots[0], root)
        XCTAssertFalse(imported.roots[0].isCollapsed)
        XCTAssertNil(imported.roots[0].side)
    }

    func testOPMLImportExportImportAndURL() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>导入</title></head>
          <body>
            <outline text="父" _note="父注">
              <outline text="子" url="https://example.com/a?b=1&amp;c=2"/>
              <outline text="弟" note="备用备注"/>
            </outline>
          </body>
        </opml>
        """
        let first = try FlorettaOPMLCodec.importOutline(Data(xml.utf8))
        XCTAssertEqual(first.title, "导入")
        XCTAssertEqual(first.roots[0].text, "父")
        XCTAssertEqual(first.roots[0].note, "父注")
        XCTAssertEqual(first.roots[0].children.map(\.text), ["子", "弟"])
        XCTAssertEqual(first.roots[0].children[0].link, "https://example.com/a?b=1&c=2")
        XCTAssertEqual(first.roots[0].children[1].note, "备用备注")
        XCTAssertFalse(first.roots[0].children[0].isCollapsed)
        XCTAssertNil(first.roots[0].children[0].side)
        let third = try FlorettaOPMLCodec.importOutline(try FlorettaOPMLCodec.export(first))
        assertShape(third.roots[0], first.roots[0])
        XCTAssertEqual(third.title, first.title)
    }

    func testOPMLKeepsBothTextAndTitleWhenTheyDiffer() throws {
        let xml = """
        <opml version="2.0"><body>
          <outline text="显示" title="另一标题"/>
        </body></opml>
        """
        let imported = try FlorettaOPMLCodec.importOutline(Data(xml.utf8))
        XCTAssertEqual(imported.roots[0].text, "显示")
        XCTAssertEqual(imported.roots[0].note, "另一标题")
    }

    func testOPMLUnknownElementsAreNotNodes() throws {
        let xml = """
        <opml version="2.0">
          <head><title>T</title><expansionState>1,2</expansionState></head>
          <body>
            <outline text="父"><hook/><outline text="子"/></outline>
          </body>
        </opml>
        """
        let imported = try FlorettaOPMLCodec.importOutline(Data(xml.utf8))
        XCTAssertEqual(imported.roots[0].children.map(\.text), ["子"])
    }

    func testOPMLExternalEntityFails() {
        let xxe = Data("""
        <!DOCTYPE opml [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>
        <opml version="2.0"><body><outline text="&xxe;"/></body></opml>
        """.utf8)
        XCTAssertThrowsError(try FlorettaOPMLCodec.importOutline(xxe))
    }

    func testMarkdownExportWritesHeadingsNotesAndLinks() {
        let tree = MindMapNode(
            text: "根",
            note: "根备注\n第二行",
            children: [
                MindMapNode(
                    text: "子",
                    note: "子备注",
                    link: "https://example.com/a",
                    children: [MindMapNode(text: "孙")]
                ),
            ]
        )
        let markdown = FlorettaMarkdown.export(MindMapDocument(title: "md", roots: [tree]))
        XCTAssertTrue(markdown.contains("# 根\n"))
        XCTAssertTrue(markdown.contains("> 根备注\n> 第二行\n"))
        XCTAssertTrue(markdown.contains("## [子](https://example.com/a)\n"))
        XCTAssertTrue(markdown.contains("> 子备注\n"))
        XCTAssertTrue(markdown.contains("### 孙\n"))
        XCTAssertFalse(markdown.contains("根备注\n第二行\n###"))
    }

    private func assertShape(
        _ actual: MindMapNode,
        _ expected: MindMapNode,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.text, expected.text, file: file, line: line)
        XCTAssertEqual(actual.note, expected.note, file: file, line: line)
        XCTAssertEqual(actual.link, expected.link, file: file, line: line)
        XCTAssertEqual(actual.children.count, expected.children.count, file: file, line: line)
        for pair in zip(actual.children, expected.children) {
            assertShape(pair.0, pair.1, file: file, line: line)
        }
    }
}
