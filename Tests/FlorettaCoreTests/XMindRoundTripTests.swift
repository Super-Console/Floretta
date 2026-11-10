import CoreFoundation
import FlorettaCore
import Foundation
import XCTest

final class XMindRoundTripTests: XCTestCase {
    private let editedTitle = "改过的标题-不撞车"

    func testSixFixturesRoundTripUnchangedBytesAndEditedFields() throws {
        for fixture in XMindFieldCatalog.fixtures {
            let data = try load(fixture.file)
            let imported = try FlorettaXMindCodec.importMap(data)
            let unchanged = try FlorettaXMindCodec.export(imported)
            XCTAssertEqual(
                try entry(unchanged, "content.json"),
                try entry(data, "content.json"),
                "\(fixture.name) content.json changed without an edit"
            )
            for name in try names(data) where name != "content.json" {
                XCTAssertEqual(try entry(unchanged, name), try entry(data, name), "\(fixture.name) \(name)")
            }

            var edited = imported
            let originalTitle = edited.roots[0].text
            edited.roots[0].text = editedTitle
            let exported = try FlorettaXMindCodec.export(edited)
            XCTAssertNotEqual(try entry(exported, "content.json"), try entry(data, "content.json"))
            for name in try names(data) where name != "content.json" {
                XCTAssertEqual(try entry(exported, name), try entry(data, name), "\(fixture.name) edited \(name)")
            }
            let again = try FlorettaXMindCodec.importMap(exported)
            XCTAssertEqual(again.roots[0].text, editedTitle, fixture.name)
            XCTAssertEqual(again.roots[0].children.map(\.text), imported.roots[0].children.map(\.text), fixture.name)
            try assertSameJSONAfterRestoringTitle(
                original: try entry(data, "content.json"),
                exported: try entry(exported, "content.json"),
                originalTitle: originalTitle,
                fixture: fixture.name
            )
        }
    }

    func testSimpleMapsNoteAndLinkAndKeepsLabelsOutOfTheModel() throws {
        let imported = try FlorettaXMindCodec.importMap(try load("simple.xmind"))
        XCTAssertEqual(row("topic.title").disposition, .mapped)
        XCTAssertEqual(row("topic.labels").disposition, .passthrough)
        XCTAssertEqual(imported.title, "简单")
        XCTAssertEqual(imported.roots.map(\.text), ["中心"])
        XCTAssertEqual(imported.roots[0].children.map(\.text), ["分支"])
        XCTAssertEqual(imported.roots[0].children[0].note, "一句备注")
        XCTAssertEqual(imported.roots[0].children[0].link, "https://example.com/simple")
        XCTAssertTrue(imported.additionalCanvases.isEmpty)
        XCTAssertNotNil(imported.xmindForeign)
    }

    func testNestedFixtureKeepsFiveLevelsAndDoesNotPromoteSummary() throws {
        let imported = try FlorettaXMindCodec.importMap(try load("nested.xmind"))
        XCTAssertEqual(row("topic.children.attached").disposition, .mapped)
        XCTAssertEqual(row("topic.children.summary").disposition, .mapped)
        XCTAssertEqual(row("topic.summaries").disposition, .mapped)
        XCTAssertEqual(row("topic.boundaries").disposition, .mapped)
        XCTAssertEqual(row("topic.structureClass").disposition, .passthrough)
        var node = imported.roots[0]
        var titles = [node.text]
        while let child = node.children.first {
            titles.append(child.text)
            node = child
        }
        XCTAssertEqual(titles, ["L0", "L1", "L2", "L3", "L4"])
        XCTAssertFalse(node.isCollapsed)
        XCTAssertEqual(row("topic.branch").disposition, .passthrough)
        XCTAssertEqual(row("isCollapsed").disposition, .gap)
        XCTAssertEqual(imported.topicCount, 5)
        let summary = try XCTUnwrap(imported.roots[0].summaries.first)
        XCTAssertEqual(summary.text, "概要")
        XCTAssertEqual(summary.rangeStart, 0)
        XCTAssertEqual(summary.rangeEnd, 0)
        XCTAssertNotEqual(summary.id, imported.roots[0].id)
        XCTAssertFalse(imported.roots[0].children.contains { $0.id == summary.id })
    }

    func testStyledFixtureMapsProperties() throws {
        let imported = try FlorettaXMindCodec.importMap(try load("styled.xmind"))
        let style = try XCTUnwrap(imported.roots[0].children[0].style)
        XCTAssertEqual(row("topic.style.line-color").disposition, .mapped)
        XCTAssertEqual(row("topic.style.shape-class").disposition, .passthrough)
        XCTAssertEqual(style.colorHex, "#C45C26")
        XCTAssertEqual(style.fillHex, "#F4E1D2")
        XCTAssertEqual(style.textHex, "#1A1A1A")
        XCTAssertEqual(style.fontDesign, "Songti SC")
        XCTAssertEqual(style.fontSize, 18)
        XCTAssertEqual(style.bold, true)
        XCTAssertEqual(style.italic, true)
        XCTAssertEqual(style.underline, true)
        XCTAssertEqual(style.strikethrough, true)
        XCTAssertEqual(style.borderHex, "#8C4A2F")
        XCTAssertEqual(style.borderWidth, 2)
        XCTAssertEqual(style.borderStyle, "dash")
        XCTAssertEqual(style.fillStyle, "solid")
    }

    func testRelationshipFixtureMapsEndsAndTitle() throws {
        let imported = try FlorettaXMindCodec.importMap(try load("relationships.xmind"))
        XCTAssertEqual(row("relationship.end1Id").disposition, .mapped)
        XCTAssertEqual(row("relationship.controlPoints").disposition, .passthrough)
        XCTAssertEqual(imported.relationships.count, 1)
        let link = imported.relationships[0]
        XCTAssertEqual(link.title, "关联")
        XCTAssertEqual(link.sourceID, imported.roots[0].children[0].id)
        XCTAssertEqual(link.targetID, imported.roots[0].children[1].id)
    }

    func testAttachmentFixtureMapsResourceAndKeepsBytes() throws {
        let data = try load("attachments.xmind")
        let imported = try FlorettaXMindCodec.importMap(data)
        XCTAssertEqual(row("topic.href xap").disposition, .mapped)
        XCTAssertEqual(row("topic.image").disposition, .passthrough)
        XCTAssertEqual(row("zip entries").disposition, .passthrough)
        let file = try XCTUnwrap(imported.roots[0].children[0].attachments.first)
        XCTAssertEqual(file.filename, "备忘.txt")
        XCTAssertEqual(file.fileExtension, "txt")
        XCTAssertEqual(file.byteCount, Int64("hello floretta\n".utf8.count))
        XCTAssertEqual(file.sha256, sha256Hex(Data("hello floretta\n".utf8)))
        XCTAssertNil(imported.roots[0].children[0].link)
        XCTAssertEqual(try entry(data, "resources/note-txt"), Data("hello floretta\n".utf8))
        XCTAssertEqual(try entry(data, "resources/picture"), Data("PNGDATA".utf8))
    }

    func testMultiSheetFixtureMapsBothCanvases() throws {
        let imported = try FlorettaXMindCodec.importMap(try load("multi-sheet.xmind"))
        XCTAssertEqual(row("additional sheets").disposition, .mapped)
        XCTAssertEqual(row("sheet.legend").disposition, .passthrough)
        XCTAssertEqual(imported.title, "画布甲")
        XCTAssertEqual(imported.roots.map(\.text), ["甲"])
        XCTAssertEqual(imported.additionalCanvases.map(\.title), ["画布乙"])
        XCTAssertEqual(imported.additionalCanvases[0].roots.map(\.text), ["乙"])
        XCTAssertEqual(imported.additionalCanvases[0].roots[0].children.map(\.text), ["乙子"])
        XCTAssertEqual(imported.topicCount, 3)
    }

    func testForeignBagSurvivesFlorettaJSONAndStillWritesOriginalBytes() throws {
        let data = try load("simple.xmind")
        let imported = try FlorettaXMindCodec.importMap(data)
        let decoded = try FlorettaCodec.decode(try FlorettaCodec.encode(imported))
        XCTAssertEqual(decoded.xmindForeign?.contentJSON, imported.xmindForeign?.contentJSON)
        XCTAssertEqual(decoded.roots.map(\.text), imported.roots.map(\.text))
        let exported = try FlorettaXMindCodec.export(decoded)
        XCTAssertEqual(try entry(exported, "content.json"), try entry(data, "content.json"))
        XCTAssertEqual(try entry(exported, "Thumbnails/thumbnail.png"), Data("PNG".utf8))
    }

    func testNonUUIDIdAndUnknownLabelWriteBackAfterEdit() throws {
        let content = """
        [{"id":"sheet-1","class":"sheet","title":"图","topicPositioning":"free","rootTopic":{"id":"center","class":"topic","title":"中心","labels":["keep"]}}]
        """
        let data = workbook(content: content, metadata: #"{"dataStructureVersion":"2","layoutEngineVersion":"3"}"#)
        var imported = try FlorettaXMindCodec.importMap(data)
        XCTAssertEqual(imported.roots.map(\.text), ["中心"])
        imported.roots[0].text = "新的中心"
        let exported = try FlorettaXMindCodec.export(imported)
        let text = try XCTUnwrap(String(data: try entry(exported, "content.json"), encoding: .utf8))
        XCTAssertTrue(text.contains("\"center\""))
        XCTAssertTrue(text.contains("keep"))
        XCTAssertTrue(text.contains("新的中心"))
        XCTAssertEqual(try entry(exported, "metadata.json"), Data(#"{"dataStructureVersion":"2","layoutEngineVersion":"3"}"#.utf8))
        let again = try FlorettaXMindCodec.importMap(exported)
        XCTAssertEqual(again.roots[0].id, imported.roots[0].id)
        XCTAssertEqual(again.roots[0].text, "新的中心")
    }

    func testNestedDetachedStaysOutOfTheTreeAndWritesBack() throws {
        let content = """
        [{"id":"sheet-1","class":"sheet","title":"图","rootTopic":{"id":"root","class":"topic","title":"根","children":{"attached":[{"id":"child","class":"topic","title":"子","children":{"detached":[{"id":"float","class":"topic","title":"内嵌浮动","branch":"folded"}]}}]}}}]
        """
        let data = workbook(content: content, metadata: #"{"dataStructureVersion":"2"}"#)
        var imported = try FlorettaXMindCodec.importMap(data)
        XCTAssertEqual(imported.topicCount, 2)
        XCTAssertTrue(imported.freeNodes.isEmpty)
        XCTAssertEqual(row("topic.children.detached nested").disposition, .passthrough)
        imported.roots[0].text = "根-改"
        let exported = try FlorettaXMindCodec.export(imported)
        let text = try XCTUnwrap(String(data: try entry(exported, "content.json"), encoding: .utf8))
        XCTAssertTrue(text.contains("内嵌浮动"))
        XCTAssertTrue(text.contains("folded"))
        XCTAssertTrue(text.contains("根-改"))
        let again = try FlorettaXMindCodec.importMap(exported)
        XCTAssertEqual(again.topicCount, 2)
        XCTAssertEqual(again.roots[0].text, "根-改")
    }

    func testContentXMLWithoutContentJSONIsRejected() throws {
        let data = ZipArchive.write([
            ZipEntry(name: "content.xml", data: Data("<xmap-content/>".utf8)),
        ])
        XCTAssertThrowsError(try FlorettaXMindCodec.importMap(data)) { error in
            XCTAssertEqual(error as? FlorettaXMindError, .missingContent)
        }
        XCTAssertEqual(row("content.xml").disposition, .gap)
    }

    func testFieldCatalogMatchesTheInRepoTable() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/XMIND-FIELDS.md")
        let markdown = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(XMindFieldCatalog.rows.isEmpty)
        var seen: Set<String> = []
        for fixture in XMindFieldCatalog.fixtures {
            XCTAssertTrue(markdown.contains(fixture.file), fixture.file)
            XCTAssertTrue(seen.insert(fixture.name).inserted)
        }
        XCTAssertEqual(seen, ["simple", "nested", "styled", "relationships", "attachments", "multi-sheet"])
        for row in XMindFieldCatalog.rows {
            let line = "| `\(row.field)` | \(row.disposition.rawValue) |"
            XCTAssertTrue(markdown.contains(line), line)
        }
        XCTAssertTrue(XMindFieldCatalog.rows.contains { $0.disposition == .mapped })
        XCTAssertTrue(XMindFieldCatalog.rows.contains { $0.disposition == .passthrough })
        XCTAssertTrue(XMindFieldCatalog.rows.contains { $0.disposition == .gap })
    }

    func testImportThousandTopicsWithinBudget() throws {
        var children: [String] = []
        children.reserveCapacity(1_000)
        for index in 0..<1_000 {
            let id = String(format: "30000000-0000-4000-8000-%012d", index)
            children.append(#"{"id":"\#(id)","class":"topic","title":"n\#(index)","labels":["k"]}"#)
        }
        let joined = children.joined(separator: ",")
        let content = #"[{"id":"30000000-0000-4000-8000-0000000000aa","class":"sheet","title":"宽","topicPositioning":"free","rootTopic":{"id":"30000000-0000-4000-8000-0000000000bb","class":"topic","title":"根","children":{"attached":[\#(joined)]}}}]"#
        let data = workbook(content: content, metadata: #"{"dataStructureVersion":"2"}"#)
        _ = try FlorettaXMindCodec.importMap(data)
        let clock = ContinuousClock()
        let start = clock.now
        let imported = try FlorettaXMindCodec.importMap(data)
        let elapsed = start.duration(to: clock.now)
        XCTAssertEqual(imported.roots[0].children.count, 1_000)
        // docs/PERF-BUDGET.md is not in the tree. MD-AS-DOCUMENT §8.2 budgets open at <1.5s.
        XCTAssertLessThan(elapsed, .milliseconds(1500), "import of 1000 topics took \(elapsed)")
    }

    private func row(_ field: String) -> XMindFieldRow {
        XMindFieldCatalog.rows.first { $0.field == field }!
    }

    private func load(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/XMind")
            .appendingPathComponent(name)
        return try Data(contentsOf: url)
    }

    private func workbook(content: String, metadata: String) -> Data {
        ZipArchive.write([
            ZipEntry(name: "content.json", data: Data(content.utf8)),
            ZipEntry(name: "metadata.json", data: Data(metadata.utf8)),
            ZipEntry(name: "manifest.json", data: Data(#"{"file-entries":{"content.json":{},"metadata.json":{},"manifest.json":{}}}"#.utf8)),
        ])
    }

    private func names(_ data: Data) throws -> [String] {
        try ZipArchive.read(data, limits: .standard).map(\.name)
    }

    private func entry(_ data: Data, _ name: String) throws -> Data {
        let entries = try ZipArchive.read(data, limits: .standard)
        return try XCTUnwrap(entries.first { $0.name == name }?.data)
    }

    private func assertSameJSONAfterRestoringTitle(
        original: Data,
        exported: Data,
        originalTitle: String,
        fixture: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let left = try JSONSerialization.jsonObject(with: original)
        var right = try JSONSerialization.jsonObject(with: exported)
        right = restoring(right, title: editedTitle, to: originalTitle)
        if let mismatch = jsonDiff(left, right, path: "$") {
            XCTFail("\(fixture) \(mismatch)", file: file, line: line)
        }
    }

    private func restoring(_ value: Any, title: String, to original: String) -> Any {
        if let object = value as? [String: Any] {
            var copy: [String: Any] = [:]
            for (key, child) in object {
                if key == "title", let text = child as? String, text == title {
                    copy[key] = original
                } else {
                    copy[key] = restoring(child, title: title, to: original)
                }
            }
            return copy
        }
        if let array = value as? [Any] {
            return array.map { restoring($0, title: title, to: original) }
        }
        return value
    }

    private func jsonDiff(_ lhs: Any, _ rhs: Any, path: String) -> String? {
        if isNull(lhs) && isNull(rhs) { return nil }
        if let left = lhs as? String, let right = rhs as? String {
            return left == right ? nil : "\(path) string \(left) != \(right)"
        }
        if isBool(lhs) || isBool(rhs) {
            guard isBool(lhs), isBool(rhs), (lhs as? NSNumber)?.boolValue == (rhs as? NSNumber)?.boolValue else {
                return "\(path) bool \(lhs) != \(rhs)"
            }
            return nil
        }
        if let left = lhs as? NSNumber, let right = rhs as? NSNumber {
            return left.doubleValue == right.doubleValue ? nil : "\(path) number \(left) != \(right)"
        }
        if let left = lhs as? [Any], let right = rhs as? [Any] {
            guard left.count == right.count else { return "\(path) array \(left.count) != \(right.count)" }
            for (index, pair) in zip(left, right).enumerated() {
                if let mismatch = jsonDiff(pair.0, pair.1, path: "\(path)[\(index)]") { return mismatch }
            }
            return nil
        }
        if let left = lhs as? [String: Any], let right = rhs as? [String: Any] {
            guard Set(left.keys) == Set(right.keys) else {
                return "\(path) keys \(Set(left.keys).sorted()) != \(Set(right.keys).sorted())"
            }
            for key in left.keys.sorted() {
                if let mismatch = jsonDiff(left[key]!, right[key]!, path: "\(path).\(key)") { return mismatch }
            }
            return nil
        }
        return "\(path) \(lhs) != \(rhs)"
    }

    private func isNull(_ value: Any) -> Bool {
        value is NSNull
    }

    private func isBool(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}
