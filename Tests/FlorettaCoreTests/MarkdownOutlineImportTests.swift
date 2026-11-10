import FlorettaCore
import XCTest

final class MarkdownOutlineImportTests: XCTestCase {
    func testHeadingsAndListsBecomeOneHierarchy() throws {
        let text = """
        # 根
        - 甲
          - 孙
        - 乙
        ## 丙
        - 丁

        """
        let imported = try FlorettaMarkdown.importOutline(text)
        XCTAssertEqual(imported.title, "根")
        XCTAssertEqual(imported.roots.map(\.text), ["根"])
        XCTAssertEqual(imported.roots[0].children.map(\.text), ["甲", "乙", "丙"])
        XCTAssertEqual(imported.roots[0].children[0].children.map(\.text), ["孙"])
        XCTAssertEqual(imported.roots[0].children[2].children.map(\.text), ["丁"])
        assertPlainTopics(imported.roots)
    }

    func testListOnlyOutlineAndMarkerVariants() throws {
        let text = "- 根\n  * 星\n    + 加\n      1. 序\n- 弟\n"
        let imported = try FlorettaMarkdown.importOutline(text)
        XCTAssertEqual(imported.title, "Markdown")
        XCTAssertEqual(imported.roots.map(\.text), ["根", "弟"])
        XCTAssertEqual(imported.roots[0].children.map(\.text), ["星"])
        XCTAssertEqual(imported.roots[0].children[0].children.map(\.text), ["加"])
        XCTAssertEqual(imported.roots[0].children[0].children[0].children.map(\.text), ["序"])
        let exported = FlorettaMarkdown.export(imported)
        XCTAssertFalse(exported.contains("\n- "))
        XCTAssertFalse(exported.contains("\n* "))
        XCTAssertFalse(exported.contains("\n+ "))
        XCTAssertTrue(exported.contains("# 根\n"))
        XCTAssertTrue(exported.contains("## 星\n"))
        XCTAssertTrue(exported.contains("### 加\n"))
        XCTAssertTrue(exported.contains("#### 序\n"))
        XCTAssertTrue(exported.contains("# 弟\n"))
        let again = try FlorettaMarkdown.importOutline(exported)
        XCTAssertEqual(shape(again.roots), shape(imported.roots))
        XCTAssertEqual(FlorettaMarkdown.export(again), exported)
    }

    func testFourSpaceNestIsOneChildAndTwoSpaceNestIsOneChild() throws {
        let wide = try FlorettaMarkdown.importOutline("- 父\n    - 子\n")
        XCTAssertEqual(wide.roots[0].text, "父")
        XCTAssertEqual(wide.roots[0].children.map(\.text), ["子"])
        XCTAssertTrue(wide.roots[0].children[0].children.isEmpty)

        let tight = try FlorettaMarkdown.importOutline("- 父\n  - 子\n    - 孙\n")
        XCTAssertEqual(tight.roots[0].children[0].text, "子")
        XCTAssertEqual(tight.roots[0].children[0].children.map(\.text), ["孙"])

        let tabbed = try FlorettaMarkdown.importOutline("- 父\n\t- 子\n")
        XCTAssertEqual(tabbed.roots[0].children.map(\.text), ["子"])
    }

    func testHeadingAfterAListIsNotItsChild() throws {
        let imported = try FlorettaMarkdown.importOutline("- 先\n  - 子\n## 后\n- 尾\n")
        XCTAssertEqual(imported.roots.map(\.text), ["先", "后"])
        XCTAssertEqual(imported.roots[0].children.map(\.text), ["子"])
        XCTAssertEqual(imported.roots[1].children.map(\.text), ["尾"])
        XCTAssertFalse(imported.roots[1].children.contains { $0.text == "先" })
    }

    func testNotesLinksAndEmptyItemsRoundTripThroughHeadingExport() throws {
        let text = """
        - [子](https://example.com/a b)
          > 子备注
          > 第二行
          - 参见 [甲](https://a.example) 和 [乙](https://b.example)
        - [ ] 待办
        - 

        """
        let imported = try FlorettaMarkdown.importOutline(text)
        XCTAssertEqual(imported.roots.map(\.text), ["子", "[ ] 待办", ""])
        XCTAssertEqual(imported.roots[0].link, "https://example.com/a b")
        XCTAssertEqual(imported.roots[0].note, "子备注\n第二行")
        XCTAssertNil(imported.roots[0].children[0].link)
        XCTAssertEqual(imported.roots[0].children[0].text, "参见 [甲](https://a.example) 和 [乙](https://b.example)")
        XCTAssertTrue(imported.roots[0].attachments.isEmpty)
        let exported = FlorettaMarkdown.export(imported)
        XCTAssertTrue(exported.contains("# [子](https://example.com/a%20b)\n"))
        XCTAssertTrue(exported.contains("> 子备注\n> 第二行\n"))
        let again = try FlorettaMarkdown.importOutline(exported)
        XCTAssertEqual(shape(again.roots), shape(imported.roots))
        XCTAssertEqual(FlorettaMarkdown.export(again), exported)
    }

    func testImageSyntaxStaysTextAndDoesNotBecomeAnAttachment() throws {
        let imported = try FlorettaMarkdown.importOutline("- ![图](assets/a.png)\n")
        XCTAssertEqual(imported.roots[0].text, "![图](assets/a.png)")
        XCTAssertNil(imported.roots[0].link)
        XCTAssertTrue(imported.roots[0].attachments.isEmpty)
        XCTAssertTrue(imported.freeNodes.isEmpty)
        XCTAssertTrue(imported.stickies.isEmpty)
    }

    func testOutlineImportIsNotTheDocumentCodec() throws {
        let text = "## 甲\n- 乙\n"
        let outline = try FlorettaMarkdown.importOutline(text)
        XCTAssertEqual(outline.roots[0].text, "甲")
        XCTAssertEqual(outline.roots[0].children.map(\.text), ["乙"])
        XCTAssertFalse(outline.roots[0].isMarkdownSectionHeading)
        XCTAssertNil(outline.markdownFrontMatter)
        XCTAssertThrowsError(try FlorettaMarkdownDocumentCodec.open(text))

        XCTAssertThrowsError(try FlorettaMarkdown.importOutline("---\ntitle: x\n---\n- 甲\n")) { error in
            XCTAssertEqual(
                error as? FlorettaMarkdownError,
                .unsupportedLine(line: 1, content: "---")
            )
        }
        XCTAssertThrowsError(try FlorettaMarkdown.importOutline("# 根\n<!-- 藏 -->\n"))
    }

    func testUnrecognizedLinesNameTheLineAndDoNotYieldAPartialTree() throws {
        XCTAssertThrowsError(try FlorettaMarkdown.importOutline("# 根\n\n这是一段正文\n- 不会留下\n")) { error in
            guard case .unsupportedLine(let line, let content) = error as? FlorettaMarkdownError else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertEqual(line, 3)
            XCTAssertEqual(content, "这是一段正文")
        }
        XCTAssertThrowsError(try FlorettaMarkdown.importOutline("> 没有节点\n")) { error in
            XCTAssertEqual(error as? FlorettaMarkdownError, .orphanNote(line: 1))
        }
        XCTAssertThrowsError(try FlorettaMarkdown.importOutline("```\n- 根\n```\n"))
        XCTAssertThrowsError(try FlorettaMarkdown.importOutline("\n\n")) { error in
            XCTAssertEqual(error as? FlorettaMarkdownError, .empty)
        }
        XCTAssertThrowsError(try FlorettaMarkdown.importOutline(Data([0xff, 0xfe]))) { error in
            XCTAssertEqual(error as? FlorettaMarkdownError, .notUTF8)
        }
    }

    func testByteOrderMarkAndCarriageReturns() throws {
        let imported = try FlorettaMarkdown.importOutline("\u{feff}# 根\r\n- 甲\r\n")
        XCTAssertEqual(imported.roots[0].text, "根")
        XCTAssertEqual(imported.roots[0].children.map(\.text), ["甲"])
    }

    func testDepthAndNodeCeilings() throws {
        var within = ""
        for level in 1...FlorettaMarkdown.maxDepth {
            within += String(repeating: "#", count: level) + " n\n"
        }
        let deep = try FlorettaMarkdown.importOutline(within)
        var node = deep.roots[0]
        var depth = 1
        while let child = node.children.first {
            node = child
            depth += 1
        }
        XCTAssertEqual(depth, FlorettaMarkdown.maxDepth)

        var over = within
        over += String(repeating: "#", count: FlorettaMarkdown.maxDepth + 1) + " n\n"
        XCTAssertThrowsError(try FlorettaMarkdown.importOutline(over)) { error in
            XCTAssertEqual(error as? FlorettaMarkdownError, .tooDeep(line: FlorettaMarkdown.maxDepth + 1))
        }

        let tooMany = String(repeating: "- n\n", count: FlorettaMarkdown.maxNodes + 1)
        XCTAssertThrowsError(try FlorettaMarkdown.importOutline(tooMany)) { error in
            XCTAssertEqual(error as? FlorettaMarkdownError, .tooManyNodes)
        }
    }

    func testImportThousandListItemsWithinBudget() throws {
        var lines = ["# 根", ""]
        for index in 0..<1_000 {
            lines.append("- 节点 \(index)")
        }
        let text = lines.joined(separator: "\n")
        _ = try FlorettaMarkdown.importOutline("- 预热\n")
        let clock = ContinuousClock()
        let start = clock.now
        let imported = try FlorettaMarkdown.importOutline(text)
        let elapsed = start.duration(to: clock.now)
        XCTAssertEqual(imported.roots[0].children.count, 1_000)
        XCTAssertLessThan(elapsed, .milliseconds(1500), "import of 1000 list items took \(elapsed)")
        let again = try FlorettaMarkdown.importOutline(FlorettaMarkdown.export(imported))
        XCTAssertEqual(again.roots[0].children.count, 1_000)
        XCTAssertEqual(again.roots[0].children[999].text, "节点 999")
    }

    private struct Shape: Equatable {
        var text: String
        var note: String
        var link: String?
        var children: [Shape]
    }

    private func shape(_ nodes: [MindMapNode]) -> [Shape] {
        nodes.map { node in
            Shape(text: node.text, note: node.note, link: node.link, children: shape(node.children))
        }
    }

    private func assertPlainTopics(_ nodes: [MindMapNode], file: StaticString = #filePath, line: UInt = #line) {
        for node in nodes {
            XCTAssertFalse(node.isMarkdownSectionHeading, file: file, line: line)
            XCTAssertFalse(node.isCollapsed, file: file, line: line)
            XCTAssertNil(node.side, file: file, line: line)
            XCTAssertTrue(node.attachments.isEmpty, file: file, line: line)
            assertPlainTopics(node.children, file: file, line: line)
        }
    }
}
