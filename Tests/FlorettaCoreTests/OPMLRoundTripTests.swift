import FlorettaCore
import XCTest

final class OPMLRoundTripTests: XCTestCase {
    func testFixturesRoundTripUnchangedBytes() throws {
        for fixture in OPMLFieldCatalog.fixtures {
            let data = try load(fixture.file)
            let imported = try FlorettaOPMLCodec.importOutline(data)
            XCTAssertEqual(try FlorettaOPMLCodec.export(imported), data, fixture.file)
            let stored = try FlorettaCodec.decode(try FlorettaCodec.encode(imported))
            XCTAssertEqual(stored.roots.map(\.text), imported.roots.map(\.text), fixture.file)
            XCTAssertEqual(try FlorettaOPMLCodec.export(stored), data, fixture.file)
            let plain = try XCTUnwrap(String(data: try FlorettaCodec.encode(MindMapDocument(title: "x", roots: [MindMapNode(text: "y")])), encoding: .utf8))
            XCTAssertFalse(plain.contains("opmlForeign"))
        }
    }

    func testSimpleAndNestedMapTheOutline() throws {
        let simple = try FlorettaOPMLCodec.importOutline(try load("simple.opml"))
        XCTAssertEqual(simple.title, "简单")
        XCTAssertEqual(simple.roots.map(\.text), ["根"])
        XCTAssertEqual(simple.roots[0].children.map(\.text), ["甲", "乙"])

        let nested = try FlorettaOPMLCodec.importOutline(try load("nested.opml"))
        XCTAssertEqual(nested.title, "五层")
        XCTAssertEqual(nested.roots[0].note, "根注")
        var node = nested.roots[0]
        for expected in ["第1层", "第2层", "第3层", "第4层", "第5层"] {
            XCTAssertEqual(node.text, expected)
            node = node.children.first ?? node
        }
        XCTAssertEqual(nested.roots[0].children[0].link, "https://example.com/two")
        XCTAssertEqual(nested.roots[0].children[0].children[0].children[0].note, "第四")
        XCTAssertTrue(nested.roots[0].children[0].children[0].children[0].children[0].children.isEmpty)
    }

    func testPassthroughSurvivesAnEditAndComesBackWhenReverted() throws {
        let data = try load("passthrough.opml")
        var imported = try FlorettaOPMLCodec.importOutline(data)
        XCTAssertEqual(imported.title, "样本")
        XCTAssertEqual(imported.roots[0].text, "父")
        XCTAssertEqual(imported.roots[0].note, "另一标题")
        XCTAssertEqual(imported.roots[0].children.map(\.text), ["子", "只有标题"])
        XCTAssertEqual(imported.roots[0].children[0].link, "https://example.com/a?b=1&c=2")
        XCTAssertEqual(imported.roots[0].children[0].note, "子注")
        XCTAssertEqual(imported.roots[0].children[1].note, "备用")
        XCTAssertFalse(imported.roots[0].isCollapsed)
        XCTAssertNil(imported.roots[0].side)
        XCTAssertNil(imported.roots[0].position)
        XCTAssertNil(imported.roots[0].style)

        imported.roots[0].text = "改过"
        let edited = try FlorettaOPMLCodec.export(imported)
        let editedText = try XCTUnwrap(String(data: edited, encoding: .utf8))
        XCTAssertTrue(editedText.contains("text=\"改过\""))
        XCTAssertTrue(editedText.contains("expansionState"))
        XCTAssertTrue(editedText.contains("Ada"))
        XCTAssertTrue(editedText.contains("<hook NAME=\"example\"/>"))
        XCTAssertTrue(editedText.contains("xmlUrl=\"https://example.com/feed.xml\""))
        XCTAssertTrue(editedText.contains("title=\"另一标题\""))
        XCTAssertTrue(editedText.contains("_note=\"子注\""))
        XCTAssertTrue(editedText.contains("title=\"只有标题\""))
        XCTAssertFalse(editedText.contains("isCollapsed"))

        let again = try FlorettaOPMLCodec.importOutline(edited)
        XCTAssertEqual(again.roots[0].text, "改过")
        XCTAssertEqual(again.roots[0].note, "另一标题")
        XCTAssertEqual(again.roots[0].children[0].link, "https://example.com/a?b=1&c=2")
        XCTAssertEqual(again.roots[0].children.count, 2)
        XCTAssertEqual(try FlorettaOPMLCodec.export(again), edited)

        imported.roots[0].text = "父"
        XCTAssertEqual(try FlorettaOPMLCodec.export(imported), data)
    }

    func testEditingTheNoteRewritesTheFoldedTitleButKeepsUnknownAttributes() throws {
        var imported = try FlorettaOPMLCodec.importOutline(try load("passthrough.opml"))
        imported.roots[0].note = "新备注"
        let edited = try XCTUnwrap(String(data: try FlorettaOPMLCodec.export(imported), encoding: .utf8))
        XCTAssertTrue(edited.contains("_note=\"新备注\""))
        XCTAssertFalse(edited.contains("另一标题"))
        XCTAssertTrue(edited.contains("type=\"rss\""))
        XCTAssertTrue(edited.contains("<hook NAME=\"example\"/>"))
        let again = try FlorettaOPMLCodec.importOutline(Data(edited.utf8))
        XCTAssertEqual(again.roots[0].note, "新备注")
        XCTAssertEqual(again.roots[0].text, "父")
    }

    func testNativeExportKeepsThePreviousAttributeOrder() throws {
        let root = MindMapNode(
            text: "中心",
            note: "根备注",
            children: [
                MindMapNode(text: "甲", note: "第一行\n第二行"),
                MindMapNode(text: "乙", children: [MindMapNode(text: "孙")]),
            ]
        )
        let document = MindMapDocument(title: "大纲", roots: [root])
        XCTAssertNil(document.opmlForeign)
        let xml = try XCTUnwrap(String(data: try FlorettaOPMLCodec.export(document), encoding: .utf8))
        XCTAssertEqual(
            xml,
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0">
            <head>
            <title>大纲</title>
            </head>
            <body>
              <outline text="中心" _note="根备注">
                <outline text="甲" _note="第一行&#10;第二行"/>
                <outline text="乙">
                  <outline text="孙"/>
                </outline>
              </outline>
            </body>
            </opml>

            """
        )
    }

    func testFieldCatalogMatchesTheInRepoTable() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/OPML-FIELDS.md")
        let markdown = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(OPMLFieldCatalog.rows.isEmpty)
        var seen: Set<String> = []
        for fixture in OPMLFieldCatalog.fixtures {
            XCTAssertTrue(markdown.contains(fixture.file), fixture.file)
            XCTAssertTrue(seen.insert(fixture.name).inserted)
        }
        XCTAssertEqual(seen, ["simple", "nested", "passthrough"])
        for row in OPMLFieldCatalog.rows {
            let line = "| `\(row.field)` | \(row.disposition.rawValue) |"
            XCTAssertTrue(markdown.contains(line), line)
        }
        XCTAssertTrue(OPMLFieldCatalog.rows.contains { $0.disposition == .mapped })
        XCTAssertTrue(OPMLFieldCatalog.rows.contains { $0.disposition == .passthrough })
        XCTAssertTrue(OPMLFieldCatalog.rows.contains { $0.disposition == .gap })
    }

    func testImportThousandOutlinesWithinBudget() throws {
        var lines = ["<opml version=\"2.0\"><head><title>宽</title></head><body><outline text=\"根\">"]
        for index in 0..<1_000 {
            lines.append("<outline text=\"n\(index)\" category=\"k\"/>")
        }
        lines.append("</outline></body></opml>")
        let data = Data(lines.joined().utf8)
        _ = try FlorettaOPMLCodec.importOutline(data)
        let clock = ContinuousClock()
        let start = clock.now
        var imported = try FlorettaOPMLCodec.importOutline(data)
        let elapsed = start.duration(to: clock.now)
        XCTAssertEqual(imported.roots[0].children.count, 1_000)
        XCTAssertLessThan(elapsed, .milliseconds(1500), "import of 1000 outlines took \(elapsed)")
        imported.roots[0].children[0].text = "改"
        let edited = try XCTUnwrap(String(data: try FlorettaOPMLCodec.export(imported), encoding: .utf8))
        XCTAssertTrue(edited.contains("category=\"k\""))
    }

    private func load(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/OPML")
            .appendingPathComponent(name)
        return try Data(contentsOf: url)
    }
}
