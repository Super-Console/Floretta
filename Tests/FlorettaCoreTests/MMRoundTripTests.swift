import FlorettaCore
import XCTest

final class MMRoundTripTests: XCTestCase {
    func testFixturesRoundTripUnchangedBytes() throws {
        for fixture in MMFieldCatalog.fixtures {
            let data = try load(fixture.file)
            let imported = try FlorettaMMCodec.importMap(data)
            XCTAssertEqual(try FlorettaMMCodec.export(imported), data, fixture.file)
            let stored = try FlorettaCodec.decode(try FlorettaCodec.encode(imported))
            XCTAssertEqual(stored.roots.map(\.text), imported.roots.map(\.text), fixture.file)
            XCTAssertEqual(try FlorettaMMCodec.export(stored), data, fixture.file)
        }
        let plain = try XCTUnwrap(String(data: try FlorettaCodec.encode(MindMapDocument(title: "x", roots: [MindMapNode(text: "y")])), encoding: .utf8))
        XCTAssertFalse(plain.contains("mmForeign"))
    }

    func testSimpleAndNestedMapTheTree() throws {
        let simple = try FlorettaMMCodec.importMap(try load("simple.mm"))
        XCTAssertEqual(simple.roots[0].children.map(\.text), ["甲", "乙"])

        let nested = try FlorettaMMCodec.importMap(try load("nested.mm"))
        let kept = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        XCTAssertEqual(nested.roots[0].id, kept)
        var node = nested.roots[0]
        for expected in ["第1层", "第2层", "第3层", "第4层", "第5层"] {
            XCTAssertEqual(node.text, expected)
            if expected == "第5层" { break }
            node = try XCTUnwrap(node.children.first)
        }
        XCTAssertEqual(nested.roots[0].children[0].side, .right)
        XCTAssertEqual(nested.roots[0].children[0].link, "https://example.com/two")
        let fourth = nested.roots[0].children[0].children[0].children[0]
        XCTAssertTrue(fourth.isCollapsed)
        XCTAssertEqual(fourth.note, "第四")
        XCTAssertEqual(fourth.children[0].side, .left)
        XCTAssertEqual(fourth.children[0].text, "第5层")
    }

    func testPassthroughSurvivesAnEditAndComesBackWhenReverted() throws {
        let data = try load("passthrough.mm")
        var imported = try FlorettaMMCodec.importMap(data)
        XCTAssertEqual(imported.roots[0].text, "父")
        XCTAssertEqual(imported.roots[0].note, "备注")
        XCTAssertFalse(imported.roots[0].note.contains("细节"))
        XCTAssertFalse(imported.roots[0].isCollapsed)
        XCTAssertNil(imported.roots[0].style)
        XCTAssertEqual(imported.roots[0].children.map(\.text), ["子"])
        XCTAssertEqual(imported.roots[0].children[0].side, .left)
        XCTAssertEqual(imported.roots[0].children[0].link, "https://example.com/a?b=1&c=2")

        imported.roots[0].text = "改过"
        let edited = try FlorettaMMCodec.export(imported)
        let editedText = try XCTUnwrap(String(data: edited, encoding: .utf8))
        XCTAssertTrue(editedText.contains("TEXT=\"改过\""))
        XCTAssertTrue(editedText.contains("ID=\"ID_123\""))
        XCTAssertTrue(editedText.contains("COLOR=\"#112233\""))
        XCTAssertTrue(editedText.contains("BACKGROUND_COLOR=\"#fff8e7\""))
        XCTAssertTrue(editedText.contains("CREATED=\"1600000000000\""))
        XCTAssertTrue(editedText.contains("BUILTIN=\"idea\""))
        XCTAssertTrue(editedText.contains("SansSerif"))
        XCTAssertTrue(editedText.contains("bezier"))
        XCTAssertTrue(editedText.contains("DESTINATION=\"ID_123\""))
        XCTAssertTrue(editedText.contains("细节不进备注"))
        XCTAssertTrue(editedText.contains("not-decrypted"))
        XCTAssertTrue(editedText.contains("<b>"))
        XCTAssertTrue(editedText.contains("POSITION=\"left\""))

        let again = try FlorettaMMCodec.importMap(edited)
        XCTAssertEqual(again.roots[0].text, "改过")
        XCTAssertEqual(again.roots[0].note, "备注")
        XCTAssertEqual(again.roots[0].children.count, 1)
        XCTAssertEqual(try FlorettaMMCodec.export(again), edited)

        imported.roots[0].text = "父"
        XCTAssertEqual(try FlorettaMMCodec.export(imported), data)
    }

    func testEditingTheNoteReplacesMarkupAndKeepsIcons() throws {
        var imported = try FlorettaMMCodec.importMap(try load("passthrough.mm"))
        imported.roots[0].note = "新"
        let edited = try XCTUnwrap(String(data: try FlorettaMMCodec.export(imported), encoding: .utf8))
        XCTAssertTrue(edited.contains("<p>新</p>"))
        XCTAssertFalse(edited.contains("<b>"))
        XCTAssertTrue(edited.contains("BUILTIN=\"idea\""))
        XCTAssertTrue(edited.contains("细节不进备注"))
        XCTAssertTrue(edited.contains("COLOR=\"#112233\""))
        XCTAssertTrue(edited.contains("ID=\"ID_123\""))
        let again = try FlorettaMMCodec.importMap(Data(edited.utf8))
        XCTAssertEqual(again.roots[0].note, "新")
        XCTAssertEqual(again.roots[0].text, "父")
    }

    func testExportImportKeepsUUIDShapedIDs() throws {
        let rootID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let childID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let document = MindMapDocument(
            title: "根",
            roots: [
                MindMapNode(
                    id: rootID,
                    text: "根",
                    children: [
                        MindMapNode(id: childID, text: "子", isCollapsed: true, side: .left),
                    ]
                ),
            ]
        )
        let imported = try FlorettaMMCodec.importMap(try FlorettaMMCodec.export(document))
        XCTAssertEqual(imported.roots[0].id, rootID)
        XCTAssertEqual(imported.roots[0].children[0].id, childID)
        XCTAssertTrue(imported.roots[0].children[0].isCollapsed)
        XCTAssertEqual(imported.roots[0].children[0].side, .left)
    }

    func testNativeExportDoesNotInventStyleOrFreeNodes() throws {
        var document = MindMapDocument(
            title: "根",
            roots: [MindMapNode(text: "根", style: MindMapNodeStyle(colorHex: "#C45C26"))]
        )
        document.addFreeNode(text: "自由", at: MindMapPoint(x: 3, y: 4))
        document.addSticky(text: "便签不写", at: MindMapPoint(x: 1, y: 2))
        let xml = try XCTUnwrap(String(data: try FlorettaMMCodec.export(document), encoding: .utf8))
        XCTAssertFalse(xml.contains("#C45C26"))
        XCTAssertFalse(xml.contains("自由"))
        XCTAssertFalse(xml.contains("便签不写"))
        XCTAssertTrue(xml.contains("TEXT=\"根\""))
        XCTAssertTrue(xml.contains(" ID=\""))
    }

    func testFieldCatalogMatchesTheInRepoTable() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/MM-FIELDS.md")
        let markdown = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(MMFieldCatalog.rows.isEmpty)
        var seen: Set<String> = []
        for fixture in MMFieldCatalog.fixtures {
            XCTAssertTrue(markdown.contains(fixture.file), fixture.file)
            XCTAssertTrue(seen.insert(fixture.name).inserted)
        }
        XCTAssertEqual(seen, ["simple", "nested", "passthrough"])
        for row in MMFieldCatalog.rows {
            let line = "| `\(row.field)` | \(row.disposition.rawValue) |"
            XCTAssertTrue(markdown.contains(line), line)
        }
        XCTAssertTrue(MMFieldCatalog.rows.contains { $0.disposition == .mapped })
        XCTAssertTrue(MMFieldCatalog.rows.contains { $0.disposition == .passthrough })
        XCTAssertTrue(MMFieldCatalog.rows.contains { $0.disposition == .gap })
    }

    func testImportThousandNodesWithinBudget() throws {
        var lines = ["<map version=\"1.0.1\"><node TEXT=\"根\">"]
        for index in 0..<1_000 {
            lines.append("<node TEXT=\"n\(index)\" COLOR=\"#010101\"><icon BUILTIN=\"idea\"/></node>")
        }
        lines.append("</node></map>")
        let data = Data(lines.joined().utf8)
        _ = try FlorettaMMCodec.importMap(data)
        let clock = ContinuousClock()
        let start = clock.now
        var imported = try FlorettaMMCodec.importMap(data)
        let elapsed = start.duration(to: clock.now)
        XCTAssertEqual(imported.roots[0].children.count, 1_000)
        XCTAssertLessThan(elapsed, .milliseconds(1500), "import of 1000 nodes took \(elapsed)")
        imported.roots[0].text = "改"
        let edited = try XCTUnwrap(String(data: try FlorettaMMCodec.export(imported), encoding: .utf8))
        XCTAssertTrue(edited.contains("COLOR=\"#010101\""))
        XCTAssertTrue(edited.contains("BUILTIN=\"idea\""))
    }

    private func load(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/MM")
            .appendingPathComponent(name)
        return try Data(contentsOf: url)
    }
}
