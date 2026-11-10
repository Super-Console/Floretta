import FlorettaCore
import XCTest

final class MarkdownFieldTests: XCTestCase {
    func testDocumentFixturesStillRoundTripMappedFields() throws {
        for fixture in MarkdownFieldCatalog.documentFixtures {
            let data = try load(fixture.file, folder: "MarkdownAsDocument")
            let opened = try FlorettaMarkdownDocumentCodec.open(data)
            let saved = FlorettaMarkdownDocumentCodec.save(opened.document)
            let again = try FlorettaMarkdownDocumentCodec.open(saved)
            XCTAssertEqual(shape(again.document.roots), shape(opened.document.roots), fixture.file)
            XCTAssertEqual(again.document.markdownFrontMatter, opened.document.markdownFrontMatter, fixture.file)
            XCTAssertFalse(saved.contains("<!--"), fixture.file)
            XCTAssertFalse(saved.contains("##"), fixture.file)
        }
    }

    func testHeadingFixturesRoundTripAndRejectOtherLines() throws {
        let simple = try FlorettaMarkdown.importOutline(try load("simple.md", folder: "MarkdownHeading"))
        XCTAssertEqual(simple.roots.map(\.text), ["根"])
        XCTAssertEqual(simple.roots[0].children.map(\.text), ["甲", "乙"])

        let nested = try FlorettaMarkdown.importOutline(try load("nested.md", folder: "MarkdownHeading"))
        var node = nested.roots[0]
        for expected in ["第1层", "第2层", "第3层", "第4层", "第5层"] {
            XCTAssertEqual(node.text, expected)
            if expected == "第5层" {
                XCTAssertTrue(node.children.isEmpty)
            } else {
                node = try XCTUnwrap(node.children.first)
            }
        }

        let notes = try FlorettaMarkdown.importOutline(try load("notes-links.md", folder: "MarkdownHeading"))
        XCTAssertEqual(notes.roots[0].note, "根备注\n第二行")
        XCTAssertEqual(notes.roots[0].children[0].text, "子")
        XCTAssertEqual(notes.roots[0].children[0].link, "https://example.com/a")
        XCTAssertEqual(notes.roots[0].children[0].note, "子备注")
        XCTAssertEqual(notes.roots[0].children[0].children[0].text, "孙")

        for fixture in MarkdownFieldCatalog.headingFixtures {
            let first = try FlorettaMarkdown.importOutline(try load(fixture.file, folder: "MarkdownHeading"))
            let exported = FlorettaMarkdown.export(first)
            let second = try FlorettaMarkdown.importOutline(exported)
            XCTAssertEqual(shape(second.roots), shape(first.roots), fixture.file)
            XCTAssertEqual(FlorettaMarkdown.export(second), exported, fixture.file)
        }

        XCTAssertThrowsError(try FlorettaMarkdown.importOutline("不是标题\n"))
    }

    func testHeadingExportDropsFieldsThePresetCannotExpress() {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let node = MindMapNode(
            id: id,
            text: "主题\n换行",
            note: "备注",
            isCollapsed: true,
            style: MindMapNodeStyle(colorHex: "#C45C26"),
            position: MindMapPoint(x: 12, y: 34),
            link: "https://example.com/a b",
            side: .left
        )
        var document = MindMapDocument(title: "预设", roots: [node])
        document.addFreeNode(text: "自由", at: MindMapPoint(x: 1, y: 2))
        document.addSticky(text: "便签", at: MindMapPoint(x: 3, y: 4))
        let markdown = FlorettaMarkdown.export(document)
        XCTAssertTrue(markdown.contains("# [主题 换行](https://example.com/a%20b)\n"))
        XCTAssertTrue(markdown.contains("> 备注\n"))
        XCTAssertFalse(markdown.contains(id.uuidString))
        XCTAssertFalse(markdown.contains("#C45C26"))
        XCTAssertFalse(markdown.contains("left"))
        XCTAssertFalse(markdown.contains("自由"))
        XCTAssertFalse(markdown.contains("便签"))
        XCTAssertFalse(markdown.contains("<!--"))
    }

    func testFieldCatalogMatchesTheInRepoTable() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/MARKDOWN-FIELDS.md")
        let markdown = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(MarkdownFieldCatalog.rows.isEmpty)
        for fixture in MarkdownFieldCatalog.documentFixtures + MarkdownFieldCatalog.headingFixtures {
            XCTAssertTrue(markdown.contains(fixture.file), fixture.file)
        }
        for row in MarkdownFieldCatalog.rows {
            let line = "| `\(row.field)` | \(row.disposition.rawValue) |"
            XCTAssertTrue(markdown.contains(line), line)
        }
        XCTAssertTrue(MarkdownFieldCatalog.rows.contains { $0.disposition == .mapped })
        XCTAssertTrue(MarkdownFieldCatalog.rows.contains { $0.disposition == .passthrough })
        XCTAssertTrue(MarkdownFieldCatalog.rows.contains { $0.disposition == .gap })
        XCTAssertEqual(
            MarkdownFieldCatalog.rows.filter { $0.field.hasPrefix("heading") && $0.disposition == .passthrough }.count,
            0
        )
    }

    func testImportThousandHeadingsWithinBudget() throws {
        var lines = ["# 根", ""]
        for index in 0..<1_000 {
            lines.append("## 节点 \(index)")
            lines.append("")
        }
        let text = lines.joined(separator: "\n")
        _ = try FlorettaMarkdown.importOutline("# 预热\n")
        let clock = ContinuousClock()
        let start = clock.now
        let imported = try FlorettaMarkdown.importOutline(text)
        let elapsed = start.duration(to: clock.now)
        XCTAssertEqual(imported.roots[0].children.count, 1_000)
        XCTAssertLessThan(elapsed, .milliseconds(1500), "import of 1000 headings took \(elapsed)")
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

    private func load(_ name: String, folder: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(folder)")
            .appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
